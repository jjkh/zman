bg_brush: SolidColorBrush,
border: ?BorderStyle = null,

widget: Widget,

const BlockWidget = @This();

const std = @import("std");
const direct2d = @import("../direct2d.zig");
const Widget = @import("Widget.zig");

const Direct2D = direct2d.Direct2D;
const SolidColorBrush = direct2d.SolidColorBrush;
const RectF = direct2d.RectF;

pub const BorderStyle = struct {
    brush: SolidColorBrush,
    width: f32,
};

fn paintFn(w: *Widget, d2d: *Direct2D) anyerror!void {
    const self = @fieldParentPtr(BlockWidget, "widget", w);
    d2d.fillRect(w.absRect(), self.bg_brush);

    if (self.border) |style|
        d2d.outlineRect(w.absRect(), style.width, style.brush);
}

pub fn init(rect: RectF, bg_brush: SolidColorBrush) BlockWidget {
    return .{
        .widget = Widget.init(rect, paintFn),
        .bg_brush = bg_brush,
    };
}

pub fn paint(self: *BlockWidget, d2d: *Direct2D) !void {
    return self.widget.paint(d2d);
}

pub fn addChild(self: *BlockWidget, child: anytype) void {
    self.widget.addChild(&child.widget);
}

pub fn relRect(self: BlockWidget) RectF {
    return self.widget.rect;
}
