text_format: TextFormat,
text_color: Color,
bg_color: Color = Color.fromU32(0x0D1017FF),
padding: f32 = 4,

items: ArrayList(ListItem),
allocator: *Allocator,
widget: Widget,

selected_item: ?ListItem = null,
hovered_item: ?ListItem = null,

const ListBoxWidget = @This();

const trace = @import("../trace.zig").trace;
const log = std.log.scoped(.ListBoxWidget);

const std = @import("std");
const direct2d = @import("../direct2d.zig");
const Widget = @import("Widget.zig");
const BlockWidget = @import("BlockWidget.zig");
const LabelWidget = @import("LabelWidget.zig");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Direct2D = direct2d.Direct2D;
const Color = direct2d.Color;
const TextFormat = direct2d.TextFormat;
const PointF = direct2d.PointF;
const RectF = direct2d.RectF;

const ListItem = struct {
    label: *LabelWidget,
    block: *BlockWidget,
};

// TODO: derive this from textlayout
const LINE_SPACING = 20;
// TODO: not like this
const SELECTED_COLOR = Color.fromU32(0x181C26FF);
const HOVERED_COLOR = Color.fromU32(0x1B202AFF);
const HOVERED_BORDER_STYLE = BlockWidget.BorderStyle{ .color = Color.fromU32(0x646B73FF), .width = 1 };

fn resizeFn(w: *Widget, new_rect: RectF) bool {
    const self = @fieldParentPtr(ListBoxWidget, "widget", w);
    trace(@src(), .{ &self, new_rect, self.items.items.len });

    var block_rect = new_rect.size().toRect().grow(-1); // grow is workaround for outer border growing inwards >:(
    block_rect.bottom = LINE_SPACING + self.padding * 2 + 1;

    const label_rect = block_rect.grow(-self.padding);

    for (self.items.items) |*list_item| {
        list_item.block.widget.resize(block_rect);
        list_item.label.widget.resize(label_rect);

        block_rect = block_rect.addPoint(.{ .y = block_rect.height() });
    }

    return false;
}

fn paintFn(w: *Widget, _: *Direct2D) !void {
    const self = @fieldParentPtr(ListBoxWidget, "widget", w);
    trace(@src(), .{&self});

    for (self.items.items) |*list_item| {
        list_item.block.bg_color = self.bg_color;
        list_item.block.border_style = null;
    }

    if (self.selected_item) |*selected_item|
        selected_item.block.bg_color = SELECTED_COLOR;

    if (self.hovered_item) |*hovered_item| {
        hovered_item.block.bg_color = HOVERED_COLOR;
        hovered_item.block.border_style = HOVERED_BORDER_STYLE;
    }
}

fn itemAtPoint(self: ListBoxWidget, point: PointF) ?ListItem {
    for (self.items.items) |list_item|
        if (list_item.block.widget.rect().contains(point))
            return list_item;

    return null;
}

// alternative approach could have a mouseevent handler which we manually
// apply to the child blocks, but feels kinda gross
fn onMouseEventFn(w: *Widget, event: Widget.MouseEvent, point: PointF) bool {
    const self = @fieldParentPtr(ListBoxWidget, "widget", w);
    trace(@src(), .{&self});

    log.info("{}", .{point});
    var maybe_item_at_point = self.itemAtPoint(point);
    switch (event) {
        .Down => self.selected_item = maybe_item_at_point,
        .Move => {
            if (maybe_item_at_point == null and self.hovered_item == null) return false;
            if (maybe_item_at_point != null and self.hovered_item != null)
                if (maybe_item_at_point.?.block == self.hovered_item.?.block) return false;

            self.hovered_item = maybe_item_at_point;
        },
        .Leave => self.hovered_item = null,
        else => return false,
    }
    return true;
}

fn deinitFn(w: *Widget) void {
    const self = @fieldParentPtr(ListBoxWidget, "widget", w);
    trace(@src(), .{&self});

    self.items.deinit();
    self.allocator.destroy(self);
}

pub fn init(
    allocator: *Allocator,
    rect: RectF,
    text_format: TextFormat,
    text_color: Color,
    items: ?[]const []const u8,
    parent: anytype,
) !*ListBoxWidget {
    trace(@src(), .{ rect, parent });

    var list_box_widget = try allocator.create(ListBoxWidget);
    list_box_widget.* = ListBoxWidget{
        .text_format = text_format,
        .text_color = text_color,
        .items = if (items) |i| try ArrayList(ListItem).initCapacity(allocator, i.len) else ArrayList(ListItem).init(allocator),
        .allocator = allocator,
        .widget = .{ .abs_rect = rect, .paintFn = paintFn, .onMouseEventFn = onMouseEventFn, .resizeFn = resizeFn, .deinitFn = deinitFn },
    };

    if (@typeInfo(@TypeOf(parent)) != .Null)
        parent.widget.addChild(&list_box_widget.widget);

    if (items) |_items| for (_items) |item|
        try list_box_widget.appendItem(item);

    return list_box_widget;
}

pub fn deinit(self: *ListBoxWidget) void {
    trace(@src(), .{});

    self.widget.deinit();
}

fn makeItem(self: *ListBoxWidget, text: []const u8) !ListItem {
    var list_item = .{
        .block = try BlockWidget.init(self.allocator, .{}, self.bg_color, self),
        .label = try LabelWidget.init(self.allocator, .{}, text, self.text_format, self.text_color, .{}, null),
    };
    list_item.block.widget.addChild(&list_item.label.widget);
    list_item.block.radius = 5;

    return list_item;
}

pub fn appendItem(self: *ListBoxWidget, text: []const u8) !void {
    try self.items.append(try self.makeItem(text));

    self.resize(self.widget.rect());
}

// NOTE: This is O(N)
pub fn insertItem(self: *ListBoxWidget, pos: usize, text: []const u8) !void {
    try self.items.insert(pos, try self.makeItem(text));

    self.resize(self.widget.rect());
}

pub fn setTextColor(self: *ListBoxWidget, new_color: Color) void {
    if (new_color.toU32() == self.text_color.toU32()) return;

    for (self.items.items) |*list_item|
        list_item.label.text_color = new_color;

    self.text_color = new_color;
}

pub fn paint(self: *ListBoxWidget, d2d: *Direct2D) !void {
    trace(@src(), .{});

    return self.widget.paint(d2d);
}

pub fn resize(self: *ListBoxWidget, new_rect: RectF) void {
    trace(@src(), .{new_rect});

    self.widget.resize(new_rect);
}
