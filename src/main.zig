// enable trace logging
pub const TRACE = false;
const trace = @import("trace.zig").trace;

const std = @import("std");
const assert = std.debug.assert;

const win32 = @import("win32");
const win32_window = @import("window.zig");
const direct2d = @import("direct2d.zig");
const BlockWidget = @import("widgets/BlockWidget.zig");
const LabelWidget = @import("widgets/LabelWidget.zig");
const ListBoxWidget = @import("widgets/ListBoxWidget.zig");
const SplitWidget = @import("widgets/SplitWidget.zig");

const WINAPI = std.os.windows.WINAPI;
const L = win32.zig.L;
const HWND = win32.foundation.HWND;
const wam = win32.ui.windows_and_messaging;
const Color = direct2d.Color;

const log = std.log.scoped(.default);
pub const log_level: std.log.Level = .info;

var window: win32_window.SimpleWindow = undefined;
var d2d: direct2d.Direct2D = undefined;

const border_color = Color.fromU32(0x262C38FF);
const primary_bg_color = Color.fromU32(0x0D1017FF);
const primary_text_color = Color.fromU32(0xBFBDB6FF);
const secondary_bg_color = Color.fromU32(0x0B0E14FF);
const secondary_text_color = Color.fromU32(0x646B73FF);

var text_format: direct2d.TextFormat = undefined;

const DirPane = struct {
    block: *BlockWidget,
    list: *ListBoxWidget,
    // statusBar: *LabelWidget,
};

var app = struct {
    main_widget: *SplitWidget = undefined,
    left: DirPane = undefined,
    right: DirPane = undefined,
    active_pane: enum { Left, Right } = .Left,
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
    _,
};

fn windowProc(hwnd: HWND, msg: u32, w_param: usize, l_param: isize) callconv(WINAPI) i32 {
    trace(@src(), .{@intToEnum(WmMsg, msg)});

    switch (@intToEnum(WmMsg, msg)) {
        .PAINT => {
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
    window.invalidate(.ERASE) catch {};
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

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        try list_box.addItem(entry.name);
    }
}

fn createWidgets() !*SplitWidget {
    trace(@src(), .{});

    app.main_widget = try SplitWidget.init(&gpa.allocator, .{}, .Horizontal, null);

    app.left = .{
        .block = try BlockWidget.init(&gpa.allocator, .{}, primary_bg_color, null),
        .list = try ListBoxWidget.init(&gpa.allocator, .{}, text_format, primary_text_color, null, app.left.block),
    };
    app.left.block.border_style = .{ .width = 1, .color = border_color };
    try app.main_widget.addWidget(app.left.block);

    app.right = .{
        .block = try BlockWidget.init(&gpa.allocator, .{}, secondary_bg_color, null),
        .list = try ListBoxWidget.init(&gpa.allocator, .{}, text_format, secondary_text_color, null, app.right.block),
    };
    try app.main_widget.addWidget(app.right.block);

    try populateDirEntries("C:\\", app.left.list);
    try populateDirEntries("D:\\dev\\source", app.right.list);

    return app.main_widget;
}

fn paint() !void {
    trace(@src(), .{});

    try d2d.beginDraw();
    defer d2d.endDraw() catch {};

    d2d.clear(Color.DarkGray);
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

    // show the window
    window.show();

    app.main_widget = try createWidgets();
    log.debug("created widget", .{});

    // handle windows messages
    while (win32_window.processMessage()) {}

    // cleanup all widgets
    app.main_widget.deinit();
}
