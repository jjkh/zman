text_format: TextFormat,
text_color: Color,
bg_color: Color = Color.Transparent,
padding: PointF = .{ .x = 8, .y = 4 },

onHoverFn: ?fn (?ListItem) void = null,
onSelectFn: ?fn (?ListItem) void = null,
onActivateFn: ?fn (ListItem) void = null,

items: ArrayList(ListItem),
allocator: *Allocator,
widget: Widget,

selected_item: ?ListItem = null,
hovered_item: ?ListItem = null,

const ListBoxWidget = @This();

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

pub const ListItem = struct {
    label: *LabelWidget,
    block: *BlockWidget,
};

// TODO: derive this from textlayout
const LINE_SPACING = 20;
// TODO: not like this
const SELECTED_COLOR = Color.fromU32(0x181C26FF);
const HOVERED_COLOR = Color.fromU32(0x1B202AFF);
const HOVERED_BORDER_COLOR = Color.fromU32(0x646B73FF);
const BORDER_WIDTH = 1;

fn resizeFn(w: *Widget, new_rect: RectF) bool {
    const self = @fieldParentPtr(ListBoxWidget, "widget", w);

    var block_rect = new_rect.size().toRect();
    block_rect.bottom = LINE_SPACING + self.padding.y * 2;

    const label_rect = block_rect.add(.{
        .top = self.padding.y,
        .bottom = -self.padding.y,
        .left = self.padding.x,
        .right = -self.padding.x,
    });

    for (self.items.items) |*list_item| {
        list_item.block.widget.resize(block_rect);
        list_item.label.widget.resize(label_rect);

        block_rect = block_rect.addPoint(.{ .y = block_rect.height() });
    }

    w.abs_rect.bottom = new_rect.top + block_rect.top;

    return false;
}

fn paintFn(w: *Widget, _: *Direct2D) !void {
    const self = @fieldParentPtr(ListBoxWidget, "widget", w);

    for (self.items.items) |list_item| {
        list_item.block.bg_color = self.bg_color;
        list_item.block.border_style = .{ .color = self.bg_color, .width = BORDER_WIDTH };
    }

    if (self.selected_item) |selected_item| {
        selected_item.block.bg_color = SELECTED_COLOR;
        selected_item.block.border_style = .{ .color = SELECTED_COLOR, .width = BORDER_WIDTH };
    }

    if (self.hovered_item) |hovered_item| {
        hovered_item.block.bg_color = HOVERED_COLOR;
        hovered_item.block.border_style = .{ .color = HOVERED_BORDER_COLOR, .width = BORDER_WIDTH };
    }
}

fn itemAtPoint(self: ListBoxWidget, point: PointF) ?ListItem {
    for (self.items.items) |list_item|
        if (list_item.block.widget.rect().contains(point))
            return list_item;

    return null;
}

fn itemsEql(first: ?ListItem, second: ?ListItem) bool {
    if (first == null and second == null) return true;
    if (first != null and second != null and first.?.block == second.?.block) return true;

    return false;
}

// alternative approach could have a mouseevent handler which we manually
// apply to the child blocks, but feels kinda gross
fn onMouseEventFn(w: *Widget, event: Widget.MouseEvent, point: PointF) bool {
    const self = @fieldParentPtr(ListBoxWidget, "widget", w);

    const maybe_item_at_point = self.itemAtPoint(point);
    switch (event) {
        .DblClick => if (maybe_item_at_point) |list_item| {
            if (self.onActivateFn != null) self.onActivateFn.?(list_item);
        },
        .Down => {
            if (!itemsEql(maybe_item_at_point, self.selected_item)) {
                self.selected_item = maybe_item_at_point;
                if (self.onSelectFn != null) self.onSelectFn.?(self.selected_item);
            }
            if (maybe_item_at_point) |item| {
                // this is just horrendous
                const block = @fieldParentPtr(BlockWidget, "widget", self.widget.parent.?);
                block.scrollIntoView(item.block.widget.abs_rect.addPoint(self.widget.offset).grow(self.padding.y / 2));
            }
        },
        .Move => if (!itemsEql(maybe_item_at_point, self.hovered_item)) {
            self.hovered_item = maybe_item_at_point;
            if (self.onHoverFn != null) self.onHoverFn.?(self.hovered_item);
        },
        .Leave => self.hovered_item = null,
        else => return false,
    }
    return true;
}

fn deinitFn(w: *Widget) void {
    const self = @fieldParentPtr(ListBoxWidget, "widget", w);

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
    self.widget.deinit();
}

fn makeItem(self: *ListBoxWidget, text: []const u8) !ListItem {
    const block = try BlockWidget.init(self.allocator, .{}, self.bg_color, self);
    block.border_style = .{ .color = self.bg_color, .width = BORDER_WIDTH };
    block.radius = 4;

    var list_item = .{
        .block = block,
        .label = try LabelWidget.init(self.allocator, .{}, text, self.text_format, self.text_color, .{}, block),
    };

    return list_item;
}

pub fn appendItem(self: *ListBoxWidget, text: []const u8) !void {
    try self.items.append(try self.makeItem(text));

    self.resize(self.widget.abs_rect);
}

// NOTE: This is O(N)
pub fn insertItem(self: *ListBoxWidget, pos: usize, text: []const u8) !void {
    try self.items.insert(pos, try self.makeItem(text));

    self.resize(self.widget.abs_rect);
}

pub fn clearItems(self: *ListBoxWidget) void {
    for (self.items.items) |list_item| {
        list_item.block.deinit();
    }
    self.widget.first_child = null;

    self.hovered_item = null;
    self.selected_item = null;
    self.items.clearRetainingCapacity();
}

pub fn setTextColor(self: *ListBoxWidget, new_color: Color) void {
    if (new_color.toU32() == self.text_color.toU32()) return;

    for (self.items.items) |*list_item|
        list_item.label.text_color = new_color;

    self.text_color = new_color;
}

pub fn paint(self: *ListBoxWidget, d2d: *Direct2D) !void {
    return self.widget.paint(d2d);
}

pub fn resize(self: *ListBoxWidget, new_rect: RectF) void {
    self.widget.resize(new_rect);
}
