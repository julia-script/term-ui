const Tree = @import("../tree/Tree.zig");
const Style = @import("../tree/Style.zig");
const Node = @import("../tree/Node.zig");
const parsers = @import("./styles.zig");
const logger = std.log.scoped(.parse_styles);

const std = @import("std");
pub fn trim(str: []const u8) []const u8 {
    return std.mem.trim(u8, str, " \n\r\t");
}
pub fn parseStyleProperty(tree: *Tree, node_id: Node.NodeId, _key: []const u8, _value: []const u8) void {
    const key = trim(_key);
    const value = trim(_value);

    // Try to use the new StyleProperty API with proper invalidation for supported properties
    // Most common properties first for performance
    if (std.mem.eql(u8, key, "color")) {
        const parsed = parsers.color.parse(value, 0) catch {
            logger.warn("Invalid color value: '{s}'\n", .{value});
            return;
        };
        tree.setStyleProperty(node_id, Tree.StyleProperty{ .color = parsed.value }) catch |err| {
            logger.warn("Error setting color property: {s}\n", .{@errorName(err)});
        };
        return;
    } else if (std.mem.eql(u8, key, "background-color")) {
        const parsed = parsers.background.parse(value, 0) catch {
            logger.warn("Invalid background-color value: '{s}'\n", .{value});
            return;
        };
        tree.setStyleProperty(node_id, Tree.StyleProperty{ .background = parsed.value }) catch |err| {
            logger.warn("Error setting background-color property: {s}\n", .{@errorName(err)});
        };
        return;
    } else if (std.mem.eql(u8, key, "display")) {
        const parsed = parsers.display.parse(value, 0) catch {
            logger.warn("Invalid display value: '{s}'\n", .{value});
            return;
        };
        tree.setStyleProperty(node_id, Tree.StyleProperty{ .display = parsed.value }) catch |err| {
            logger.warn("Error setting display property: {s}\n", .{@errorName(err)});
        };
        return;
    } else if (std.mem.eql(u8, key, "position")) {
        const parsed = parsers.position.parse(value, 0) catch {
            logger.warn("Invalid position value: '{s}'\n", .{value});
            return;
        };
        tree.setStyleProperty(node_id, Tree.StyleProperty{ .position = parsed.value }) catch |err| {
            logger.warn("Error setting position property: {s}\n", .{@errorName(err)});
        };
        return;
    } else if (std.mem.eql(u8, key, "width")) {
        const parsed = parsers.length_percentage_auto.parse(value, 0) catch {
            logger.warn("Invalid width value: '{s}'\n", .{value});
            return;
        };
        tree.setStyleProperty(node_id, Tree.StyleProperty{ .width = parsed.value }) catch |err| {
            logger.warn("Error setting width property: {s}\n", .{@errorName(err)});
        };
        return;
    } else if (std.mem.eql(u8, key, "height")) {
        const parsed = parsers.length_percentage_auto.parse(value, 0) catch {
            logger.warn("Invalid height value: '{s}'\n", .{value});
            return;
        };
        tree.setStyleProperty(node_id, Tree.StyleProperty{ .height = parsed.value }) catch |err| {
            logger.warn("Error setting height property: {s}\n", .{@errorName(err)});
        };
        return;
    } else if (std.mem.eql(u8, key, "text-align")) {
        const parsed = parsers.text_align.parse(value, 0) catch {
            logger.warn("Invalid text-align value: '{s}'\n", .{value});
            return;
        };
        tree.setStyleProperty(node_id, Tree.StyleProperty{ .text_align = parsed.value }) catch |err| {
            logger.warn("Error setting text-align property: {s}\n", .{@errorName(err)});
        };
        return;
    }

    // Fall back to legacy parsing for properties not yet migrated to setStyleProperty
    // For now, just handle these with legacy parsing and manual invalidation

    if (std.mem.eql(u8, key, "overflow-x")) {
        const parsed = parsers.position.parse(value, 0) catch {
            logger.warn("Invalid position value: '{s}'\n", .{value});
            return;
        };
        tree.getNode(node_id).styles.position = parsed.value;
    } else if (std.mem.eql(u8, key, "width")) {
        const parsed = parsers.length_percentage_auto.parse(value, 0) catch {
            logger.warn("Invalid width value: '{s}'\n", .{value});
            return;
        };
        tree.getNode(node_id).styles.size.x = parsed.value;
    } else if (std.mem.eql(u8, key, "height")) {
        const parsed = parsers.length_percentage_auto.parse(value, 0) catch {
            logger.warn("Invalid height value: '{s}'\n", .{value});
            return;
        };
        tree.getNode(node_id).styles.size.y = parsed.value;
    } else if (std.mem.eql(u8, key, "min-width")) {
        const parsed = parsers.length_percentage_auto.parse(value, 0) catch {
            logger.warn("Invalid min-width value: '{s}'\n", .{value});
            return;
        };
        tree.getNode(node_id).styles.min_size.x = parsed.value;
    } else if (std.mem.eql(u8, key, "min-height")) {
        const parsed = parsers.length_percentage_auto.parse(value, 0) catch {
            logger.warn("Invalid min-height value: '{s}'\n", .{value});
            return;
        };
        tree.getNode(node_id).styles.min_size.y = parsed.value;
    } else if (std.mem.eql(u8, key, "max-width")) {
        const parsed = parsers.length_percentage_auto.parse(value, 0) catch {
            logger.warn("Invalid max-width value: '{s}'\n", .{value});
            return;
        };
        tree.getNode(node_id).styles.max_size.x = parsed.value;
    } else if (std.mem.eql(u8, key, "max-height")) {
        const parsed = parsers.length_percentage_auto.parse(value, 0) catch {
            logger.warn("Invalid max-height value: '{s}'\n", .{value});
            return;
        };
        tree.getNode(node_id).styles.max_size.y = parsed.value;
    } else if (std.mem.eql(u8, key, "top")) {
        const parsed = parsers.length_percentage_auto.parse(value, 0) catch {
            logger.warn("Invalid top value: '{s}'\n", .{value});
            return;
        };
        tree.getNode(node_id).styles.inset.top = parsed.value;
    } else if (std.mem.eql(u8, key, "right")) {
        const parsed = parsers.length_percentage_auto.parse(value, 0) catch {
            logger.warn("Invalid right value: '{s}'\n", .{value});
            return;
        };
        tree.getNode(node_id).styles.inset.right = parsed.value;
    } else if (std.mem.eql(u8, key, "bottom")) {
        const parsed = parsers.length_percentage_auto.parse(value, 0) catch {
            logger.warn("Invalid bottom value: '{s}'\n", .{value});
            return;
        };
        tree.getNode(node_id).styles.inset.bottom = parsed.value;
    } else if (std.mem.eql(u8, key, "left")) {
        const parsed = parsers.length_percentage_auto.parse(value, 0) catch {
            logger.warn("Invalid left value: '{s}'\n", .{value});
            return;
        };
        tree.getNode(node_id).styles.inset.left = parsed.value;
    } else if (std.mem.eql(u8, key, "overflow-x")) {
        const parsed = parsers.overflow.parse(value, 0) catch {
            logger.warn("Invalid overflow-x value: '{s}'\n", .{value});
            return;
        };
        tree.getNode(node_id).styles.overflow.x = parsed.value;
    } else if (std.mem.eql(u8, key, "overflow-y")) {
        const parsed = parsers.overflow.parse(value, 0) catch {
            logger.warn("Invalid overflow-y value: '{s}'\n", .{value});
            return;
        };
        tree.getNode(node_id).styles.overflow.y = parsed.value;
    } else if (std.mem.eql(u8, key, "overflow")) {
        const parsed = parsers.utils.parseVecShorthand(parsers.overflow.Overflow, value, 0, parsers.overflow.parse) catch {
            logger.warn("Invalid overflow value: '{s}'\n", .{value});
            return;
        };
        tree.getNode(node_id).styles.overflow = parsed.value;
    } else if (std.mem.eql(u8, key, "gap")) {
        const parsed = parsers.utils.parseVecShorthand(parsers.length_percentage.LengthPercentage, value, 0, parsers.length_percentage.parse) catch {
            logger.warn("Invalid gap value: '{s}'\n", .{value});
            return;
        };
        tree.getNode(node_id).styles.gap = parsed.value;
    } else if (std.mem.eql(u8, key, "aspect-ratio")) {
        // style.aspect_ratio = (try s.number.parse(a, attr.value, 0)).value;
    } else if (std.mem.eql(u8, key, "margin-top")) {
        const parsed = parsers.length_percentage_auto.parse(value, 0) catch {
            logger.warn("Invalid margin-top value: '{s}'\n", .{value});
            return;
        };
        tree.getNode(node_id).styles.margin.top = parsed.value;
    } else if (std.mem.eql(u8, key, "margin-right")) {
        const parsed = parsers.length_percentage_auto.parse(value, 0) catch {
            logger.warn("Invalid margin-right value: '{s}'\n", .{value});
            return;
        };
        tree.getNode(node_id).styles.margin.right = parsed.value;
    } else if (std.mem.eql(u8, key, "margin-bottom")) {
        const parsed = parsers.length_percentage_auto.parse(value, 0) catch {
            logger.warn("Invalid margin-bottom value: '{s}'\n", .{value});
            return;
        };
        tree.getNode(node_id).styles.margin.bottom = parsed.value;
    } else if (std.mem.eql(u8, key, "margin-left")) {
        const parsed = parsers.length_percentage_auto.parse(value, 0) catch {
            logger.warn("Invalid margin-left value: '{s}'\n", .{value});
            return;
        };
        tree.getNode(node_id).styles.margin.left = parsed.value;
    } else if (std.mem.eql(u8, key, "margin")) {
        const parsed = parsers.utils.parseRectShorthand(parsers.length_percentage_auto.LengthPercentageAuto, value, 0, parsers.length_percentage_auto.parse) catch {
            logger.warn("Invalid margin value: '{s}'\n", .{value});
            return;
        };
        tree.getNode(node_id).styles.margin = parsed.value;
    } else if (std.mem.eql(u8, key, "padding-top")) {
        const parsed = parsers.length_percentage.parse(value, 0) catch {
            logger.warn("Invalid padding-top value: '{s}'\n", .{value});
            return;
        };
        tree.getNode(node_id).styles.padding.top = parsed.value;
    } else if (std.mem.eql(u8, key, "padding-right")) {
        const parsed = parsers.length_percentage.parse(value, 0) catch {
            logger.warn("Invalid padding-right value: '{s}'\n", .{value});
            return;
        };
        tree.getNode(node_id).styles.padding.right = parsed.value;
    } else if (std.mem.eql(u8, key, "padding-bottom")) {
        const parsed = parsers.length_percentage.parse(value, 0) catch {
            logger.warn("Invalid padding-bottom value: '{s}'\n", .{value});
            return;
        };
        tree.getNode(node_id).styles.padding.bottom = parsed.value;
    } else if (std.mem.eql(u8, key, "padding-left")) {
        const parsed = parsers.length_percentage.parse(value, 0) catch {
            logger.warn("Invalid padding-left value: '{s}'\n", .{value});
            return;
        };
        tree.getNode(node_id).styles.padding.left = parsed.value;
    } else if (std.mem.eql(u8, key, "padding")) {
        const parsed = parsers.utils.parseRectShorthand(parsers.length_percentage.LengthPercentage, value, 0, parsers.length_percentage.parse) catch {
            logger.warn("Invalid padding value: '{s}'\n", .{value});
            return;
        };
        tree.getNode(node_id).styles.padding = parsed.value;
    } else if (std.mem.eql(u8, key, "flex-direction")) {
        const parsed = parsers.flex_direction.parse(value, 0) catch {
            logger.warn("Invalid flex-direction value: '{s}'\n", .{value});
            return;
        };
        tree.getNode(node_id).styles.flex_direction = parsed.value;
    } else if (std.mem.eql(u8, key, "flex-wrap")) {
        const parsed = parsers.flex_wrap.parse(value, 0) catch {
            logger.warn("Invalid flex-wrap value: '{s}'\n", .{value});
            return;
        };
        tree.getNode(node_id).styles.flex_wrap = parsed.value;
    } else if (std.mem.eql(u8, key, "flex-basis")) {
        const parsed = parsers.length_percentage_auto.parse(value, 0) catch {
            logger.warn("Invalid flex-basis value: '{s}'\n", .{value});
            return;
        };
        tree.getNode(node_id).styles.flex_basis = parsed.value;
    } else if (std.mem.eql(u8, key, "flex-grow")) {
        const parsed = parsers.number.parse(value, 0) catch {
            logger.warn("Invalid flex-grow value: '{s}'\n", .{value});
            return;
        };
        tree.getNode(node_id).styles.flex_grow = parsed.value;
    } else if (std.mem.eql(u8, key, "flex-shrink")) {
        const parsed = parsers.number.parse(value, 0) catch {
            logger.warn("Invalid flex-shrink value: '{s}'\n", .{value});
            return;
        };
        tree.getNode(node_id).styles.flex_shrink = parsed.value;
    } else if (std.mem.eql(u8, key, "align-items")) {
        const parsed = parsers.align_items.parse(value, 0) catch {
            logger.warn("Invalid align-items value: '{s}'\n", .{value});
            return;
        };
        tree.getNode(node_id).styles.align_items = parsed.value;
    } else if (std.mem.eql(u8, key, "align-self")) {
        const parsed = parsers.align_items.parse(value, 0) catch {
            logger.warn("Invalid align-self value: '{s}'\n", .{value});
            return;
        };
        tree.getNode(node_id).styles.align_self = parsed.value;
    } else if (std.mem.eql(u8, key, "justify-items")) {
        const parsed = parsers.align_items.parse(value, 0) catch {
            logger.warn("Invalid justify-items value: '{s}'\n", .{value});
            return;
        };
        tree.getNode(node_id).styles.justify_items = parsed.value;
    } else if (std.mem.eql(u8, key, "justify-self")) {
        const parsed = parsers.align_items.parse(value, 0) catch {
            logger.warn("Invalid justify-self value: '{s}'\n", .{value});
            return;
        };
        tree.getNode(node_id).styles.justify_self = parsed.value;
    } else if (std.mem.eql(u8, key, "align-content")) {
        const parsed = parsers.align_content.parse(value, 0) catch {
            logger.warn("Invalid align-content value: '{s}'\n", .{value});
            return;
        };
        tree.getNode(node_id).styles.align_content = parsed.value;
    } else if (std.mem.eql(u8, key, "justify-content")) {
        const parsed = parsers.align_content.parse(value, 0) catch {
            logger.warn("Invalid justify-content value: '{s}'\n", .{value});
            return;
        };
        tree.getNode(node_id).styles.justify_content = parsed.value;
    } else if (std.mem.eql(u8, key, "color")) {
        const parsed = parsers.color.parse(value, 0) catch {
            logger.warn("Invalid color value: '{s}'\n", .{value});
            return;
        };
        tree.getNode(node_id).styles.foreground_color = parsed.value;
    } else if (std.mem.eql(u8, key, "background-color")) {
        const parsed = parsers.background.parse(value, 0) catch {
            logger.warn("Invalid background-color value: '{s}'\n", .{value});
            return;
        };
        tree.getNode(node_id).styles.background_color = parsed.value;
    } else if (std.mem.eql(u8, key, "text-align")) {
        const parsed = parsers.text_align.parse(value, 0) catch {
            logger.warn("Invalid text-align value: '{s}'\n", .{value});
            return;
        };
        tree.getNode(node_id).styles.text_align = parsed.value;
    } else if (std.mem.eql(u8, key, "white-space")) {
        // Handle white-space shorthand by setting individual longhand properties
        const parsed = parsers.white_space.parse(value, 0) catch {
            logger.warn("Invalid white-space value: '{s}'\n", .{value});
            return;
        };
        const longhand = parsed.value.toLonghand();
        tree.getNode(node_id).styles.white_space_collapse = longhand.collapse;
        tree.getNode(node_id).styles.text_wrap_mode = longhand.wrap_mode;
        tree.getNode(node_id).styles.white_space_trim = longhand.trim;
    } else if (std.mem.eql(u8, key, "white-space-collapse")) {
        // Handle white-space-collapse longhand property
        const parsed = parsers.white_space.parseCollapse(value, 0) catch {
            logger.warn("Invalid white-space-collapse value: '{s}'\n", .{value});
            return;
        };
        tree.getNode(node_id).styles.white_space_collapse = parsed.value;
    } else if (std.mem.eql(u8, key, "text-wrap-mode")) {
        // Handle text-wrap-mode longhand property
        const parsed = parsers.white_space.parseWrapMode(value, 0) catch {
            logger.warn("Invalid text-wrap-mode value: '{s}'\n", .{value});
            return;
        };
        tree.getNode(node_id).styles.text_wrap_mode = parsed.value;
    } else if (std.mem.eql(u8, key, "white-space-trim")) {
        // Handle white-space-trim longhand property
        // TODO: Implement trim parsing when needed
        logger.warn("white-space-trim parsing not yet implemented: '{s}'\n", .{value});
    } else if (std.mem.eql(u8, key, "tab-size")) {
        const parsed = parsers.white_space.parseTabSize(value, 0) catch {
            logger.warn("Invalid tab-size value: '{s}'\n", .{value});
            return;
        };
        tree.getNode(node_id).styles.tab_size = parsed.value;
    } else if (std.mem.eql(u8, key, "font-weight")) {
        const parsed = parsers.font_weight.parse(value, 0) catch {
            logger.warn("Invalid font-weight value: '{s}'\n", .{value});
            return;
        };
        tree.getNode(node_id).styles.font_weight = parsed.value;
    } else if (std.mem.eql(u8, key, "font-style")) {
        const parsed = parsers.font_style.parse(value, 0) catch {
            logger.warn("Invalid font-style value: '{s}'\n", .{value});
            return;
        };
        tree.getNode(node_id).styles.font_style = parsed.value;
    } else if (std.mem.eql(u8, key, "text-decoration")) {
        const parsed = parsers.text_decoration.parse(value, 0) catch {
            logger.warn("Invalid text-decoration value: '{s}'\n", .{value});
            return;
        };
        tree.getNode(node_id).styles.text_decoration = parsed.value;
    } else if (std.mem.eql(u8, key, "border-style-top")) {
        const parsed = parsers.border_style.parse(value, 0) catch {
            logger.warn("Invalid border-style-top value: '{s}'\n", .{value});
            return;
        };
        tree.getNode(node_id).styles.border_style.top = parsed.value;
    } else if (std.mem.eql(u8, key, "border-style-right")) {
        const parsed = parsers.border_style.parse(value, 0) catch {
            logger.warn("Invalid border-style-right value: '{s}'\n", .{value});
            return;
        };
        tree.getNode(node_id).styles.border_style.right = parsed.value;
    } else if (std.mem.eql(u8, key, "border-style-bottom")) {
        const parsed = parsers.border_style.parse(value, 0) catch {
            logger.warn("Invalid border-style-bottom value: '{s}'\n", .{value});
            return;
        };
        tree.getNode(node_id).styles.border_style.bottom = parsed.value;
    } else if (std.mem.eql(u8, key, "border-style-left")) {
        const parsed = parsers.border_style.parse(value, 0) catch {
            logger.warn("Invalid border-style-left value: '{s}'\n", .{value});
            return;
        };
        tree.getNode(node_id).styles.border_style.left = parsed.value;
    } else if (std.mem.eql(u8, key, "border-style")) {
        const parsed = parsers.utils.parseRectShorthand(parsers.border_style.BoxChar.Cell, value, 0, parsers.border_style.parse) catch {
            logger.warn("Invalid border-style value: '{s}'\n", .{value});
            return;
        };
        tree.getNode(node_id).styles.border_style = parsed.value;
    } else if (std.mem.eql(u8, key, "border-color-top")) {
        const parsed = parsers.background.parse(value, 0) catch |err| {
            logger.warn("Invalid border-color-top value: '{s}', {s}\n", .{ value, @errorName(err) });
            return;
        };
        tree.getNode(node_id).styles.border_color.top = parsed.value;
    } else if (std.mem.eql(u8, key, "border-color-right")) {
        const parsed = parsers.background.parse(value, 0) catch |err| {
            logger.warn("Invalid border-color-right value: '{s}', {s}\n", .{ value, @errorName(err) });
            return;
        };
        tree.getNode(node_id).styles.border_color.right = parsed.value;
    } else if (std.mem.eql(u8, key, "border-color-bottom")) {
        const parsed = parsers.background.parse(value, 0) catch |err| {
            logger.warn("Invalid border-color-bottom value: '{s}', {s}\n", .{ value, @errorName(err) });
            return;
        };
        tree.getNode(node_id).styles.border_color.bottom = parsed.value;
    } else if (std.mem.eql(u8, key, "border-color-left")) {
        const parsed = parsers.background.parse(value, 0) catch |err| {
            logger.warn("Invalid border-color-left value: '{s}', {s}\n", .{ value, @errorName(err) });
            return;
        };

        tree.getNode(node_id).styles.border_color.left = parsed.value;
    } else if (std.mem.eql(u8, key, "border-color")) {
        const parsed = parsers.utils.parseRectShorthand(parsers.background.Background, value, 0, parsers.background.parse) catch |err| {
            logger.warn("Invalid border-color value: '{s}', {s}\n", .{ value, @errorName(err) });
            return;
        };

        tree.getNode(node_id).styles.border_color = parsed.value;
    } else if (std.mem.eql(u8, key, "cursor")) {
        const parsed = parsers.cursor.parse(value, 0) catch {
            logger.warn("Invalid cursor value: '{s}'\n", .{value});
            return;
        };
        tree.getNode(node_id).styles.cursor = parsed.value;
    } else if (std.mem.eql(u8, key, "pointer-events")) {
        const parsed = parsers.pointer_events.parse(value, 0) catch {
            logger.warn("Invalid pointer-events value: '{s}'\n", .{value});
            return;
        };
        tree.getNode(node_id).styles.pointer_events = parsed.value;
    } else if (std.mem.eql(u8, key, "z-index")) {
        const parsed = parsers.z_index.parse(value, 0) catch {
            logger.warn("Invalid z-index value: '{s}'\n", .{value});
            return;
        };
        tree.getNode(node_id).styles.z_index = parsed.value;
    } else {
        logger.warn("Unknown style property: '{s}'\n", .{key});
    }
}
pub fn parseStyleString(tree: *Tree, node_id: Node.NodeId, styles: []const u8) !void {
    const slice = trim(styles);
    if (slice.len == 0) {
        return;
    }
    var iter_properties = std.mem.splitSequence(u8, slice, ";");
    while (iter_properties.next()) |_property| {
        const property = trim(_property);

        if (property.len == 0) {
            continue;
        }
        var iter_property = std.mem.splitSequence(u8, property, ":");
        const key = iter_property.next() orelse {
            logger.warn("Invalid property: '{s}'\n", .{property});
            continue;
        };
        // key = trim(key);
        const value = iter_property.next() orelse {
            logger.warn("Invalid property value: '{any}'\n", .{property});
            continue;
        };
        // value = trim(value);
        parseStyleProperty(tree, node_id, key, value);

        // const a = fba.allocator();

    }
    // tree.setStyle(node_id, style);
    // return style;
}
