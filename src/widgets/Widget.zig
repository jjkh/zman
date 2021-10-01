offset: PointF = .{},
paintFn: ?fn (*Widget, *Direct2D) anyerror!void = null,
deinitFn: ?fn (*Widget) void = null,
resizeFn: ?fn (*Widget, RectF) bool = null,
onMouseEventFn: ?fn (*Widget, MouseEvent, PointF) bool = null,

abs_rect: RectF,
preferred_size: ?PointF = null,
parent: ?*Widget = null,
first_child: ?*Widget = null,
next_sibling: ?*Widget = null,
mouse_inside: bool = false,

const Widget = @This();
const std = @import("std");
const direct2d = @import("../direct2d.zig");

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
    var it = self.first_child;
    while (it) |child| {
        it = child.next_sibling;
        child.deinit();
    }
    self.first_child = null;

    if (self.deinitFn != null) self.deinitFn.?(self);
}

pub fn paint(self: *Widget, d2d: *Direct2D) anyerror!void {
    // currently every widget clips the render output
    // this has a ~20% increase in render time - would be nice to do better
    d2d.pushAxisAlignedClip(self.windowRect());
    defer d2d.popAxisAlignedClip();

    if (self.paintFn != null) try self.paintFn.?(self, d2d);

    var it = self.first_child;
    while (it) |child| : (it = child.next_sibling)
        try child.paint(d2d);
}

pub fn windowRect(self: Widget) RectF {
    if (self.parent) |parent|
        return self.rect().addPoint(parent.windowRect().topLeft())
    else
        return self.rect();
}

pub fn rect(self: Widget) RectF {
    return self.abs_rect.addPoint(self.offset);
}

pub fn addChild(self: *Widget, child: *Widget) void {
    child.parent = self;
    child.next_sibling = self.first_child;
    self.first_child = child;
}

pub fn resize(self: *Widget, new_rect: RectF) void {
    self.abs_rect = new_rect;

    if (self.resizeFn == null or self.resizeFn.?(self, self.rect())) {
        var it = self.first_child;
        while (it) |child| : (it = child.next_sibling)
            child.resize(self.relRect(self.rect()));
    }
}

pub fn relRect(self: Widget, outer: RectF) RectF {
    return outer.addPoint(self.rect().topLeft().neg());
}

fn relPoint(self: Widget, outer: PointF) PointF {
    return outer.add(self.rect().topLeft().neg());
}

// TODO: the widget/window/offset coordinate systems are confusing and almost
// certainly not correct - find a more clear and robust abstraction for them
pub fn onMouseEvent(self: *Widget, event: MouseEvent, point: PointF) bool {
    if (!self.rect().contains(point)) return false;

    switch (event) {
        // shouldn't call generic widget onMouseEvent for enter/leave/over
        .Enter, .Leave, .Move => unreachable,
        else => {},
    }

    var it = self.first_child;
    while (it) |child| : (it = child.next_sibling)
        if (child.onMouseEvent(event, self.relPoint(point))) return true;

    if (self.onMouseEventFn != null)
        return self.onMouseEventFn.?(self, event, self.relPoint(point));

    return false;
}

pub fn onMouseMove(self: *Widget, point: PointF) bool {
    const contains_point = self.rect().contains(point);
    const has_handler = self.onMouseEventFn != null;

    if (!contains_point and !self.mouse_inside) return false;

    var ret = false;

    if (!contains_point and self.mouse_inside) {
        self.mouse_inside = false;
        if (has_handler)
            ret = self.onMouseEventFn.?(self, .Leave, self.relPoint(point));
    }

    if (contains_point and !self.mouse_inside) {
        self.mouse_inside = true;
        if (has_handler)
            ret = self.onMouseEventFn.?(self, .Enter, self.relPoint(point));
    }

    if (contains_point and has_handler) {
        ret = ret or self.onMouseEventFn.?(self, .Move, self.relPoint(point));
    }

    var it = self.first_child;
    while (it) |child| : (it = child.next_sibling)
        ret = ret or child.onMouseMove(self.relPoint(point));

    return ret;
}
