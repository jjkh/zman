const SHOW_FPS = true;

const std = @import("std");
const assert = std.debug.assert;

const win32 = @import("win32");
const win32_window = @import("window.zig");
const direct2d = @import("direct2d.zig");
const BlockWidget = @import("widgets/BlockWidget.zig");
const LabelWidget = @import("widgets/LabelWidget.zig");
const ListBoxWidget = @import("widgets/ListBoxWidget.zig");
const SplitWidget = @import("widgets/SplitWidget.zig");
const ButtonWidget = @import("widgets/ButtonWidget.zig");

const WINAPI = std.os.windows.WINAPI;
const L = win32.zig.L;
const HWND = win32.foundation.HWND;
const wam = win32.ui.windows_and_messaging;
const Color = direct2d.Color;
const Direct2D = direct2d.Direct2D;
const RectF = direct2d.RectF;

const log = std.log.scoped(.default);
pub const log_level: std.log.Level = .info;

// TODO: move to some sort of stylesheet (JSON probably?)
const border_color = Color.fromU32(0x262C38FF);
const primary_bg_color = Color.fromU32(0x10141CFF);
const primary_text_color = Color.fromU32(0xBFBDB6FF);
const secondary_bg_color = Color.fromU32(0x0D1017FF);
const secondary_text_color = Color.fromU32(0x646B73FF);

// TODO: these imports are awful. this needs to be fixed
// TODO: also, maybe these can be moved to an explicit app state struct?
var window: win32_window.SimpleWindow = undefined;
var d2d: direct2d.Direct2D = undefined;
var tracking_mouse_event = false;
var text_format: direct2d.TextFormat = undefined;
var centered_text_format: direct2d.TextFormat = undefined;

var app: App = undefined;

var fps_text_format: direct2d.TextFormat = undefined;
var fps_meter: *LabelWidget = undefined;

var first_surrogate_half: u16 = 0;

var gpa: std.heap.GeneralPurposeAllocator(.{}) = undefined;

const StatusBar = struct {
    block: *BlockWidget,
    label: *LabelWidget,

    pub fn init() !StatusBar {
        const block = try BlockWidget.init(&gpa.allocator, .{}, secondary_bg_color, null);
        // TODO: set preferred size based on line height
        // this should probably be it's own widget? unsure
        block.widget.preferred_size = .{ .y = 24 };
        const label = try LabelWidget.init(&gpa.allocator, .{}, "", text_format, secondary_text_color, .{}, block);
        label.widget.offset = .{ .x = 6, .y = 2.5 };
        return StatusBar{
            .block = block,
            .label = label,
        };
    }
};

