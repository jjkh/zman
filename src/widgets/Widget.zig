rect: RectF,
paintFn: ?fn (*Widget, *Direct2D) anyerror!void = null,
deinitFn: ?fn (*Widget) void = null,
resizeFn: ?fn (*Widget, RectF) void = null,
onMouseEventFn: ?fn (*Widget, MouseEvent, PointF) bool = null,

parent: ?*Widget = null,
first_child: ?*Widget = null,
next_sibling: ?*Widget = null,
mouse_inside: bool = false,

const Widget = @This();
const std = @import("std");
const direct2d = @import("../direct2d.zig");
const trace = @import("../trace.zig").trace;

const Direct2D = direct2d.Direct2D;
const PointF = direct2d.PointF;
const RectF = direct2d.RectF;
const log = std.log.scoped(.widget);

pub const MouseEvent = enum {
    Down,
    Up,
    Enter,
    Leave,
    Move,
};

pub fn deinit(self: *Widget) void {
    trace(@src(), .{self});

    var it = self.first_child;
    while (it) |child| {
        it = child.next_sibling;
        child.deinit();
    }
    self.first_child = null;

    if (self.deinitFn != null) self.deinitFn.?(self);
}

pub fn paint(self: *Widget, d2d: *Direct2D) anyerror!void {
    if (self.paintFn != null) try self.paintFn.?(self, d2d);

    var it = self.first_child;
    while (it) |child| : (it = child.next_sibling)
        try child.paint(d2d);
}

pub fn absRect(self: Widget) RectF {
    if (self.parent) |parent|
        return self.rect.addPoint(parent.absRect().topLeft())
    else
        return self.rect;
}

pub fn addChild(self: *Widget, child: *Widget) void {
    trace(@src(), .{ self, child });

    child.parent = self;
    child.next_sibling = self.first_child;
    self.first_child = child;
}

pub fn resize(self: *Widget, new_rect: RectF) void {
    trace(@src(), .{ self, new_rect });

    self.rect = new_rect;

    if (self.resizeFn != null) {
        self.resizeFn.?(self, new_rect);
    } else {
        var it = self.first_child;
        while (it) |child| : (it = child.next_sibling)
            child.resize(self.relRect(new_rect));
    }
}

fn relRect(self: Widget, outer: RectF) RectF {
    return outer.addPoint(self.rect.topLeft().neg());
}

fn relPoint(self: Widget, outer: PointF) PointF {
    return outer.add(self.rect.topLeft().neg());
}

pub fn onMouseEvent(self: *Widget, event: MouseEvent, point: PointF) bool {
    // shouldn't call generic widget onMouseEvent for enter/leave/over
    switch (event) {
        .Enter, .Leave, .Move => unreachable,
        else => {},
    }

    if (!self.rect.contains(point)) return false;

    var it = self.first_child;
    while (it) |child| : (it = child.next_sibling)
        if (child.onMouseEvent(event, self.relPoint(point))) return true;

    if (self.onMouseEventFn != null)
        return self.onMouseEventFn.?(self, event, point);

    return false;
}

pub fn onMouseMove(self: *Widget, point: PointF) bool {
    const contains_point = self.rect.contains(point);
    const has_handler = self.onMouseEventFn != null;

    if (!contains_point and !self.mouse_inside) return false;

    var ret = false;

    if (!contains_point and self.mouse_inside) {
        self.mouse_inside = false;
        if (has_handler)
            ret = self.onMouseEventFn.?(self, .Leave, point);
    }

    if (contains_point and !self.mouse_inside) {
        self.mouse_inside = true;
        if (has_handler)
            ret = self.onMouseEventFn.?(self, .Enter, point);
    }

    if (contains_point and has_handler) {
        ret = ret or self.onMouseEventFn.?(self, .Move, point);
    }

    var it = self.first_child;
    while (it) |child| : (it = child.next_sibling)
        ret = ret or child.onMouseMove(self.relPoint(point));

    return ret;
}
