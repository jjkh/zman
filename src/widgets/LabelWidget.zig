format: TextFormat,
text_color: Color,

text_list: ArrayList(u8),
allocator: *Allocator,
widget: Widget,

const LabelWidget = @This();

const trace = @import("../trace.zig").trace;
const log = std.log.scoped(.label);

const std = @import("std");
const direct2d = @import("../direct2d.zig");
const Widget = @import("Widget.zig");

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const Direct2D = direct2d.Direct2D;
const Color = direct2d.Color;
const SolidColorBrush = direct2d.SolidColorBrush;
const TextFormat = direct2d.TextFormat;
const RectF = direct2d.RectF;

fn paintFn(w: *Widget, d2d: *Direct2D) anyerror!void {
    const self = @fieldParentPtr(LabelWidget, "widget", w);

    var text_brush = SolidColorBrush{ .color = self.text_color };
    defer text_brush.deinit();
    try d2d.drawTextAlloc(self.allocator, self.text(), self.format, w.absRect(), &text_brush);
}

fn deinitFn(w: *Widget) void {
    const self = @fieldParentPtr(LabelWidget, "widget", w);
    trace(@src(), .{&self});

    self.text_list.deinit();
    self.allocator.destroy(self);
}

pub fn init(allocator: *Allocator, rect: RectF, new_text: []const u8, format: TextFormat, text_color: Color, parent: anytype) !*LabelWidget {
    trace(@src(), .{ rect, parent });

    var label_widget = try allocator.create(LabelWidget);
    label_widget.* = LabelWidget{
        .text_list = try ArrayList(u8).initCapacity(allocator, new_text.len),
        .format = format,
        .text_color = text_color,
        .allocator = allocator,
        .widget = .{ .rect = rect, .paintFn = paintFn, .deinitFn = deinitFn },
    };

    label_widget.text_list.appendSliceAssumeCapacity(new_text);

    if (@typeInfo(@TypeOf(parent)) != .Null) {
        parent.widget.addChild(&label_widget.widget);
    }

    return label_widget;
}

pub fn text(self: LabelWidget) []const u8 {
    return self.text_list.items;
}

pub fn setText(self: *LabelWidget, new_text: []const u8) !void {
    self.text_list.clearRetainingCapacity();
    try self.text_list.appendSlice(new_text);
}

pub fn deinit(self: *LabelWidget) void {
    self.widget.deinit();
}

pub fn relRect(self: LabelWidget) RectF {
    return self.widget.rect;
}
