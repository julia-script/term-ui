# LineBuilder Token-Based Design

## Overview

This document describes a token-based approach to text layout that cleanly separates concerns and makes the complex text processing pipeline more manageable. The key insight is to transform the text into a token stream early, then operate on these tokens through distinct phases.

## Motivation

The current implementation has several pain points:
1. **Mixed Concerns**: Line breaking, whitespace collapsing, and fragment reconstruction are intertwined
2. **Complex State Management**: Tracking pending fragments, accumulated width, and break opportunities becomes unwieldy
3. **DOM Range Mapping**: Maintaining the relationship between transformed text and original DOM positions is error-prone
4. **Fragment Boundary Mismatches**: Break opportunities don't respect fragment boundaries (e.g., `"hello wo<span>rld</span>"`)

## Core Concept

Transform the input fragments into a stream of tokens that carry all necessary metadata, then process these tokens through clear, separate phases:

```
Text Nodes → Tokenization → Phase 1 Rules → Line Breaking → Fragment Reconstruction
```

## Token Structure

```zig
const TokenKind = enum {
    text,          // Regular text content
    whitespace,    // Spaces, tabs (not segment breaks)
    segment_break, // Newlines
    atomic,        // Inline-blocks, images, etc.
};

const BreakType = enum {
    mandatory,   // Must break here (after newlines)
    allowed,     // Can break here (after spaces)
    prohibited,  // Cannot break here (middle of words)
};

const Token = struct {
    // Original location - never lost!
    node_id: NodeId,
    dom_range: Range,        // Position in original node's text
    
    // Content (already transformed based on collapse mode)
    text: []const u8,
    kind: TokenKind,
    
    // Line breaking information
    break_after: BreakType,
    
    // Layout info (filled during line breaking phase)
    width: f32 = 0,
    line_index: ?usize = null,
    position_in_line: ?f32 = null,
};
```

## Phase 0: Tokenization

The tokenization phase converts fragments into tokens while respecting line break opportunities:

```zig
fn tokenizeFragments(fragments: []Fragment, collapse_mode: WhiteSpaceCollapse) !TokenList {
    var tokens = TokenList.init(allocator);
    var linebreak_iter = LineBreakStream.init(allocator);
    
    for (fragments) |fragment| {
        if (fragment.is_atomic) {
            // Atomic elements become single tokens
            try tokens.append(.{
                .node_id = fragment.node_id,
                .dom_range = fragment.dom_range,
                .text = fragment.text,
                .kind = .atomic,
                .break_after = .allowed,
            });
            continue;
        }
        
        // Use line breaker to find segment boundaries
        try linebreak_iter.append(fragment.text);
        
        var last_break: usize = 0;
        while (linebreak_iter.next()) |linebreak| {
            const segment = fragment.text[last_break..linebreak.local_i];
            
            try tokenizeAndAppend(
                &tokens,
                segment,
                fragment.node_id,
                .{ .start = last_break, .end = linebreak.local_i },
                linebreak.mandatory,
                collapse_mode,
            );
            
            last_break = linebreak.local_i;
        }
        
        // Handle remaining text after last break
        if (last_break < fragment.text.len) {
            const segment = fragment.text[last_break..];
            try tokenizeAndAppend(&tokens, segment, ...);
        }
    }
    
    return tokens;
}
```

### Tokenization Examples

Input: `"hello   \t\n  world"` with collapse mode
```
Tokens:
[
    {kind: .text, text: "hello", break_after: .prohibited},
    {kind: .whitespace, text: " ", break_after: .allowed},     // "   \t" → " "
    {kind: .segment_break, text: " ", break_after: .allowed},  // "\n" → " "
    {kind: .whitespace, text: " ", break_after: .allowed},     // "  " → " "
    {kind: .text, text: "world", break_after: .prohibited}
]
```

Input: `"hello   world"` with preserve mode
```
Tokens:
[
    {kind: .text, text: "hello", break_after: .prohibited},
    {kind: .whitespace, text: "   ", break_after: .allowed},   // Preserved as-is
    {kind: .text, text: "world", break_after: .prohibited}
]
```

## Phase 1: Whitespace Collapsing Rules

Phase 1 applies CSS whitespace collapsing rules by modifying token text or marking tokens for removal:

