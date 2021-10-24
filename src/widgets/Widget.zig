offset: PointF = .{},
paintFn: ?fn (*Widget, *Direct2D) anyerror!void = null,
deinitFn: ?fn (*Widget) void = null,
resizeFn: ?fn (*Widget, RectF) bool = null,
onMouseEventFn: ?fn (*Widget, MouseEvent, PointF) bool = null,
onScrollFn: ?fn (*Widget, PointF, i32) bool = null,
onDragEventFn: ?fn (*Widget, DragEvent, PointF, ?DragInfo) bool = null,

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
    DblClick,
    Enter,
    Leave,
    Move,
};

pub const DragEvent = enum {
    Start,
    End,
    Move,
};

pub const DragInfo = struct {
    widget: *Widget,
    from: PointF,
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

    if (self.resizeFn == null or self.resizeFn.?(self, new_rect)) {
        var it = self.first_child;
        while (it) |child| : (it = child.next_sibling)
            child.resize(self.relRect(self.rect()));
    }
}

pub fn relRect(self: Widget, outer_rect: RectF) RectF {
    return outer_rect.addPoint(self.rect().topLeft().neg());
}

fn relPoint(self: Widget, outer_point: PointF) PointF {
    return outer_point.add(self.rect().topLeft().neg());
}

// TODO: the widget/window/offset coordinate systems are confusing and almost
// certainly not correct - find a more clear and robust abstraction for them
pub fn onMouseEvent(self: *Widget, event: MouseEvent, point: PointF) bool {
    if (!self.rect().contains(point)) return false;

    switch (event) {
        // some messages are not propogated to children
        .Enter, .Leave, .Move => {},
        else => {
            var it = self.first_child;
            while (it) |child| : (it = child.next_sibling)
                if (child.onMouseEvent(event, self.relPoint(point))) return true;
        },
    }

    if (self.onMouseEventFn != null)
        return self.onMouseEventFn.?(self, event, self.relPoint(point));

    return false;
}

pub fn onDragStart(self: *Widget, point: PointF) ?DragInfo {
    if (!self.rect().contains(point))
        return null;

    var it = self.first_child;
    while (it) |child| : (it = child.next_sibling) {
        const result = child.onDragStart(self.relPoint(point));
        if (result != null) return result;
    }

    if (self.onDragEventFn != null and self.onDragEventFn.?(self, .Start, self.relPoint(point), null))
        return DragInfo{ .widget = self, .from = point };

    return null;
}

pub fn onDragEvent(self: *Widget, event: DragEvent, point: PointF, drag_info: DragInfo) bool {
    if (event == .Start) {
        log.crit("{*}: onDragEvent should not be called on drag start! [point={}, drag_info={}]", .{ self, point, drag_info });
        unreachable;
    }

    var it = self.first_child;
    while (it) |child| : (it = child.next_sibling)
        if (child.onDragEvent(event, self.relPoint(point), drag_info)) return true;

    if (self.onDragEventFn != null)
        return self.onDragEventFn.?(self, event, self.relPoint(point), drag_info);

    return false;
}

pub fn onMouseMove(self: *Widget, point: PointF) bool {
    const contains_point = self.rect().contains(point);

    if (!contains_point and !self.mouse_inside)
        return false;

    var ret = blk: {
        if (!contains_point and self.mouse_inside) {
            self.mouse_inside = false;
            break :blk self.onMouseEvent(.Leave, point);
        }
        if (contains_point and !self.mouse_inside) {
            self.mouse_inside = true;
            break :blk self.onMouseEvent(.Enter, point);
        }

        break :blk false;
    };

    if (contains_point)
        ret = self.onMouseEvent(.Move, point) or ret;

    var it = self.first_child;
    while (it) |child| : (it = child.next_sibling)
        ret = child.onMouseMove(self.relPoint(point)) or ret;

    return ret;
}

pub fn onScroll(self: *Widget, point: PointF, wheel_delta: i32) bool {
    if (!self.rect().contains(point)) return false;

    var it = self.first_child;
    while (it) |child| : (it = child.next_sibling)
        if (child.onScroll(self.relPoint(point), wheel_delta)) return true;

    if (self.onScrollFn != null)
        return self.onScrollFn.?(self, self.relPoint(point), wheel_delta);

    return false;
}
