const std = @import("std");

/// Style inheritance type - controls how properties are cascaded
pub const Inheritance = enum {
    /// Property will never inherit from parent
    none,

    /// Property always inherits from parent if not explicitly set
    inherit,

    /// Property inherits only when explicitly set to inherit
    explicit,
};

/// Maps style properties to their inheritance behavior
pub const PropertyInheritance = struct {
    // Text properties
    text_align: Inheritance = .explicit,
    white_space: Inheritance = .explicit,
    tab_size: Inheritance = .inherit,
    foreground_color: Inheritance = .inherit,
    line_height: Inheritance = .inherit,

    // Text formatting properties
    font_weight: Inheritance = .explicit,
    font_style: Inheritance = .explicit,
    text_decoration: Inheritance = .explicit,

    // Background properties
    background_color: Inheritance = .none,

    // Layout properties (mostly don't inherit)
    display: Inheritance = .none,
    position: Inheritance = .none,
    inset: Inheritance = .none,
    size: Inheritance = .none,
    min_size: Inheritance = .none,
    max_size: Inheritance = .none,
    aspect_ratio: Inheritance = .none,
    margin: Inheritance = .none,
    padding: Inheritance = .none,
    border: Inheritance = .none,
    overflow: Inheritance = .none,

    // Flex properties
    flex_direction: Inheritance = .none,
    flex_wrap: Inheritance = .none,
    flex_basis: Inheritance = .none,
    flex_grow: Inheritance = .none,
    flex_shrink: Inheritance = .none,
    align_items: Inheritance = .none,
    align_self: Inheritance = .none,
    justify_items: Inheritance = .none,
    justify_self: Inheritance = .none,
    align_content: Inheritance = .none,
    justify_content: Inheritance = .none,
    gap: Inheritance = .none,
};

/// Default inheritance table for all properties
pub const DEFAULT_INHERITANCE = PropertyInheritance{};

/// Manages style property origins for cascade resolution
pub const StyleOrigin = enum {
    /// User agent (browser default) styles - lowest priority
    user_agent,

    /// User styles (custom user preferences)
    user,

    /// Author styles (from the application/document)
    author,

    /// Inline styles directly on the element - highest priority (except !important)
    @"inline",
};

/// Style priority for cascade resolution
pub const StylePriority = enum {
    /// Normal priority
    normal,

    /// Important (!important) priority - overrides everything
    important,
};