```zig
fn applyPhase1Rules(tokens: []Token, collapse_mode: WhiteSpaceCollapse) void {
    switch (collapse_mode) {
        .collapse, .preserve_breaks => {
            // Rule 1: Remove spaces around segment breaks
            for (tokens, 0..) |*token, i| {
                if (token.kind == .segment_break) {
                    // Remove preceding whitespace
                    if (i > 0 and tokens[i-1].kind == .whitespace) {
                        tokens[i-1].text = "";  // Mark for removal
                    }
                    // Remove following whitespace
                    if (i + 1 < tokens.len and tokens[i+1].kind == .whitespace) {
                        tokens[i+1].text = "";
                    }
                }
            }
            
            // Rule 2: Collapse consecutive segment breaks
            var prev_was_segment_break = false;
            for (tokens) |*token| {
                if (token.kind == .segment_break) {
                    if (prev_was_segment_break) {
                        token.text = "";  // Remove consecutive breaks
                    }
                    prev_was_segment_break = true;
                } else {
                    prev_was_segment_break = false;
                }
            }
            
            // Rule 3: Collapse consecutive spaces (already done in tokenization)
        },
        .preserve, .preserve_spaces => {}, // No collapsing needed
    }
}
```

## Phase 2: Line Breaking

Line breaking becomes a simple state machine that processes tokens sequentially:

```zig
fn breakLines(tokens: []Token, available_width: AvailableSpace) !void {
    switch (available_width) {
        .definite => |width| try breakWithWidth(tokens, width),
        .max_content => try breakOnMandatory(tokens),
        .min_content => try breakEverywhere(tokens),
    }
}

fn breakWithWidth(tokens: []Token, width: f32) !void {
    var current_line_width: f32 = 0;
    var current_line: usize = 0;
    
    for (tokens) |*token| {
        // Skip removed tokens
        if (token.text.len == 0) continue;
        
        token.width = measureText(token.text);
        
        // Handle mandatory breaks
        if (token.break_after == .mandatory) {
            token.line_index = current_line;
            token.position_in_line = current_line_width;
            current_line += 1;
            current_line_width = 0;
            continue;
        }
        
        // Check if we need to wrap
        if (current_line_width + token.width > width and 
            token.break_after == .allowed and
            current_line_width > 0) {
            // Start new line
            current_line += 1;
            current_line_width = 0;
        }
        
        // Place token on current line
        token.line_index = current_line;
        token.position_in_line = current_line_width;
        current_line_width += token.width;
    }
}
```

## Phase 3: Fragment Reconstruction

Finally, we reconstruct fragments from tokens, merging adjacent tokens from the same node:

```zig
fn reconstructFragments(tokens: []Token) !LineBoxList {
    var lines = LineBoxList.init(allocator);
    var current_line = LineBox.init();
    var current_line_index: ?usize = null;
    
    for (tokens) |token| {
        // Skip removed tokens
        if (token.text.len == 0) continue;
        
        // Start new line if needed
        if (current_line_index != token.line_index) {
            if (current_line.fragments.len > 0) {
                try lines.append(current_line);
                current_line = LineBox.init();
            }
            current_line_index = token.line_index;
        }
        
        // Try to merge with previous fragment if from same node
        const last_fragment = current_line.fragments.getLastOrNull();
        if (last_fragment != null and 
            last_fragment.node_id == token.node_id and
            last_fragment.dom_range.end == token.dom_range.start) {
            // Extend previous fragment
            last_fragment.text = extendText(last_fragment.text, token.text);
            last_fragment.dom_range.end = token.dom_range.end;
            last_fragment.size.x += token.width;
        } else {
            // Create new fragment
            try current_line.fragments.append(.{
                .text = token.text,
                .node_id = token.node_id,
                .dom_range = token.dom_range,
                .position = .{ .x = token.position_in_line, .y = 0 },
                .size = .{ .x = token.width, .y = 1 },
            });
        }
    }
    
    if (current_line.fragments.len > 0) {
        try lines.append(current_line);
    }
    
    return lines;
}
```

## Benefits

### 1. **Clean Separation of Concerns**
Each phase has a single, well-defined responsibility. No more mixing line breaking logic with whitespace collapsing.

### 2. **Trivial DOM Range Mapping**
Every token maintains its origin throughout all transformations:
```zig
// Even after all transformations, we know:
token.node_id      // Which node this came from
token.dom_range    // Exact position in original text
```

### 3. **Debuggability**
Can inspect and validate the token stream at each phase:
```zig
const tokens = try tokenize(fragments);
debug.printTokens("After tokenization", tokens);

applyPhase1Rules(&tokens);
debug.printTokens("After Phase 1", tokens);

try breakLines(&tokens);
debug.printTokens("After line breaking", tokens);
```

### 4. **Performance**
- **No string allocations**: Tokens point to slices of original text or static strings like `" "`
- **Cache-friendly**: Linear iteration through contiguous token array
- **Predictable memory access**: CPU can effectively prefetch
- **Potential for SIMD**: Operations like "mark all spaces" could be vectorized

### 5. **Extensibility**
- Easy to add new token types (e.g., for inline formatting)
- New whitespace rules can be added to Phase 1 without touching other code
- Different line breaking strategies can be plugged in

