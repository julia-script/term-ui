const std = @import("std");
const utils = @import("utils.zig");

/// The 'white-space' CSS property shorthand
/// Maps to longhand properties according to W3C spec table
pub const WhiteSpace = enum {
    normal,
    pre,
    @"pre-wrap",
    nowrap,
    inherit,

    /// Convert shorthand to longhand properties per W3C spec
    pub fn toLonghand(self: WhiteSpace) struct {
        collapse: WhiteSpaceCollapse,
        wrap_mode: TextWrapMode,
    } {
        return switch (self) {
            .normal => .{ .collapse = .collapse, .wrap_mode = .wrap },
            .pre => .{ .collapse = .preserve, .wrap_mode = .nowrap },
            .@"pre-wrap" => .{ .collapse = .preserve, .wrap_mode = .wrap },
            .nowrap => .{ .collapse = .collapse, .wrap_mode = .nowrap },
            .inherit => .{ .collapse = .inherit, .wrap_mode = .inherit },
        };
    }
};

/// The 'white-space-collapse' longhand property
/// Controls how white space is collapsed
pub const WhiteSpaceCollapse = enum {
    /// Collapse sequences of white space into single character
    collapse,
    /// Preserve white space sequences, segment breaks as forced line breaks
    preserve,
    /// Collapse white space but preserve segment breaks as forced line breaks
    @"preserve-breaks",
    inherit,
};

/// The 'text-wrap-mode' longhand property  
/// Controls whether lines may wrap at soft wrap opportunities
pub const TextWrapMode = enum {
    /// Content may break across lines at soft wrap opportunities
    wrap,
    /// Content does not break across lines, may overflow
    nowrap,
    inherit,
};

/// The 'tab-size' CSS property
/// Controls the size of tab characters (U+0009) when rendered
pub const TabSize = union(enum) {
    /// Size as a multiple of the advance width of space character (U+0020)
    number: f32,
    /// Size as an absolute length
    length: f32,
    inherit,

    /// Default tab size (8 spaces per spec)
    pub const DEFAULT: TabSize = .{ .number = 8.0 };
};

/// Parse white-space shorthand property
pub fn parse(src: []const u8, pos: usize) utils.ParseError!utils.Result(WhiteSpace) {
    return utils.parseEnum(WhiteSpace, src, pos) orelse error.InvalidSyntax;
}

/// Parse white-space-collapse longhand property
pub fn parseCollapse(src: []const u8, pos: usize) utils.ParseError!utils.Result(WhiteSpaceCollapse) {
    return utils.parseEnum(WhiteSpaceCollapse, src, pos) orelse error.InvalidSyntax;
}

/// Parse text-wrap-mode longhand property
pub fn parseWrapMode(src: []const u8, pos: usize) utils.ParseError!utils.Result(TextWrapMode) {
    return utils.parseEnum(TextWrapMode, src, pos) orelse error.InvalidSyntax;
}

/// Parse tab-size property
pub fn parseTabSize(src: []const u8, pos: usize) utils.ParseError!utils.Result(TabSize) {
    // Try parsing "inherit" first
    if (utils.parseEnum(enum { inherit }, src, pos)) |result| {
        return utils.Result(TabSize){
            .value = .inherit,
            .start = result.start,
            .end = result.end,
        };
    }
    
    // Try parsing as number
    if (utils.parseNumber(src, pos)) |result| {
        const number_value = std.fmt.parseFloat(f32, result.value) catch return error.InvalidSyntax;
        if (number_value < 0) {
            return error.InvalidSyntax; // Negative values not allowed per spec
        }
        return utils.Result(TabSize){
            .value = .{ .number = number_value },
            .start = result.start,
            .end = result.end,
        };
    } else |_| {
        // Number parsing failed, continue to other options
    }
    
    // Try parsing as length (this would need length parsing support)
    // For now, just return error since we don't have length parsing
    return error.InvalidSyntax;
}

// Tests
test "WhiteSpace enum parsing" {
    const testing = std.testing;
    
    // Test valid values
    {
        const result = try parse("normal", 0);
        try testing.expectEqual(WhiteSpace.normal, result.value);
        try testing.expectEqual(@as(usize, 6), result.end);
    }
    
    {
        const result = try parse("pre-wrap", 0);
        try testing.expectEqual(WhiteSpace.@"pre-wrap", result.value);
        try testing.expectEqual(@as(usize, 8), result.end);
    }
    
    // Test invalid value
    try testing.expectError(error.InvalidSyntax, parse("invalid", 0));
}

