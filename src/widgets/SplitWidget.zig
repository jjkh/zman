orientation: SplitOrientation,

inner_widgets: ArrayList(*Widget),
allocator: *Allocator,
widget: Widget,

const SplitWidget = @This();

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

fn resizeFn(w: *Widget, new_rect: RectF) bool {
    const self = @fieldParentPtr(SplitWidget, "widget", w);

    if (self.inner_widgets.items.len == 0) return false;

    var variable_dist: f32 = undefined;
    var variable_count: usize = 0;
    if (self.orientation == .Horizontal) {
        variable_dist = new_rect.width();
        for (self.inner_widgets.items) |inner_widget| {
            if (inner_widget.preferred_size) |preferred_size| {
                if (preferred_size.x > 0) {
                    variable_dist -= preferred_size.x;
                    continue;
                }
            }

            variable_count += 1;
        }
    } else {
        variable_dist = new_rect.height();
        for (self.inner_widgets.items) |inner_widget| {
            if (inner_widget.preferred_size) |preferred_size| {
                if (preferred_size.y > 0) {
                    variable_dist -= preferred_size.y;
                    continue;
                }
            }

            variable_count += 1;
        }
    }

    const single_dist = if (variable_count > 0) variable_dist / @intToFloat(f32, variable_count) else 0;

    var offset: f32 = 0;
    if (self.orientation == .Horizontal) {
        for (self.inner_widgets.items) |inner_widget| {
            var new_inner_rect = RectF{
                .top = 0,
                .bottom = w.rect().height(),
                .left = offset,
                .right = offset + single_dist,
            };

            if (inner_widget.preferred_size) |preferred_size| {
                if (preferred_size.x > 0) {
                    new_inner_rect.left = offset;
                    new_inner_rect.right = offset + preferred_size.x;
                }

                if (preferred_size.y > 0) {
                    const new_height = std.math.min(new_rect.height(), preferred_size.y);
                    const y_offset = (new_rect.height() - new_height) / 2;
                    new_inner_rect.top = y_offset;
                    new_inner_rect.bottom = y_offset + new_height;
                }
            }

            inner_widget.resize(new_inner_rect);
            offset = new_inner_rect.right;
        }
    } else {
        for (self.inner_widgets.items) |inner_widget| {
            var new_inner_rect = RectF{
                .top = offset,
                .bottom = offset + single_dist,
                .left = 0,
                .right = new_rect.width(),
            };

            if (inner_widget.preferred_size) |preferred_size| {
                if (preferred_size.y > 0) {
                    new_inner_rect.top = offset;
                    new_inner_rect.bottom = offset + preferred_size.y;
                }

                if (preferred_size.x > 0) {
                    const new_width = std.math.min(new_rect.width(), preferred_size.x);
                    const x_offset = (new_rect.width() - new_width) / 2;
                    new_inner_rect.left = x_offset;
                    new_inner_rect.right = x_offset + new_width;
                }
            }

            inner_widget.resize(new_inner_rect);
            offset = new_inner_rect.bottom;
        }
    }

    return false;
}

fn deinitFn(w: *Widget) void {
    const self = @fieldParentPtr(SplitWidget, "widget", w);

    self.inner_widgets.deinit();
    self.allocator.destroy(self);
}

pub fn init(allocator: *Allocator, rect: RectF, direction: SplitOrientation, parent: anytype) !*SplitWidget {
    var split_widget = try allocator.create(SplitWidget);

    split_widget.* = SplitWidget{
        .inner_widgets = ArrayList(*Widget).init(allocator),
        .orientation = direction,
        .allocator = allocator,
        .widget = .{ .abs_rect = rect, .resizeFn = resizeFn, .deinitFn = deinitFn },
    };

    if (@typeInfo(@TypeOf(parent)) != .Null)
        parent.widget.addChild(&split_widget.widget);

    return split_widget;
}

pub fn deinit(self: *SplitWidget) void {
    self.widget.deinit();
}

pub fn addWidget(self: *SplitWidget, new_widget: anytype) !void {
    if (new_widget.widget.parent == null)
        self.widget.addChild(&new_widget.widget)
    else
        return error.WidgetAlreadyHasParent;

    try self.inner_widgets.append(&new_widget.widget);
    self.resize(self.widget.rect());
}

pub fn paint(self: *SplitWidget, d2d: *Direct2D) !void {
    return self.widget.paint(d2d);
}

pub fn resize(self: *SplitWidget, new_rect: RectF) void {
    self.widget.resize(new_rect);
}

pub fn onMouseEvent(self: *SplitWidget, event: Widget.MouseEvent, point: PointF) bool {
    return self.widget.onMouseEvent(event, point);
}

pub fn onMouseMove(self: *SplitWidget, point: PointF) bool {
    return self.widget.onMouseMove(point);
}
