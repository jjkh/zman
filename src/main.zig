// enable trace logging
pub const TRACE = false;
const SHOW_FPS = false;

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

const log = std.log.scoped(.default);
pub const log_level: std.log.Level = .info;
const trace = @import("trace.zig").trace;

var window: win32_window.SimpleWindow = undefined;
var d2d: direct2d.Direct2D = undefined;
var tracking_mouse_event = false;

const border_color = Color.fromU32(0x262C38FF);
const primary_bg_color = Color.fromU32(0x0D1017FF);
const primary_text_color = Color.fromU32(0xBFBDB6FF);
const secondary_bg_color = Color.fromU32(0x0B0E14FF);
const secondary_text_color = Color.fromU32(0x646B73FF);

var text_format: direct2d.TextFormat = undefined;
var centered_text_format: direct2d.TextFormat = undefined;

const DirPane = struct {
    split: *SplitWidget,

    // top
    block: *BlockWidget,
    list: *ListBoxWidget,

    // bottom
    button: *ButtonWidget,
    // statusBar: *LabelWidget,
};

var app = struct {
    main_widget: *SplitWidget = undefined,
    left: DirPane = undefined,
    right: DirPane = undefined,
    active_pane: enum { Left, Right } = .Left,
    fps_meter: *LabelWidget = undefined,
}{};

var first_surrogate_half: u16 = 0;

var gpa: std.heap.GeneralPurposeAllocator(.{}) = undefined;

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
    L_BUTTON_DOWN = wam.WM_LBUTTONDOWN,
    MOUSE_MOVE = wam.WM_MOUSEMOVE,
    MOUSE_LEAVE = win32.ui.controls.WM_MOUSELEAVE,
    SET_CURSOR = wam.WM_SETCURSOR,
    _,
};

