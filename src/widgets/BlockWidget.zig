bg_color: Color,
border_style: ?BorderStyle = null,
padding: f32 = 0,
radius: f32 = 0,
scroll_pos: ?PointF = null,

allocator: *Allocator,
widget: Widget,

const BlockWidget = @This();

const log = std.log.scoped(.BlockWidget);

const std = @import("std");
const direct2d = @import("../direct2d.zig");
const Widget = @import("Widget.zig");

const Allocator = std.mem.Allocator;
const Direct2D = direct2d.Direct2D;
const Color = direct2d.Color;
const SolidColorBrush = direct2d.SolidColorBrush;
const PointF = direct2d.PointF;
const RectF = direct2d.RectF;

pub const BorderStyle = struct {
    color: Color,
    width: f32,
};

fn paintFn(w: *Widget, d2d: *Direct2D) anyerror!void {
    const self = @fieldParentPtr(BlockWidget, "widget", w);

    var bg_brush = SolidColorBrush{ .color = self.bg_color };
    defer bg_brush.deinit();
    if (self.radius == 0)
        try d2d.fillRect(w.windowRect(), &bg_brush)
    else
        try d2d.fillRoundedRect(w.windowRect(), &bg_brush, self.radius);

    if (self.border_style) |border_style| {
        // direct2d draws the outline centered on the rect which makes it hard to correctly size widgets
        // instead we offset the rect by the border width in resizeFn, and grow the rect to draw it here
        const border_rect = w.windowRect().grow(border_style.width / 2);

        // first, we need to remove the generic widget clipping rect (as that's for the inner dimension)
        d2d.popAxisAlignedClip();

        var border_brush = SolidColorBrush{ .color = border_style.color };
        defer border_brush.deinit();
        if (self.radius == 0)
            try d2d.outlineRect(border_rect, border_style.width, &border_brush)
        else
            try d2d.outlineRoundedRect(border_rect, border_style.width, &border_brush, self.radius);

        // now we re-add the inner clipping rect (so the border won't be drawn over by child widgets)
        d2d.pushAxisAlignedClip(w.windowRect());
    }
}

fn resizeFn(w: *Widget, new_rect: RectF) bool {
    const self = @fieldParentPtr(BlockWidget, "widget", w);

    // this abs_rect is used to resize children, so it doesn't include the border width
    if (self.border_style) |border_style|
        w.abs_rect = new_rect.grow(-border_style.width);

    return true;
}

fn deinitFn(w: *Widget) void {
    const self = @fieldParentPtr(BlockWidget, "widget", w);

    self.allocator.destroy(self);
}

pub fn scrollTo(self: *BlockWidget, new_scroll_pos: f32) void {
    if (self.scroll_pos) |*scroll_pos| {
        var total_child_height: f32 = 0;
        {
            var it = self.widget.first_child;
            while (it) |child| : (it = child.next_sibling)
                total_child_height += child.abs_rect.height();
        }

        scroll_pos.y = if (total_child_height > self.widget.abs_rect.height())
            std.math.clamp(new_scroll_pos, -(total_child_height - self.widget.abs_rect.height()), 0)
        else
            0;

        {
            var it = self.widget.first_child;
            while (it) |child| : (it = child.next_sibling)
                child.offset.y = scroll_pos.y;
        }
    }
}

fn scrollBy(self: *BlockWidget, scroll_delta: f32) void {
    if (self.scroll_pos) |*scroll_pos|
        self.scrollTo(scroll_pos.y + scroll_delta);
}

fn onScrollFn(w: *Widget, _: PointF, wheel_delta: i32) bool {
    const self = @fieldParentPtr(BlockWidget, "widget", w);
    if (self.scroll_pos != null) {
        self.scrollBy(@intToFloat(f32, @divTrunc(wheel_delta, 3)));
        return true;
    }

    return false;
}

pub fn init(allocator: *Allocator, rect: RectF, bg_color: Color, parent: anytype) !*BlockWidget {
    var block_widget = try allocator.create(BlockWidget);
    block_widget.* = BlockWidget{
        .bg_color = bg_color,
        .allocator = allocator,
        .widget = .{ .abs_rect = rect, .resizeFn = resizeFn, .paintFn = paintFn, .deinitFn = deinitFn, .onScrollFn = onScrollFn },
    };

    if (@typeInfo(@TypeOf(parent)) != .Null) {
        parent.widget.addChild(&block_widget.widget);
    }

    return block_widget;
}

pub fn deinit(self: *BlockWidget) void {
    self.widget.deinit();
}

pub fn paint(self: *BlockWidget, d2d: *Direct2D) !void {
    return self.widget.paint(d2d);
}

pub fn resize(self: *BlockWidget, new_rect: RectF) void {
    self.widget.resize(new_rect);
}

pub fn scrollIntoView(self: *BlockWidget, rect: RectF) void {
    if (self.scroll_pos != null) {
        if (rect.top < 0)
            self.scrollBy(-rect.top)
        else if (rect.bottom > self.widget.rect().height())
            self.scrollBy(self.widget.rect().height() - rect.bottom);
    }
}