test "WhiteSpace shorthand to longhand mapping" {
    const testing = std.testing;
    
    // Test normal mode
    {
        const longhand = WhiteSpace.normal.toLonghand();
        try testing.expectEqual(WhiteSpaceCollapse.collapse, longhand.collapse);
        try testing.expectEqual(TextWrapMode.wrap, longhand.wrap_mode);
    }
    
    // Test pre mode
    {
        const longhand = WhiteSpace.pre.toLonghand();
        try testing.expectEqual(WhiteSpaceCollapse.preserve, longhand.collapse);
        try testing.expectEqual(TextWrapMode.nowrap, longhand.wrap_mode);
    }
    
    // Test pre-wrap mode
    {
        const longhand = WhiteSpace.@"pre-wrap".toLonghand();
        try testing.expectEqual(WhiteSpaceCollapse.preserve, longhand.collapse);
        try testing.expectEqual(TextWrapMode.wrap, longhand.wrap_mode);
    }
    
    // Test nowrap mode
    {
        const longhand = WhiteSpace.nowrap.toLonghand();
        try testing.expectEqual(WhiteSpaceCollapse.collapse, longhand.collapse);
        try testing.expectEqual(TextWrapMode.nowrap, longhand.wrap_mode);
    }
}

test "WhiteSpaceCollapse enum parsing" {
    const testing = std.testing;
    
    {
        const result = try parseCollapse("collapse", 0);
        try testing.expectEqual(WhiteSpaceCollapse.collapse, result.value);
    }
    
    {
        const result = try parseCollapse("preserve-breaks", 0);
        try testing.expectEqual(WhiteSpaceCollapse.@"preserve-breaks", result.value);
    }
}

test "TextWrapMode enum parsing" {
    const testing = std.testing;
    
    {
        const result = try parseWrapMode("wrap", 0);
        try testing.expectEqual(TextWrapMode.wrap, result.value);
    }
    
    {
        const result = try parseWrapMode("nowrap", 0);
        try testing.expectEqual(TextWrapMode.nowrap, result.value);
    }
}

test "CSS white-space property parsing integration" {
    const testing = std.testing;
    const mod = @import("../layout/v2/mod.zig");
    
    // Test if the style string is being processed correctly
    {
        const doc_xml = 
            \\<p style="display: block; white-space: normal">Hello world</p>
        ;
        var tree = try mod.docFromXml(testing.allocator, doc_xml, .{});
        defer tree.deinit();
        
        const p_node = tree.getChildren(0).items[0];
        const style = tree.getStyle(p_node);
        
        // Check if display was parsed (this should work)
        std.debug.print("Display: {}\n", .{style.display});
        std.debug.print("WhiteSpace: {}\n", .{style.white_space});
        
        // The display is set by the XML parser, and white-space should be parsed
        // Let's just check if white-space parsing is working
    }
    
    // Test direct style parsing
    {
        const Tree = @import("../tree/Tree.zig");
        var tree = try Tree.init(testing.allocator);
        defer tree.deinit();
        
        const node_id = try tree.createNode();
        
        // Apply style directly
        const parseStyleString = @import("parse-styles.zig").parseStyleString;
        try parseStyleString(&tree, node_id, "white-space: normal");
        
        const style = tree.getStyle(node_id);
        std.debug.print("Direct parsing - WhiteSpace: {}\n", .{style.white_space});
        try testing.expectEqual(WhiteSpace.normal, style.white_space);
    }
}

test "TabSize parsing" {
    const testing = std.testing;
    
    // Test inherit
    {
        const result = try parseTabSize("inherit", 0);
        try testing.expectEqual(TabSize.inherit, result.value);
        try testing.expectEqual(@as(usize, 7), result.end);
    }
    
    // Test number values
    {
        const result = try parseTabSize("4", 0);
        switch (result.value) {
            .number => |val| try testing.expectEqual(@as(f32, 4.0), val),
            else => try testing.expect(false),
        }
        try testing.expectEqual(@as(usize, 1), result.end);
    }
    
    {
        const result = try parseTabSize("8.5", 0);
        switch (result.value) {
            .number => |val| try testing.expectApproxEqAbs(@as(f32, 8.5), val, 0.01),
            else => try testing.expect(false),
        }
        try testing.expectEqual(@as(usize, 3), result.end);
    }
    
    // Test default tab size
    {
        switch (TabSize.DEFAULT) {
            .number => |val| try testing.expectEqual(@as(f32, 8.0), val),
            else => try testing.expect(false),
        }
    }
    
    // Test negative values are rejected
    try testing.expectError(error.InvalidSyntax, parseTabSize("-1", 0));
    
    // Test invalid syntax
    try testing.expectError(error.InvalidSyntax, parseTabSize("invalid", 0));
}