fn windowProc(hwnd: HWND, msg: u32, w_param: usize, l_param: isize) callconv(WINAPI) i32 {
    trace(@src(), .{@intToEnum(WmMsg, msg)});

    const msg_type = @intToEnum(WmMsg, msg);
    switch (msg_type) {
        .PAINT => {
            var timer = std.time.Timer.start() catch unreachable;
            defer {
                if (SHOW_FPS) {
                    const frame_time_us = @intToFloat(f32, timer.read() / 1000);
                    var buf: [128]u8 = undefined;
                    const fps_str = std.fmt.bufPrint(&buf, "{d:.0} FPS ({d:.2}ms)", .{ 100_0000 / frame_time_us, frame_time_us / 1000 }) catch unreachable;
                    app.fps_meter.setText(fps_str) catch unreachable;
                }
            }

            paint() catch |err| log.err("paint: {}", .{err});
            return -1;
        },
        .SIZE => d2d.resize() catch |err| log.err("d2d.resize: {}", .{err}),
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
        .L_BUTTON_DOWN, .MOUSE_MOVE => {
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
            const x_pixel_coord = @intCast(i16, win32_window.loword(l_param));
            const y_pixel_coord = @intCast(i16, win32_window.hiword(l_param));

            const di_point = direct2d.PointF{
                .x = window.toDIPixels(x_pixel_coord),
                .y = window.toDIPixels(y_pixel_coord),
            };

            const invalidate_window = switch (msg_type) {
                .L_BUTTON_DOWN => app.main_widget.onMouseEvent(.Down, di_point),
                .MOUSE_MOVE => app.main_widget.onMouseMove(di_point),
                else => false,
            };
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

fn toggleActivePane() void {
    if (app.active_pane == .Left) {
        app.active_pane = .Right;
        app.left.block.bg_color = secondary_bg_color;
        app.left.block.border_style = null;
        app.left.list.setTextColor(secondary_text_color);

        app.right.block.bg_color = primary_bg_color;
        app.right.block.border_style = .{ .width = 1, .color = border_color };
        app.right.list.setTextColor(primary_text_color);
    } else {
        app.active_pane = .Left;
        app.left.block.bg_color = primary_bg_color;
        app.left.block.border_style = .{ .width = 1, .color = border_color };
        app.left.list.setTextColor(primary_text_color);

        app.right.block.bg_color = secondary_bg_color;
        app.right.block.border_style = null;
        app.right.list.setTextColor(secondary_text_color);
    }
    window.invalidate(.NO_ERASE) catch {};
}

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
            toggleActivePane();
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
//     trace(@src(), .{});
//     if (input_text_layout == null)
//         return;

//     const caret_info = try input_text_layout.?.caretInfo(input_text_layout.?.text.len, .{});

//     const caret = try window.getCaret(2.0, caret_info.height);
//     try caret.setPos(60.0 + caret_info.position.x, 60.0 + caret_info.position.y);
//     try caret.show();
// }

fn populateDirEntries(path: []const u8, list_box: *ListBoxWidget) !void {
    const dir = try std.fs.cwd().openDir(
        path,
        .{ .iterate = true },
    );

    try list_box.appendItem(" ↩  ..");

    var folder_pos: usize = 1;
    var name_buf: [8096]u8 = undefined;

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind == .Directory) {
            const folder_name = try std.fmt.bufPrint(&name_buf, "📁 {s}", .{entry.name});
            try list_box.insertItem(folder_pos, folder_name);
            folder_pos += 1;
        } else {
            try list_box.appendItem(entry.name);
        }
    }
}

fn scrollActivePane() void {
    if (app.active_pane == .Left)
        app.left.list.widget.offset = app.left.list.widget.offset.add(.{ .y = 10 })
    else
        app.right.list.widget.offset = app.right.list.widget.offset.add(.{ .y = 10 });

    window.invalidate(.NO_ERASE) catch {};
}

fn createWidgets() !*SplitWidget {
    trace(@src(), .{});

    app.main_widget = try SplitWidget.init(&gpa.allocator, .{}, .Horizontal, null);

    if (SHOW_FPS) {
        // TODO: probably shouldn't be adding children directly to a split widget - could easily get confusing
        // can we prevent this at compile/run time?

        // make this first because children list is backwards and I want this on top
        // TODO: fix this with Z-index or at least a doubly-linked list
        app.fps_meter = try LabelWidget.init(&gpa.allocator, .{ .top = 0, .left = 0, .right = 200, .bottom = 200 }, "", text_format, Color.Magenta, .{}, app.main_widget);
    }

    app.left = .{
        .split = undefined,
        .block = try BlockWidget.init(&gpa.allocator, .{}, primary_bg_color, null),
        .list = try ListBoxWidget.init(&gpa.allocator, .{}, text_format, primary_text_color, null, app.left.block),
        .button = undefined,
    };
    app.left.block.border_style = .{ .width = 1, .color = border_color };
    try app.main_widget.addWidget(app.left.block);

    app.right = .{
        .split = try SplitWidget.init(&gpa.allocator, .{}, .Vertical, null),
        .block = try BlockWidget.init(&gpa.allocator, .{}, secondary_bg_color, null),
        .list = try ListBoxWidget.init(&gpa.allocator, .{}, text_format, secondary_text_color, null, app.right.block),
        .button = try ButtonWidget.init(&gpa.allocator, .{}, centered_text_format, "Scroll active pane", .{}, null),
    };

    app.right.button.onClickFn = scrollActivePane;
    try app.right.split.addWidget(app.right.block);
    try app.right.split.addWidget(app.right.button);
    try app.main_widget.addWidget(app.right.split);

    try populateDirEntries("C:\\", app.left.list);
    try populateDirEntries("D:\\dev\\source", app.right.list);

    return app.main_widget;
}

fn paint() !void {
    trace(@src(), .{});

    try d2d.beginDraw();
    defer d2d.endDraw() catch {};

    d2d.clear(Color.DarkGray);
    // TODO: only recalculate sizes if size has changed?
    try recalculateSizes();

    try app.main_widget.paint(&d2d);
    log.debug("painted widget", .{});
}

fn recalculateSizes() !void {
    trace(@src(), .{});

    const new_size = try d2d.getSize();
    app.main_widget.resize(new_size.toRect());
}

pub fn main() !void {
    trace(@src(), .{});
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
    text_format = try d2d.createTextFormat("SegoeUI", 13.5);
    defer text_format.deinit();

    // create a default font (but centered)
    centered_text_format = try d2d.createTextFormat("SegoeUI", 14);
    defer centered_text_format.deinit();
    try centered_text_format.setAlignment(.{ .horizontal = .CENTER, .vertical = .CENTER });

    // show the window
    window.show();

    app.main_widget = try createWidgets();
    log.debug("created widget", .{});

    // handle windows messages
    while (win32_window.processMessage()) {}

    // cleanup all widgets
    app.main_widget.deinit();
}