## Implementation Notes

### Memory Management
- Use arena allocator for tokens - all freed at once
- Token text fields point to original strings or static constants
- Only allocate when reconstructing final fragments

### Edge Cases Handled Naturally
- **Fragment boundaries**: No longer relevant during processing
- **Atomic elements**: Just another token type
- **Mixed whitespace**: Each run is a separate token with clear behavior
- **Lookahead problem**: No need for pending fragments - we have all tokens upfront

### Testing Strategy
1. Test each phase independently with known token inputs
2. Round-trip tests: tokenize → process → reconstruct should preserve semantics
3. Snapshot tests on token streams make debugging easier

## Future Extensions

This design makes several future features much easier:

1. **Hyphenation**: Add hyphenation points as special tokens
2. **Justification**: Adjust whitespace token widths during line breaking
3. **Bidirectional text**: Add direction info to tokens
4. **Ruby annotations**: Add annotation tokens that don't affect line breaking
5. **Advanced typography**: Kerning adjustments can be applied to tokens

### Caching Optimization

During a single layout calculation, the LineBuilder may be called multiple times with the same text but different available widths (e.g., when determining intrinsic sizes). We can cache intermediate results:

```zig
const TokenCache = struct {
    // Cache key: text content + collapse mode
    fragments_hash: u64,
    collapse_mode: WhiteSpaceCollapse,
    
    // Cached results
    tokens_raw: ?TokenList,         // Initial tokenization with segments
    tokens_phase1: ?TokenList,      // After Phase 1 whitespace rules
    
    pub fn getCachedTokens(self: *@This(), hash: u64, mode: WhiteSpaceCollapse) ?TokenList {
        if (self.fragments_hash == hash and self.collapse_mode == mode) {
            return self.tokens_phase1 orelse self.tokens_raw;
        }
        return null;
    }
};
```

**Caching Strategy:**
1. **Always tokenize with line breaker**: Even for nowrap/max-content, we need proper segments
2. **Cache raw tokens**: The expensive Unicode line break analysis is done once
3. **Cache Phase 1 results**: Whitespace collapsing is also text-dependent, not width-dependent
4. **Never cache line breaking**: This is the only phase that depends on available width

**Usage Pattern:**
```zig
// First call: max-content
//   - Full tokenization with line breaker (cached)
//   - Apply Phase 1 rules (cached)
//   - Simple line breaking (only on mandatory breaks)

// Second call: min-content  
//   - Reuse cached tokens
//   - Reuse cached Phase 1 results
//   - Aggressive line breaking (every allowed break)

// Third call: definite 300px
//   - Reuse cached tokens
//   - Reuse cached Phase 1 results  
//   - Width-based line breaking

// Fourth call: definite 400px
//   - Reuse cached tokens
//   - Reuse cached Phase 1 results
//   - Different width-based line breaking
```

This way, expensive operations (Unicode line breaking, whitespace collapsing) are done only once per text content, regardless of wrap mode or available width.

## Implementation Plan

### 1. Create New Directory Structure
Create a fresh directory `packages/core/src/layout/v2/line-builder/` with:

```
layout/v2/line-builder/
├── LineBuilder.zig          # Main entry point with same public API
├── Token.zig                # Token type definitions
├── Tokenizer.zig            # Tokenization logic
├── WhitespaceRules.zig      # Phase 1 whitespace collapsing
├── LineBreaker.zig          # Line breaking logic
├── FragmentBuilder.zig      # Fragment reconstruction
├── LineBox.zig              # Copy of LineBox structure
├── LineBoxFragment.zig      # Copy of fragment structure
└── __tests__/               # New test directory
    └── LineBuilder.test.zig
```

### 2. Update computeInlineContextLayout.zig
Update the import in `packages/core/src/layout/v2/block/computeInlineContextLayout.zig`:

```zig
// Change from:
const LineBuilder = @import("../text/LineBuilder.zig");

// To:
const LineBuilder = @import("../line-builder/LineBuilder.zig");
```

The public API remains the same, so no other changes needed in the caller.

### 3. Implementation Strategy
1. Start by copying `LineBox.zig` and relevant structures to establish the foundation
2. Implement the token types and tokenizer first
3. Add each phase incrementally with tests
4. Keep the old `text/LineBuilder.zig` as reference material

### 4. Benefits of Fresh Start
- Clean, modular architecture from the beginning
- Each phase in its own file for clarity
- No legacy code to work around
- Clear separation from the current implementation

## Conclusion

By transforming the problem into token processing, we get a cleaner, more maintainable, and more correct implementation. The initial complexity of tokenization is more than offset by the simplification of every subsequent operation.