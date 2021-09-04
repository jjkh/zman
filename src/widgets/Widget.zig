rect: RectF,

parent: ?*Widget = null,
node: ChildList.Node = undefined,
children: ChildList = .{},

paintFn: fn (*Widget, *Direct2D) PaintError!void,

const Widget = @This();
const std = @import("std");
const direct2d = @import("../direct2d.zig");

const Direct2D = direct2d.Direct2D;
const RectF = direct2d.RectF;

pub const PaintError = error{};
pub const ChildList = std.SinglyLinkedList(*Widget);

pub fn init(rect: RectF, paintFn: fn (*Widget, *Direct2D) PaintError!void) Widget {
    var widget = Widget{
        .rect = rect,
        .paintFn = paintFn,
    };

    return widget;
}

pub fn paint(self: *Widget, d2d: *Direct2D) PaintError!void {
    try self.paintFn(self, d2d);

    var it = self.children.first;
    while (it) |child| : (it = child.next)
        try child.data.paint(d2d);
}

pub fn absRect(self: Widget) RectF {
    if (self.parent) |parent|
        return self.rect.addPoint(parent.rect.topLeft());

    return self.rect;
}

// TODO: something better than this - can't call from init due to references being made to old copies
pub fn addChild(self: *Widget, child: *Widget) void {
    child.node = .{ .data = child };
    self.children.prepend(&child.node);
    child.node.data.parent = self;
}
