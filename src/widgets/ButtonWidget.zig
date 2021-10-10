style: ButtonStyle,
enabled: bool = true,
onClickFn: ?fn () void = null,

hovered: bool = false,
block: *BlockWidget,
label: *LabelWidget,

allocator: *Allocator,
widget: Widget,

const ButtonWidget = @This();

const log = std.log.scoped(.ButtonWidget);

const std = @import("std");
const direct2d = @import("../direct2d.zig");
const Widget = @import("Widget.zig");
const BlockWidget = @import("BlockWidget.zig");
const LabelWidget = @import("LabelWidget.zig");

const Allocator = std.mem.Allocator;
const Direct2D = direct2d.Direct2D;
const Color = direct2d.Color;
const TextFormat = direct2d.TextFormat;
const PointF = direct2d.PointF;
const RectF = direct2d.RectF;

const ButtonStyle = struct {
    active_bg_color: Color = Color.fromU32(0x040F18FF),
    hover_bg_color: Color = Color.fromU32(0x07131EFF),
    disabled_bg_color: Color = Color.fromU32(0x081422FF),

    active_text_color: Color = Color.fromU32(0xBFBDB6FF),
    disabled_text_color: Color = Color.fromU32(0x22262BFF),

    active_border: BlockWidget.BorderStyle = .{ .color = Color.fromU32(0x646B73FF), .width = 1 },
    disabled_border: BlockWidget.BorderStyle = .{ .color = Color.fromU32(0x444B53FF), .width = 1 },
};

fn paintFn(w: *Widget, _: *Direct2D) !void {
    const self = @fieldParentPtr(ButtonWidget, "widget", w);

    // TODO: probably cache this or something?
    if (self.enabled) {
        if (self.widget.mouse_inside) {
            self.block.bg_color = self.style.hover_bg_color;
            self.block.border_style = self.style.active_border;
            self.label.text_color = self.style.active_text_color;
        } else {
            self.block.bg_color = self.style.active_bg_color;
            self.block.border_style = self.style.active_border;
            self.label.text_color = self.style.active_text_color;
        }
    } else {
        self.block.bg_color = self.style.disabled_bg_color;
        self.block.border_style = self.style.disabled_border;
        self.label.text_color = self.style.disabled_text_color;
    }
}

fn onMouseEventFn(w: *Widget, event: Widget.MouseEvent, _: PointF) bool {
    const self = @fieldParentPtr(ButtonWidget, "widget", w);

    return switch (event) {
        .Up => blk: {
            if (self.enabled and self.onClickFn != null) {
                self.onClickFn.?();
                break :blk true;
            } else {
                break :blk false;
            }
        },
        .Enter, .Leave => true,
        else => false,
    };
}

fn deinitFn(w: *Widget) void {
    const self = @fieldParentPtr(ButtonWidget, "widget", w);

    self.allocator.destroy(self);
}

pub fn init(
    allocator: *Allocator,
    rect: RectF,
    text_format: TextFormat,
    text: []const u8,
    style: ButtonStyle,
    parent: anytype,
) !*ButtonWidget {
    var button_widget = try allocator.create(ButtonWidget);
    button_widget.* = ButtonWidget{
        .block = try BlockWidget.init(allocator, rect, style.active_bg_color, null),
        .label = try LabelWidget.init(allocator, rect, text, text_format, style.active_text_color, .{}, null),
        .style = style,
        .allocator = allocator,
        .widget = .{ .abs_rect = rect, .onMouseEventFn = onMouseEventFn, .paintFn = paintFn, .deinitFn = deinitFn },
    };

    button_widget.block.border_style = style.active_border;
    button_widget.widget.addChild(&button_widget.block.widget);
    button_widget.block.widget.addChild(&button_widget.label.widget);

    if (@typeInfo(@TypeOf(parent)) != .Null) {
        parent.widget.addChild(&button_widget.widget);
    }

    return button_widget;
}

pub fn deinit(self: *ButtonWidget) void {
    self.widget.deinit();
}

pub fn paint(self: *ButtonWidget, d2d: *Direct2D) !void {
    return self.widget.paint(d2d);
}

pub fn resize(self: *ButtonWidget, new_rect: RectF) void {
    self.widget.resize(new_rect);
}
