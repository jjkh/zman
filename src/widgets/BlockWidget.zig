bg_color: Color,
border_style: ?BorderStyle = null,
padding: f32 = 0,
radius: f32 = 0,

allocator: *Allocator,
widget: Widget,

const BlockWidget = @This();

const trace = @import("../trace.zig").trace;
const log = std.log.scoped(.BlockWidget);

const std = @import("std");
const direct2d = @import("../direct2d.zig");
const Widget = @import("Widget.zig");

const Allocator = std.mem.Allocator;
const Direct2D = direct2d.Direct2D;
const Color = direct2d.Color;
const SolidColorBrush = direct2d.SolidColorBrush;
const RectF = direct2d.RectF;

pub const BorderStyle = struct {
    color: Color,
    width: f32,
};

fn paintFn(w: *Widget, d2d: *Direct2D) anyerror!void {
    const self = @fieldParentPtr(BlockWidget, "widget", w);
    trace(@src(), .{&self});

    var bg_brush = SolidColorBrush{ .color = self.bg_color };
    defer bg_brush.deinit();
    if (self.radius == 0)
        try d2d.fillRect(w.windowRect(), &bg_brush)
    else
        try d2d.fillRoundedRect(w.windowRect(), &bg_brush, self.radius);

    if (self.border_style) |border_style| {
        var border_brush = SolidColorBrush{ .color = border_style.color };
        defer border_brush.deinit();
        if (self.radius == 0)
            try d2d.outlineRect(w.windowRect(), border_style.width, &border_brush)
        else
            try d2d.outlineRoundedRect(w.windowRect(), border_style.width, &border_brush, self.radius);
    }
}

fn resizeFn(w: *Widget, new_rect: RectF) bool {
    const self = @fieldParentPtr(BlockWidget, "widget", w);
    trace(@src(), .{&self});

    if (self.border_style) |border_style|
        self.widget.rect = new_rect.grow(-border_style.width / 2);

    return true;
}

fn deinitFn(w: *Widget) void {
    const self = @fieldParentPtr(BlockWidget, "widget", w);
    trace(@src(), .{&self});

    self.allocator.destroy(self);
}

pub fn init(allocator: *Allocator, rect: RectF, bg_color: Color, parent: anytype) !*BlockWidget {
    trace(@src(), .{ rect, bg_color });

    var block_widget = try allocator.create(BlockWidget);
    block_widget.* = BlockWidget{
        .bg_color = bg_color,
        .allocator = allocator,
        .widget = .{ .abs_rect = rect, .paintFn = paintFn, .deinitFn = deinitFn },
    };

    if (@typeInfo(@TypeOf(parent)) != .Null) {
        parent.widget.addChild(&block_widget.widget);
    }

    return block_widget;
}

pub fn deinit(self: *BlockWidget) void {
    trace(@src(), .{});

    self.widget.deinit();
}

pub fn paint(self: *BlockWidget, d2d: *Direct2D) !void {
    trace(@src(), .{});

    return self.widget.paint(d2d);
}

pub fn resize(self: *BlockWidget, new_rect: RectF) void {
    trace(@src(), .{new_rect});

    self.widget.resize(new_rect);
}
