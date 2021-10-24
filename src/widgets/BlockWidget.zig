bg_color: Color,
border_style: ?BorderStyle = null,
padding: f32 = 0,
radius: f32 = 0,
scroll_pos: ?PointF = null,

resizing_children: bool = false,
scroll_start_offset: f32 = 0,
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

const SCROLLBAR_THICKNESS = 12;
const SCROLLBAR_PADDING = 1.5;
const SCROLLBAR_BG_COLOR = Color.fromU32(0x0D1017FF);
// const SCROLLBAR_BG_COLOR = Color.Transparent;
const SCROLLBAR_FG_COLOR = Color.fromU32(0x22262EFF);

pub const BorderStyle = struct {
    color: Color,
    width: f32,
};

fn paintBorder(self: *BlockWidget, d2d: *Direct2D) !void {
    if (self.border_style) |border_style| {
        // direct2d draws the outline centered on the rect which makes it hard to correctly size widgets
        // instead we offset the rect by the border width in resizeFn, and grow the rect to draw it here
        const border_rect = self.widget.windowRect().grow(border_style.width / 2);

        // first, we need to remove the generic widget clipping rect (as that's for the inner dimension)
        d2d.popAxisAlignedClip();

        var border_brush = SolidColorBrush{ .color = border_style.color };
        defer border_brush.deinit();
        if (self.radius == 0)
            try d2d.outlineRect(border_rect, border_style.width, &border_brush)
        else
            try d2d.outlineRoundedRect(border_rect, border_style.width, &border_brush, self.radius);

        // now we re-add the inner clipping rect (so the border won't be drawn over by child widgets)
        d2d.pushAxisAlignedClip(self.widget.windowRect());
    }
}

fn paintScrollbar(self: *BlockWidget, d2d: *Direct2D) !void {
    if (self.scroll_pos) |scroll_pos| {
        var scrollbar_rect = self.widget.windowRect();
        const total_child_height = self.childHeight();

        // if the children are smaller than the block, don't draw a scrollbar
        // NOTE: this has to match the logic in resizeFn - better if it's calculated once instead
        if (total_child_height < scrollbar_rect.height() or scrollbar_rect.height() <= 0)
            return;

        // draw backgound box for scrollbar
        scrollbar_rect.left = scrollbar_rect.right - SCROLLBAR_THICKNESS;

        var scrollbar_bg_brush = SolidColorBrush{ .color = SCROLLBAR_BG_COLOR };
        defer scrollbar_bg_brush.deinit();
        try d2d.fillRect(scrollbar_rect, &scrollbar_bg_brush);

        // draw the scrollbar 'thumb'
        const scroll_thumb_height = scrollbar_rect.height() * (scrollbar_rect.height() / total_child_height);
        const scroll_thumb_top = -scroll_pos.y * (scrollbar_rect.height() / total_child_height);
        scrollbar_rect.top = scrollbar_rect.top + scroll_thumb_top;
        scrollbar_rect.bottom = scrollbar_rect.top + scroll_thumb_height;
        scrollbar_rect = scrollbar_rect.grow(-SCROLLBAR_PADDING);

        var scrollbar_fg_brush = SolidColorBrush{ .color = SCROLLBAR_FG_COLOR };
        defer scrollbar_fg_brush.deinit();
        try d2d.fillRoundedRect(scrollbar_rect, &scrollbar_fg_brush, SCROLLBAR_THICKNESS / 2.4);
    }
}

fn paintFn(w: *Widget, d2d: *Direct2D) anyerror!void {
    const self = @fieldParentPtr(BlockWidget, "widget", w);

    var bg_brush = SolidColorBrush{ .color = self.bg_color };
    defer bg_brush.deinit();
    if (self.radius == 0)
        try d2d.fillRect(w.windowRect(), &bg_brush)
    else
        try d2d.fillRoundedRect(w.windowRect(), &bg_brush, self.radius);

    try self.paintBorder(d2d);
    try self.paintScrollbar(d2d);
}

fn resizeFn(w: *Widget, new_rect: RectF) bool {
    const self = @fieldParentPtr(BlockWidget, "widget", w);
    if (self.resizing_children) return true;

    // this rect is used to resize children, so it doesn't include the border width
    const rect_excl_border = if (self.border_style) |border_style|
        new_rect.grow(-border_style.width)
    else
        new_rect;

    // if children_not_yet_resized is set, we remove the scrollbar width and call widget.resize() again to
    // propagate that to the children
    var child_rect = rect_excl_border;
    if (self.scroll_pos != null) {
        if (self.childHeight() > child_rect.height() and child_rect.height() > 0)
            child_rect.right -= SCROLLBAR_THICKNESS;
    }

    // TODO: eww
    self.resizing_children = true;
    w.resize(child_rect);
    self.resizing_children = false;

    w.abs_rect = rect_excl_border;
    return false;
}

fn deinitFn(w: *Widget) void {
    const self = @fieldParentPtr(BlockWidget, "widget", w);

    self.allocator.destroy(self);
}

fn childHeight(self: BlockWidget) f32 {
    var total_child_height: f32 = 0;
    {
        var it = self.widget.first_child;
        while (it) |child| : (it = child.next_sibling)
            total_child_height += child.abs_rect.height();
    }

    return total_child_height;
}

pub fn scrollTo(self: *BlockWidget, new_scroll_pos: f32) void {
    if (self.scroll_pos) |*scroll_pos| {
        const total_child_height = self.childHeight();

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

fn onDragEventFn(w: *Widget, event: Widget.DragEvent, point: PointF, _: ?Widget.DragInfo) bool {
    const self = @fieldParentPtr(BlockWidget, "widget", w);
    if (self.scroll_pos == null) return false;

    switch (event) {
        .Start => {
            // TODO: logic (mostly) copied from paintFn, abstract this
            var scrollbar_rect = self.widget.rect();
            const total_child_height = self.childHeight();

            if (total_child_height < scrollbar_rect.height() or scrollbar_rect.height() <= 0)
                return false;

            // TODO: this is a mess. fixing the different coordinate systems is high priority
            scrollbar_rect.left = scrollbar_rect.right - SCROLLBAR_THICKNESS;
            const scroll_thumb_top = -self.scroll_pos.?.y * (scrollbar_rect.height() / total_child_height) - w.windowRect().top;
            const scroll_thumb_height = scrollbar_rect.height() * (scrollbar_rect.height() / total_child_height);
            scrollbar_rect.top = scrollbar_rect.top + scroll_thumb_top;
            scrollbar_rect.bottom = scrollbar_rect.top + scroll_thumb_height;

            if (scrollbar_rect.contains(point)) {
                self.scroll_start_offset = point.y - scrollbar_rect.top;
                return true;
            } else {
                return false;
            }
        },
        .Move, .End => {
            var scrollbar_height = self.widget.windowRect().height();
            const total_child_height = self.childHeight();
            const dy = self.scroll_start_offset - point.y;
            const new_scroll_y = dy * (total_child_height / scrollbar_height);
            self.scrollTo(new_scroll_y);

            return true;
        },
    }
}

pub fn init(allocator: *Allocator, rect: RectF, bg_color: Color, parent: anytype) !*BlockWidget {
    var block_widget = try allocator.create(BlockWidget);
    block_widget.* = BlockWidget{
        .bg_color = bg_color,
        .allocator = allocator,
        .widget = .{ .abs_rect = rect, .resizeFn = resizeFn, .paintFn = paintFn, .deinitFn = deinitFn, .onScrollFn = onScrollFn, .onDragEventFn = onDragEventFn },
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
