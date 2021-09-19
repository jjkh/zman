orientation: SplitOrientation,

inner_widgets: ArrayList(*Widget),
allocator: *Allocator,
widget: Widget,

const SplitWidget = @This();

const trace = @import("../trace.zig").trace;
const log = std.log.scoped(.SplitWidget);

const std = @import("std");
const direct2d = @import("../direct2d.zig");
const Widget = @import("Widget.zig");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Direct2D = direct2d.Direct2D;
const RectF = direct2d.RectF;
const PointF = direct2d.PointF;

const SplitOrientation = enum {
    Vertical,
    Horizontal,
};

fn resizeFn(w: *Widget, new_rect: RectF) void {
    const self = @fieldParentPtr(SplitWidget, "widget", w);
    trace(@src(), .{ &self, new_rect, self.inner_widgets.items.len });

    if (self.inner_widgets.items.len == 0) return;

    const widget_count = @intToFloat(f32, self.inner_widgets.items.len);
    var size = new_rect.size().toRect();
    var offset = PointF{ .x = 0, .y = 0 };
    if (self.orientation == .Vertical) {
        size.bottom /= widget_count;
        offset.y = size.bottom;
    } else {
        size.right /= widget_count;
        offset.x = size.right;
    }

    for (self.inner_widgets.items) |inner_widget| {
        inner_widget.resize(size);
        size = size.addPoint(offset);
    }
}

fn paintFn(w: *Widget, _: *Direct2D) anyerror!void {
    const self = @fieldParentPtr(SplitWidget, "widget", w);
    trace(@src(), .{&self});
}

fn deinitFn(w: *Widget) void {
    const self = @fieldParentPtr(SplitWidget, "widget", w);
    trace(@src(), .{&self});

    self.inner_widgets.deinit();
    self.allocator.destroy(self);
}

pub fn init(allocator: *Allocator, rect: RectF, direction: SplitOrientation, parent: anytype) !*SplitWidget {
    trace(@src(), .{ rect, parent });

    var split_widget = try allocator.create(SplitWidget);
    split_widget.* = SplitWidget{
        .inner_widgets = ArrayList(*Widget).init(allocator),
        .orientation = direction,
        .allocator = allocator,
        .widget = .{ .rect = rect, .resizeFn = resizeFn, .paintFn = paintFn, .deinitFn = deinitFn },
    };

    if (@typeInfo(@TypeOf(parent)) != .Null)
        parent.widget.addChild(&split_widget.widget);

    return split_widget;
}

pub fn deinit(self: *SplitWidget) void {
    trace(@src(), .{});

    self.widget.deinit();
}

pub fn addWidget(self: *SplitWidget, new_widget: anytype) !void {
    trace(@src(), .{ self, &new_widget });

    if (new_widget.widget.parent == null)
        self.widget.addChild(&new_widget.widget)
    else
        return error.WidgetAlreadyHasParent;

    try self.inner_widgets.append(&new_widget.widget);
    self.resize(self.relRect());
}

pub fn paint(self: *SplitWidget, d2d: *Direct2D) !void {
    trace(@src(), .{});

    return self.widget.paint(d2d);
}

pub fn resize(self: *SplitWidget, new_rect: RectF) void {
    trace(@src(), .{new_rect});

    self.widget.resize(new_rect);
}

pub fn relRect(self: SplitWidget) RectF {
    trace(@src(), .{});

    return self.widget.rect;
}