const DirPane = struct {
    curr_path: [:0]const u8 = undefined,
    path_buf: [8096]u8 = undefined,

    split: *SplitWidget,
    location: StatusBar,
    block: *BlockWidget,
    list: *ListBoxWidget,
    status_bar: StatusBar,

    // TODO: remove these when this is done properly
    const DIR_PREFIX = "📁 ";
    const BACK_PREFIX = " ↩  ";

    pub fn init() !DirPane {
        const block = try BlockWidget.init(&gpa.allocator, .{}, primary_bg_color, null);
        block.scroll_pos = .{};
        var dir_pane = DirPane{
            .split = try SplitWidget.init(&gpa.allocator, .{}, .Vertical, null),
            .location = try StatusBar.init(),
            .block = block,
            .list = try ListBoxWidget.init(&gpa.allocator, .{}, text_format, primary_text_color, null, block),
            .status_bar = try StatusBar.init(),
        };

        dir_pane.curr_path = "";
        dir_pane.list.onSelectFn = onItemSelectFn;
        dir_pane.list.onActivateFn = onItemActivateFn;

        try dir_pane.split.addWidget(dir_pane.location.block);
        try dir_pane.split.addWidget(dir_pane.block);
        try dir_pane.split.addWidget(dir_pane.status_bar.block);

        return dir_pane;
    }

    pub fn setActive(self: DirPane, active: enum { Active, NotActive }) void {
        if (active == .Active) {
            self.block.bg_color = primary_bg_color;
            self.block.border_style = .{ .width = 1, .color = border_color };
            self.list.setTextColor(primary_text_color);
        } else {
            self.block.bg_color = secondary_bg_color;
            self.block.border_style = .{ .width = 1, .color = secondary_bg_color };
            self.list.setTextColor(secondary_text_color);
            self.list.selected_item = null;
        }
    }

    pub fn updatePath(self: *DirPane, path: []const u8) !void {
        // normalize path for display
        if (path.len > (self.path_buf.len - 2)) {
            log.err("path is too long (max len is {d}, path is {d})", .{ (self.path_buf.len - 2), path.len });
            return error.PathTooLong;
        }

        // TODO: error handling here - high priority!
        const dir = try std.fs.cwd().openDir(path, .{ .iterate = true });

        std.mem.copy(u8, &self.path_buf, path);

        var new_path_len = try std.os.windows.normalizePath(u8, self.path_buf[0..path.len]);
        if (new_path_len > 0 and self.path_buf[new_path_len - 1] != '\\') {
            self.path_buf[new_path_len] = '\\';
            new_path_len += 1;
        }
        self.path_buf[new_path_len] = 0;

        self.curr_path = self.path_buf[0..new_path_len :0];
        log.debug("{s} => {s}", .{ path, self.curr_path });

        self.list.clearItems();
        self.block.scrollTo(0);

        try self.list.appendItem(BACK_PREFIX ++ "..");

        var folder_pos: usize = 1;

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind == .Directory) {
                try self.list.insertItem(folder_pos, DIR_PREFIX);
                try self.list.items.items[folder_pos].label.text_list.appendSlice(entry.name);
                folder_pos += 1;
            } else {
                try self.list.appendItem(entry.name);
            }
        }
        try self.location.label.setText(self.curr_path);

        try self.status_bar.label.setText("");
        const status_writer = self.status_bar.label.text_list.writer();
        try status_writer.print("{d} items", .{self.list.items.items.len});
    }

    fn onItemSelectFn(maybe_list_item: ?ListBoxWidget.ListItem) void {
        if (maybe_list_item) |list_item| {
            // TODO: fix this terrible, terrible hack
            if (list_item.block.widget.parent.? == &app.left.list.widget)
                app.setActivePane(.Left)
            else
                app.setActivePane(.Right);
        }
    }

    fn onItemActivateFn(list_item: ListBoxWidget.ListItem) void {
        // this is a very bad implementation of what i want to do here
        // TODO: fix this
        log.debug("activated '{s}' @ '{s}'", .{ list_item.label.text_list.items, app.active_pane.curr_path });
        const list_text = list_item.label.text_list.items;

        var buf: [8096]u8 = undefined;
        std.mem.copy(u8, &buf, app.active_pane.curr_path);
        var remaining_slice = buf[app.active_pane.curr_path.len..];
        if (std.mem.startsWith(u8, list_text, DIR_PREFIX)) {
            const dir_name = list_text[DIR_PREFIX.len..];
            std.mem.copy(u8, remaining_slice, dir_name);
            app.active_pane.updatePath(buf[0 .. app.active_pane.curr_path.len + dir_name.len]) catch |err| {
                log.err("error updating path! {}", .{err});
            };
        } else if (std.mem.startsWith(u8, list_text, BACK_PREFIX)) {
            std.mem.copy(u8, remaining_slice, "..");
            app.active_pane.updatePath(buf[0 .. app.active_pane.curr_path.len + 2]) catch |err| {
                log.err("error updating path! {}", .{err});
            };
        } else {
            std.mem.copy(u8, &buf, list_text);
            buf[list_text.len] = 0;

            _ = win32.ui.shell.ShellExecuteA(
                null, // no window (for now)
                null, // use default verb
                &buf,
                null, // no parameters
                app.active_pane.curr_path,
                @enumToInt(win32.ui.windows_and_messaging.SW_NORMAL),
            );
        }
    }
};

