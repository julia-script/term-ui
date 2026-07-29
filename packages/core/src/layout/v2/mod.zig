const std = @import("std");
const point = @import("../point.zig");
const rect = @import("../rect.zig");
pub const constants = @import("./constants.zig");

pub const LayoutTree = @import("./LayoutTree.zig");
pub const LayoutContext = @import("./LayoutContext.zig");
pub const LayoutNode = LayoutTree.LayoutNode;
pub const LayoutResult = @import("./LayoutResult.zig");
pub const computeBlockLayout = @import("./block/computeBlockLayout.zig").computeBlockLayout;
pub const computeFlexboxLayout = @import("./flex/computeFlexboxLayout.zig").computeFlexboxLayout;
pub const computeInlineContextLayout = @import("./block/computeInlineContextLayout.zig").computeInlineContextLayout;
pub const docFromXml = @import("./doc-from-xml.zig").docFromXml;
pub const computeChildLayout = @import("./computeChildLayout.zig").computeChildLayout;
pub const performChildLayout = @import("./performChildLayout.zig").performChildLayout;
pub const computeLayout = @import("./computeLayout.zig").computeLayout;

pub const CSSPoint = point.CSSPoint;
pub const CSSMaybePoint = point.CSSMaybePoint;
pub const CSSRect = rect.CSSRect;
pub const CSSMaybeRect = rect.CSSMaybeRect;

pub const RectOf = rect.Of;
pub const PointOf = point.Of;
pub const ContainerContext = @import("./ContainerContext.zig");
pub const ComputeLayoutError = error{ OutOfMemory, FailedToComputeChildLayout };
pub const Box = @import("./Box.zig");
pub const logger = std.log.scoped(.layout);
pub const math = @import("./math.zig");
pub const CollapsibleMarginSet = @import("../compute/compute_constants.zig").CollapsibleMarginSet;
pub const computeContentSizeContribution = @import("flex/computeContentSizeContribution.zig").computeContentSizeContribution;

pub const CSSLine = @import("../line.zig").CSSLine;
pub const CSSMaybeLine = @import("../line.zig").CSSMaybeLine;
pub const LineOf = @import("../line.zig").Of;
pub const Line = @import("../line.zig").Line;

pub const LineBox = @import("./line-builder/LineBox.zig");
pub const LineBoxFragment = @import("./line-builder/LineBoxFragment.zig");
pub const LineBoxList = LineBox.LineBoxList;

pub const RenderList = @import("./RenderList.zig");
pub const RenderListBuilder = @import("./RenderListBuilder.zig");
pub const compute = @import("./line-builder/compute.zig").compute;

test {
    std.testing.refAllDecls(@This());
}
