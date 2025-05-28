const std = @import("std");
const AvailableSpace = @import("../constants.zig").AvailableSpace;
const Token = @import("Token.zig");
const LineBreakStream = @import("../../../uni/LineBreakStream.zig");
const GraphemeIterator = @import("../../grapheme.zig").GraphemeIterator;

pub const LineBreaker = struct {
    tokens: []const Token,
    available_width: AvailableSpace,
    white_space_mode: WhiteSpaceMode,
    line_break_stream: LineBreakStream,
    
    // Current state
    current_token_index: usize = 0,
    current_char_offset: usize = 0,
    
    pub const WhiteSpaceMode = enum {
        normal,
        nowrap,
        pre,
        @"pre-wrap",
        @"pre-line",
    };
    
    pub const Line = struct {
        start_token: usize,
        end_token: usize, // exclusive
        start_offset: usize,
        end_offset: usize,
        width: f32,
        has_trailing_spaces: bool,
    };
    
    pub const BreakOpportunity = struct {
        token_index: usize,
        char_offset: usize,
        is_mandatory: bool,
        is_soft_wrap: bool,
    };
    
    pub fn init(
        tokens: []const Token,
        available_width: AvailableSpace,
        white_space_mode: WhiteSpaceMode,
        allocator: std.mem.Allocator,
    ) !LineBreaker {
        // Gather all text content for line break analysis
        var text_builder = std.ArrayList(u8).init(allocator);
        defer text_builder.deinit();
        
        for (tokens) |token| {
            switch (token.kind) {
                .text, .whitespace => try text_builder.appendSlice(token.text),
                .segment_break => {
                    // Line break stream needs actual breaks for analysis
                    if (token.text.len > 0) {
                        try text_builder.append(token.text[0]);
                    } else {
                        try text_builder.append('\n');
                    }
                },
                .atomic => {}, // Atomics don't contribute to line breaking
            }
        }
        
        return LineBreaker{
            .tokens = tokens,
            .available_width = available_width,
            .white_space_mode = white_space_mode,
            .line_break_stream = try LineBreakStream.initWithData(allocator, text_builder.items),
        };
    }
    
    pub fn deinit(self: *LineBreaker) void {
        self.line_break_stream.deinit();
    }
    
    /// Get the next line of tokens that fits within available width
    pub fn nextLine(self: *LineBreaker, allocator: std.mem.Allocator) !?Line {
        if (self.current_token_index >= self.tokens.len) {
            return null;
        }
        
        // Handle different wrapping modes
        return switch (self.available_width) {
            .definite => |width| try self.nextLineWithWidth(width, allocator),
            .max_content => try self.nextLineMaxContent(allocator),
            .min_content => try self.nextLineMinContent(allocator),
        };
    }
    
    fn nextLineWithWidth(self: *LineBreaker, width: f32, allocator: std.mem.Allocator) !Line {
        const start_token = self.current_token_index;
        const start_offset = self.current_char_offset;
        var line_width: f32 = 0;
        var last_break_opportunity: ?BreakOpportunity = null;
        var has_trailing_spaces = false;
        
        // Special handling for nowrap and pre modes
        if (self.white_space_mode == .nowrap or self.white_space_mode == .pre) {
            // These modes only break at mandatory breaks
            return try self.nextLineNoWrap(allocator);
        }
        
        while (self.current_token_index < self.tokens.len) {
            const token = self.tokens[self.current_token_index];
            
            switch (token.kind) {
                .text => {
                    // Measure each grapheme cluster
                    var iter = try GraphemeIterator.init(token.text);
                    var local_offset: usize = 0;
                    
                    while (iter.next()) |grapheme| {
                        const grapheme_width = measureGrapheme(grapheme);
                        
                        // Check if adding this would exceed width
                        if (line_width + grapheme_width > width and line_width > 0) {
                            // Need to break - use last opportunity if available
                            if (last_break_opportunity) |opp| {
                                return self.createLineAtBreak(start_token, start_offset, opp, line_width);
                            }
                            // No break opportunity - break before this token
                            if (self.current_token_index > start_token) {
                                return Line{
                                    .start_token = start_token,
                                    .end_token = self.current_token_index,
                                    .start_offset = start_offset,
                                    .end_offset = 0,
                                    .width = line_width,
                                    .has_trailing_spaces = has_trailing_spaces,
                                };
                            }
                            // Must include at least this grapheme
                        }
                        
                        line_width += grapheme_width;
                        local_offset += grapheme.len;
                        
                        // Check for break opportunity after this grapheme
                        if (try self.canBreakAfter(token, local_offset)) {
                            last_break_opportunity = BreakOpportunity{
                                .token_index = self.current_token_index,
                                .char_offset = self.current_char_offset + local_offset,
                                .is_mandatory = false,
                                .is_soft_wrap = true,
                            };
                        }
                    }
                    self.current_char_offset += token.text.len;
                },
                
                .whitespace => {
                    const space_width = @as(f32, @floatFromInt(token.text.len));
                    line_width += space_width;
                    has_trailing_spaces = true;
                    
                    // Whitespace is always a break opportunity
                    last_break_opportunity = BreakOpportunity{
                        .token_index = self.current_token_index + 1,
                        .char_offset = 0,
                        .is_mandatory = false,
                        .is_soft_wrap = false,
                    };
                    
                    self.current_char_offset = 0;
                },
                
                .segment_break => {
                    // Mandatory break - end line here
                    self.current_token_index += 1;
                    self.current_char_offset = 0;
                    
                    return Line{
                        .start_token = start_token,
                        .end_token = self.current_token_index,
                        .start_offset = start_offset,
                        .end_offset = 0,
                        .width = line_width,
                        .has_trailing_spaces = has_trailing_spaces,
                    };
                },
                
                .atomic => {
                    const atomic_width = token.size.x;
                    
                    // Check if atomic would overflow
                    if (line_width + atomic_width > width and line_width > 0) {
                        // Break before atomic
                        if (last_break_opportunity) |opp| {
                            return self.createLineAtBreak(start_token, start_offset, opp, line_width);
                        }
                        // No break opportunity - must break here
                        return Line{
                            .start_token = start_token,
                            .end_token = self.current_token_index,
                            .start_offset = start_offset,
                            .end_offset = 0,
                            .width = line_width,
                            .has_trailing_spaces = has_trailing_spaces,
                        };
                    }
                    
                    line_width += atomic_width;
                    has_trailing_spaces = false;
                    self.current_char_offset = 0;
                },
            }
            
            self.current_token_index += 1;
        }
        
        // End of tokens
        return Line{
            .start_token = start_token,
            .end_token = self.tokens.len,
            .start_offset = start_offset,
            .end_offset = self.current_char_offset,
            .width = line_width,
            .has_trailing_spaces = has_trailing_spaces,
        };
    }
    
    fn nextLineMaxContent(self: *LineBreaker, allocator: std.mem.Allocator) !Line {
        // Max content: never wrap except at mandatory breaks
        return try self.nextLineNoWrap(allocator);
    }
    
    fn nextLineMinContent(self: *LineBreaker, _: std.mem.Allocator) !Line {
        // Min content: wrap at every opportunity
        const start_token = self.current_token_index;
        const start_offset = self.current_char_offset;
        var line_width: f32 = 0;
        const has_trailing_spaces = false;
        
        while (self.current_token_index < self.tokens.len) {
            const token = self.tokens[self.current_token_index];
            
            switch (token.kind) {
                .text => {
                    // For min-content, we don't break in the middle of words
                    var iter = try GraphemeIterator.init(token.text);
                    while (iter.next()) |grapheme| {
                        const grapheme_width = measureGrapheme(grapheme);
                        line_width += grapheme_width;
                    }
                    self.current_char_offset = 0;
                },
                
                .whitespace => {
                    // Always break after whitespace in min-content
                    const space_width = @as(f32, @floatFromInt(token.text.len));
                    line_width += space_width;
                    self.current_token_index += 1;
                    self.current_char_offset = 0;
                    
                    return Line{
                        .start_token = start_token,
                        .end_token = self.current_token_index,
                        .start_offset = start_offset,
                        .end_offset = 0,
                        .width = line_width,
                        .has_trailing_spaces = true,
                    };
                },
                
                .segment_break, .atomic => {
                    // Handle these the same as in regular wrapping
                    if (token.kind == .segment_break) {
                        self.current_token_index += 1;
                        self.current_char_offset = 0;
                    } else {
                        line_width += token.size.x;
                        self.current_token_index += 1;
                        self.current_char_offset = 0;
                    }
                    
                    return Line{
                        .start_token = start_token,
                        .end_token = self.current_token_index,
                        .start_offset = start_offset,
                        .end_offset = 0,
                        .width = line_width,
                        .has_trailing_spaces = token.kind == .segment_break,
                    };
                },
            }
            
            self.current_token_index += 1;
        }
        
        // End of tokens
        return Line{
            .start_token = start_token,
            .end_token = self.tokens.len,
            .start_offset = start_offset,
            .end_offset = self.current_char_offset,
            .width = line_width,
            .has_trailing_spaces = has_trailing_spaces,
        };
    }
    
    fn nextLineNoWrap(self: *LineBreaker, _: std.mem.Allocator) !Line {
        // No wrapping - only break at mandatory breaks
        const start_token = self.current_token_index;
        const start_offset = self.current_char_offset;
        var line_width: f32 = 0;
        var has_trailing_spaces = false;
        
        while (self.current_token_index < self.tokens.len) {
            const token = self.tokens[self.current_token_index];
            
            if (token.kind == .segment_break) {
                // Mandatory break
                self.current_token_index += 1;
                self.current_char_offset = 0;
                return Line{
                    .start_token = start_token,
                    .end_token = self.current_token_index,
                    .start_offset = start_offset,
                    .end_offset = 0,
                    .width = line_width,
                    .has_trailing_spaces = has_trailing_spaces,
                };
            }
            
            // Add token width
            switch (token.kind) {
                .text => {
                    var iter = try GraphemeIterator.init(token.text);
                    while (iter.next()) |grapheme| {
                        line_width += measureGrapheme(grapheme);
                    }
                    self.current_char_offset = 0;
                },
                .whitespace => {
                    line_width += @as(f32, @floatFromInt(token.text.len));
                    has_trailing_spaces = true;
                    self.current_char_offset = 0;
                },
                .atomic => {
                    line_width += token.size.x;
                    has_trailing_spaces = false;
                    self.current_char_offset = 0;
                },
                .segment_break => unreachable,
            }
            
            self.current_token_index += 1;
        }
        
        // End of tokens
        return Line{
            .start_token = start_token,
            .end_token = self.tokens.len,
            .start_offset = start_offset,
            .end_offset = self.current_char_offset,
            .width = line_width,
            .has_trailing_spaces = has_trailing_spaces,
        };
    }
    
    fn canBreakAfter(self: *LineBreaker, token: Token, offset: usize) !bool {
        // Use the line break stream to determine if we can break here
        // This is a simplified version - real implementation would track position
        _ = self;
        _ = token;
        _ = offset;
        // TODO: Properly integrate with LineBreakStream
        return true;
    }
    
    fn createLineAtBreak(
        self: *LineBreaker,
        start_token: usize,
        start_offset: usize,
        break_opp: BreakOpportunity,
        line_width: f32,
    ) Line {
        self.current_token_index = break_opp.token_index;
        self.current_char_offset = break_opp.char_offset;
        
        return Line{
            .start_token = start_token,
            .end_token = break_opp.token_index,
            .start_offset = start_offset,
            .end_offset = break_opp.char_offset,
            .width = line_width,
            .has_trailing_spaces = break_opp.is_soft_wrap,
        };
    }
    
    fn measureGrapheme(grapheme: []const u8) f32 {
        // Simplified measurement - 1 unit per grapheme
        // Real implementation would use font metrics
        _ = grapheme;
        return 1.0;
    }
};