const App = struct {
    main_widget: *SplitWidget,
    left: DirPane,
    right: DirPane,
    active_pane: *DirPane = undefined,

    pub fn init() !App {
        const main_widget = try SplitWidget.init(&gpa.allocator, .{}, .Horizontal, null);
        errdefer main_widget.deinit();

        var new_app = App{
            .main_widget = main_widget,
            .left = try DirPane.init(),
            .right = try DirPane.init(),
        };
        try main_widget.addWidget(new_app.left.split);
        try main_widget.addWidget(new_app.right.split);

        return new_app;
    }

    pub fn deinit(self: App) void {
        self.main_widget.deinit();
    }

    pub fn setActivePane(self: *App, pane: enum { Left, Right }) void {
        if (pane == .Left) {
            self.right.setActive(.NotActive);
            self.active_pane = &self.left;
        } else {
            self.left.setActive(.NotActive);
            self.active_pane = &self.right;
        }

        self.active_pane.setActive(.Active);
    }

    pub fn toggleActivePane(self: *App) void {
        self.setActivePane(if (self.active_pane == &self.left) .Right else .Left);
    }

    fn paint(self: App, _d2d: *Direct2D) !void {
        try self.main_widget.paint(_d2d);
    }

    fn resize(self: App, new_rect: RectF) void {
        self.main_widget.resize(new_rect);
    }
};

fn utf16Encode(c: u21) ![2]u16 {
    switch (c) {
        0xD800...0xDFFF => return error.InvalidCodepoint,
        0x0000...0xD7FF, 0xE000...0xFFFF => {
            return [2]u16{ 0, @intCast(u16, c) };
        },
        0x10000...0x10FFFF => {
            const to_encode = c - 0x10000;
            return [2]u16{
                0xD800 | @intCast(u16, to_encode >> 10),
                0xDC00 | @intCast(u16, to_encode & 0x03FF),
            };
        },
        else => return error.CodepointTooLarge,
    }
}

fn utf16DecodeAllocZ(allocator: *std.mem.Allocator, string: []u21) ![:0]u16 {
    var result = try std.ArrayList(u16).initCapacity(allocator, string.len);

    for (string) |c| {
        const utf16_c = try utf16Encode(c);
        if (utf16_c[0] != 0x0000) {
            try result.append(utf16_c[0]);
        }
        try result.append(utf16_c[1]);
    }

    return result.toOwnedSliceSentinel(0);
}

const WmMsg = enum(u32) {
    CREATE = wam.WM_CREATE,
    PAINT = wam.WM_PAINT,
    SIZE = wam.WM_SIZE,
    DESTROY = wam.WM_DESTROY,
    SET_FOCUS = wam.WM_SETFOCUS,
    KILL_FOCUS = wam.WM_KILLFOCUS,
    CHAR = wam.WM_CHAR,
    SYS_CHAR = wam.WM_SYSCHAR,
    L_BTN_DOWN = wam.WM_LBUTTONDOWN,
    L_BTN_UP = wam.WM_LBUTTONUP,
    L_BTN_DBL_CLICK = wam.WM_LBUTTONDBLCLK,
    MOUSE_MOVE = wam.WM_MOUSEMOVE,
    MOUSE_LEAVE = win32.ui.controls.WM_MOUSELEAVE,
    MOUSE_WHEEL = wam.WM_MOUSEWHEEL,
    SET_CURSOR = wam.WM_SETCURSOR,
    _,
};

