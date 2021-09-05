text: []const u8,
text_format: TextFormat,
brush: SolidColorBrush,

widget: Widget,

const LabelWidget = @This();

const std = @import("std");
const direct2d = @import("../direct2d.zig");
const Widget = @import("Widget.zig");

const Direct2D = direct2d.Direct2D;
const SolidColorBrush = direct2d.SolidColorBrush;
const TextFormat = direct2d.TextFormat;
const RectF = direct2d.RectF;
const log = std.log.scoped(.label);

fn paintFn(w: *Widget, d2d: *Direct2D) anyerror!void {
    const self = @fieldParentPtr(LabelWidget, "widget", w);

    // TODO: fix this
    var buf: [1024]u16 = undefined;
    try d2d.drawTextBuf(&buf, self.text, self.text_format, w.absRect(), self.brush);
}

// label length currently limited to 1024 u16 char
// TODO: use allocator i guess
pub fn init(rect: RectF, text: []const u8, text_format: TextFormat, brush: SolidColorBrush) LabelWidget {
    return .{
        .widget = Widget.init(rect, paintFn),
        .text = text,
        .text_format = text_format,
        .brush = brush,
    };
}

pub fn paint(self: *LabelWidget, d2d: *Direct2D) !void {
    return self.widget.paint(d2d);
}
