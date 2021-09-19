text_format: TextFormat,
text_color: Color,

labels: ArrayList(*LabelWidget),
allocator: *Allocator,
widget: Widget,

const ListBoxWidget = @This();

const trace = @import("../trace.zig").trace;
const log = std.log.scoped(.ListBoxWidget);

const std = @import("std");
const direct2d = @import("../direct2d.zig");
const Widget = @import("Widget.zig");
const LabelWidget = @import("LabelWidget.zig");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Direct2D = direct2d.Direct2D;
const Color = direct2d.Color;
const TextFormat = direct2d.TextFormat;
const RectF = direct2d.RectF;

const LINE_SPACING = 20;

fn resizeFn(w: *Widget, new_rect: RectF) void {
    const self = @fieldParentPtr(ListBoxWidget, "widget", w);
    trace(@src(), .{ &self, new_rect, self.labels.items.len });

    var label_rect = new_rect.size().toRect();
    label_rect.bottom = LINE_SPACING;

    for (self.labels.items) |label| {
        label.widget.resize(label_rect);
        label_rect.top += LINE_SPACING;
        label_rect.bottom += LINE_SPACING;
    }
}

fn paintFn(w: *Widget, _: *Direct2D) anyerror!void {
    const self = @fieldParentPtr(ListBoxWidget, "widget", w);
    trace(@src(), .{&self});
}

fn deinitFn(w: *Widget) void {
    const self = @fieldParentPtr(ListBoxWidget, "widget", w);
    trace(@src(), .{&self});

    self.labels.deinit();
    self.allocator.destroy(self);
}

pub fn init(
    allocator: *Allocator,
    rect: RectF,
    text_format: TextFormat,
    text_color: Color,
    items: []const []const u8,
    parent: anytype,
) !*ListBoxWidget {
    trace(@src(), .{ rect, parent });

    var list_box_widget = try allocator.create(ListBoxWidget);
    list_box_widget.* = ListBoxWidget{
        .text_format = text_format,
        .text_color = text_color,
        .labels = try ArrayList(*LabelWidget).initCapacity(allocator, items.len),
        .allocator = allocator,
        .widget = .{ .rect = rect, .resizeFn = resizeFn, .paintFn = paintFn, .deinitFn = deinitFn },
    };

    if (@typeInfo(@TypeOf(parent)) != .Null)
        parent.widget.addChild(&list_box_widget.widget);

    for (items) |item|
        try list_box_widget.addItem(item);

    return list_box_widget;
}

pub fn deinit(self: *ListBoxWidget) void {
    trace(@src(), .{});

    self.widget.deinit();
}

pub fn addItem(self: *ListBoxWidget, text: []const u8) !void {
    var label = try LabelWidget.init(self.allocator, .{}, text, self.text_format, self.text_color, self);
    try self.labels.append(label);

    self.resize(self.relRect());
}

pub fn paint(self: *ListBoxWidget, d2d: *Direct2D) !void {
    trace(@src(), .{});

    return self.widget.paint(d2d);
}

pub fn resize(self: *ListBoxWidget, new_rect: RectF) void {
    trace(@src(), .{new_rect});

    self.widget.resize(new_rect);
}

pub fn relRect(self: ListBoxWidget) RectF {
    trace(@src(), .{});

    return self.widget.rect;
}