fn windowProc(hwnd: HWND, msg: u32, w_param: usize, l_param: isize) callconv(WINAPI) i32 {
    const msg_type = @intToEnum(WmMsg, msg);
    switch (msg_type) {
        .PAINT => {
            paint() catch |err| log.err("paint: {}", .{err});
        },
        .SIZE => {
            d2d.resize() catch |err| log.err("d2d.resize: {}", .{err});
            resize() catch |err| log.err("resize: {}", .{err});
        },
        .DESTROY => {
            log.debug("destroying window", .{});
            wam.PostQuitMessage(0);
        },
        // .SET_FOCUS => showCursor() catch |err| {
        //     log.err("{}", .{err});
        //     return -1;
        // },
        // .KILL_FOCUS => if (window.caret) |caret| caret.destroy() catch |err| {
        //     log.err("{}", .{err});
        //     return -1;
        // },
        .CHAR => {
            const char = @intCast(u16, w_param);
            const flags = @bitCast(CharFlags, @intCast(u32, l_param));

            if (char > 0xD800 and char < 0xDC00) {
                first_surrogate_half = char;
            } else {
                if (first_surrogate_half == 0)
                    handleChar(&[1]u16{char}, flags)
                else
                    handleChar(&[2]u16{ first_surrogate_half, char }, flags);

                first_surrogate_half = 0;
            }
        },
        .MOUSE_MOVE => {
            if (!tracking_mouse_event) {
                // cursor has just entered the client rect
                const kmi = win32.ui.keyboard_and_mouse_input;
                _ = kmi.TrackMouseEvent(&kmi.TRACKMOUSEEVENT{
                    .cbSize = @sizeOf(kmi.TRACKMOUSEEVENT),
                    .dwFlags = .LEAVE,
                    .hwndTrack = window.handle,
                    .dwHoverTime = 0,
                });
                _ = wam.SetCursor(wam.LoadCursor(null, wam.IDC_ARROW));
                tracking_mouse_event = true;
            }
            const x_pixel_coord = @bitCast(i16, win32_window.loword(l_param));
            const y_pixel_coord = @bitCast(i16, win32_window.hiword(l_param));

            const di_point = direct2d.PointF{
                .x = window.toDIPixels(x_pixel_coord),
                .y = window.toDIPixels(y_pixel_coord),
            };

            if (app.main_widget.onMouseMove(di_point))
                window.invalidate(.NO_ERASE) catch {};
        },
        .L_BTN_DOWN, .L_BTN_UP, .L_BTN_DBL_CLICK => {
            const x_pixel_coord = @bitCast(i16, win32_window.loword(l_param));
            const y_pixel_coord = @bitCast(i16, win32_window.hiword(l_param));

            const di_point = direct2d.PointF{
                .x = window.toDIPixels(x_pixel_coord),
                .y = window.toDIPixels(y_pixel_coord),
            };

            const invalidate_window = move_result: {
                break :move_result switch (msg_type) {
                    .L_BTN_DOWN => app.main_widget.onMouseEvent(.Down, di_point),
                    .L_BTN_UP => app.main_widget.onMouseEvent(.Up, di_point),
                    .L_BTN_DBL_CLICK => app.main_widget.onMouseEvent(.DblClick, di_point),
                    else => false,
                };
            };
            if (invalidate_window) window.invalidate(.NO_ERASE) catch {};
        },
        .MOUSE_WHEEL => {
            const x_pixel_coord = @bitCast(i16, win32_window.loword(l_param));
            const y_pixel_coord = @bitCast(i16, win32_window.hiword(l_param));

            const client_point = window.screenToClient(.{ .x = x_pixel_coord, .y = y_pixel_coord }) catch unreachable;

            const di_point = direct2d.PointF{
                .x = window.toDIPixels(client_point.x),
                .y = window.toDIPixels(client_point.y),
            };

            const wheel_delta = @bitCast(i16, win32_window.hiword(w_param));
            const invalidate_window = app.main_widget.onScroll(di_point, wheel_delta);

            if (invalidate_window) window.invalidate(.NO_ERASE) catch {};
        },
        .MOUSE_LEAVE => {
            if (app.main_widget.onMouseMove(.{ .x = -1000, .y = -1000 }))
                window.invalidate(.NO_ERASE) catch {};

            tracking_mouse_event = false;
        },
        else => return wam.DefWindowProc(hwnd, msg, w_param, l_param),
    }

    return 0;
}

const CharFlags = packed struct {
    repeat_count: u16,
    scan_code: u8,
    reserved: u4,
    extended: bool,
    context_code: bool,
    previous_key_state: enum(u1) { Down = 0, Up = 1 },
    transition_state: enum(u1) { Released = 0, Pressed = 1 },
};

