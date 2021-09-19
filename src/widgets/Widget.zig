rect: RectF,
paintFn: fn (*Widget, *Direct2D) anyerror!void,
deinitFn: ?fn (*Widget) void,
resizeFn: ?fn (*Widget, RectF) void = null,

parent: ?*Widget = null,
first_child: ?*Widget = null,
next_sibling: ?*Widget = null,

const Widget = @This();
const std = @import("std");
const direct2d = @import("../direct2d.zig");
const trace = @import("../trace.zig").trace;

const Direct2D = direct2d.Direct2D;
const RectF = direct2d.RectF;
const log = std.log.scoped(.widget);

pub const ChildList = std.SinglyLinkedList(*Widget).Node;

pub fn deinit(self: *Widget) void {
    trace(@src(), .{self});

    var it = self.first_child;
    while (it) |child| {
        it = child.next_sibling;
        child.deinit();
    }
    self.first_child = null;

    if (self.deinitFn) |deinitFunc| deinitFunc(self);
}

pub fn paint(self: *Widget, d2d: *Direct2D) anyerror!void {
    try self.paintFn(self, d2d);

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

    if (self.resizeFn) |resizeFunc| {
        resizeFunc(self, new_rect);
    } else {
        var it = self.first_child;
        while (it) |child| : (it = child.next_sibling)
            child.resize(new_rect.addPoint(self.rect.topLeft().neg()));
    }
}