fn handleChar(char: []u16, flags: CharFlags) void {
    var it = std.unicode.Utf16LeIterator.init(char);
    _ = flags;

    const c = it.nextCodepoint() catch unreachable orelse return;

    // handle special characters (as listed in MSDN)
    switch (c) {
        // 0x08 => {
        //     // backspace
        //     input_text.dropRight(flags.repeat_count) catch {};

        //     window.invalidate(.ERASE) catch {};
        //     text_changed = true;
        // },
        '\t' => {
            app.toggleActivePane();
            window.invalidate(.NO_ERASE) catch {};
            return;
        },
        0x1B => {
            // escape
            wam.PostQuitMessage(0);
            return;
        },
        else => {
            // var i: i32 = flags.repeat_count;
            // while (i > 0) : (i -= 1) {
            //     input_text.append(c) catch {};
            // }
            // window.invalidate(.NO_ERASE) catch {};
            // text_changed = true;
        },
    }
}

// fn showCursor() !void {
//     if (input_text_layout == null)
//         return;

//     const caret_info = try input_text_layout.?.caretInfo(input_text_layout.?.text.len, .{});

//     const caret = try window.getCaret(2.0, caret_info.height);
//     try caret.setPos(60.0 + caret_info.position.x, 60.0 + caret_info.position.y);
//     try caret.show();
// }

fn paint() !void {
    const timer = if (SHOW_FPS) try std.time.Timer.start() else undefined;
    defer {
        if (SHOW_FPS) {
            const frame_time_us = @intToFloat(f32, timer.read() / 1000);
            var buf: [128]u8 = undefined;
            const fps_str = std.fmt.bufPrint(&buf, "{d:.0} FPS ({d:.2}ms)", .{ 100_0000 / frame_time_us, frame_time_us / 1000 }) catch unreachable;
            fps_meter.setText(fps_str) catch unreachable;
        }
    }

    try d2d.beginDraw();
    defer d2d.endDraw() catch |err| log.err("error '{}' on endDraw - should be recreating resources...", .{err});

    d2d.clear(Color.DarkGray);

    try app.paint(&d2d);
    if (SHOW_FPS) try fps_meter.paint(&d2d);
}

fn resize() !void {
    const new_rect = (try d2d.getSize()).toRect();

    app.resize(new_rect);
    if (SHOW_FPS) fps_meter.resize(new_rect);
}

pub fn main() !void {
    gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // TODO: use manifest for utf-8 xxxA functions instead of this
    // configure console for utf-8 output
    const old_codepage = win32.system.console.GetConsoleOutputCP();
    if (win32.system.console.SetConsoleOutputCP(win32.globalization.CP_UTF8) == 0)
        return error.SetConsoleOutputCPFailed;
    defer _ = win32.system.console.SetConsoleOutputCP(old_codepage);

    // create a window
    window = try win32_window.SimpleWindow.init("zman", "zmanClass", windowProc);
    defer window.deinit();

    // init the d2d instance
    d2d = try direct2d.Direct2D.init(window);
    defer d2d.deinit();

    // create a default font
    text_format = try d2d.createTextFormat("SegoeUI", 14);
    defer text_format.deinit();

    // create a default font (but centered)
    centered_text_format = try d2d.createTextFormat("SegoeUI", 14);
    defer centered_text_format.deinit();
    try centered_text_format.setAlignment(.{ .horizontal = .CENTER, .vertical = .CENTER });

    // create a default font (but top right)
    fps_text_format = try d2d.createTextFormat("SegoeUI", 14);
    defer fps_text_format.deinit();
    try fps_text_format.setAlignment(.{ .horizontal = .TRAILING });

    // create the application UI
    app = try App.init();
    defer app.deinit();

    if (SHOW_FPS) fps_meter = try LabelWidget.init(&gpa.allocator, .{}, "", fps_text_format, Color.Green, .{}, null);
    defer if (SHOW_FPS) fps_meter.deinit();

    // populate each pane with the directory contents
    const left_dir = "C:/";
    const right_dir = "C:/Users/Jamie/Downloads";

    app.left.updatePath(left_dir) catch |err| {
        log.crit("Couldn't open directory '{s}' in left pane ({}).", .{ left_dir, err });
        return;
    };
    app.setActivePane(.Left);

    app.right.updatePath(right_dir) catch |err| {
        log.crit("Couldn't open directory '{s}' in right pane ({}).", .{ right_dir, err });
        return;
    };

    // show the window
    window.show();

    // handle windows messages
    while (win32_window.processMessage()) {}
}
