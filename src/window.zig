pub const UNICODE = true;
const std = @import("std");
const log = std.log.scoped(.window);

const WINAPI = std.os.windows.WINAPI;
const win32 = @import("win32");
usingnamespace win32.zig;
usingnamespace win32.foundation;
usingnamespace win32.system.system_services;
usingnamespace win32.system.library_loader;
usingnamespace win32.system.diagnostics.debug;
usingnamespace win32.ui.hi_dpi;
usingnamespace win32.ui.windows_and_messaging;
usingnamespace win32.graphics.gdi;

// todo: move to common - reorganise types
pub const Rect = struct {
    top: i32 = 0,
    bottom: i32 = 0,
    left: i32 = 0,
    right: i32 = 0,

    pub fn fromRECT(rect: RECT) Rect {
        return .{
            .top = rect.top,
            .bottom = rect.bottom,
            .left = rect.left,
            .right = rect.right,
        };
    }

    pub fn toRECT(self: Rect) RECT {
        return .{
            .top = self.top,
            .bottom = self.bottom,
            .left = self.left,
            .right = self.right,
        };
    }

    pub fn toSizeU(self: Rect) win32.graphics.direct2d.D2D_SIZE_U {
        return .{
            .width = @intCast(u32, self.right - self.left),
            .height = @intCast(u32, self.bottom - self.top),
        };
    }
};

pub const Point = struct {
    x: i32 = 0,
    y: i32 = 0,
};

pub const Caret = struct {
    window: *SimpleWindow,
    width: f32,
    height: f32,

    pub fn setPos(self: Caret, x: f32, y: f32) !void {
        if (FAILED(SetCaretPos(self.window.toPhysicalPixels(x), self.window.toPhysicalPixels(y))))
            return error.SetCaretPosFailed;
    }

    pub fn show(self: Caret) !void {
        if (FAILED(ShowCaret(self.window.handle)))
            return error.ShowCaretFailed;
    }

    pub fn hide(self: Caret) !void {
        if (FAILED(HideCaret(self.window.handle)))
            return error.HideCaretFailed;
    }

    pub fn destroy(self: Caret) !void {
        // does this work??
        self.window.caret = null;

        if (FAILED(DestroyCaret()))
            return error.DestroyCaretFailed;
    }
};

pub fn processMessage() bool {
    var msg: MSG = undefined;
    if (GetMessage(&msg, null, 0, 0) == 0)
        return false;

    _ = TranslateMessage(&msg);
    _ = DispatchMessage(&msg);

    return true;
}

pub inline fn hiword(value: anytype) u16 {
    return @truncate(u16, @bitCast(usize, value) >> 16);
}

pub inline fn loword(value: anytype) u16 {
    return @truncate(u16, @bitCast(usize, value));
}

pub const SimpleWindow = struct {
    title: []const u8,
    class_name: []const u8,
    handle: HWND,
    caret: ?Caret = null,
    paint_struct: PAINTSTRUCT = undefined,
    dpi_scaling_factor: f32 = 1,

    pub fn init(comptime title: []const u8, comptime class_name: []const u8, window_proc: WNDPROC) !SimpleWindow {
        // configure default process-level dpi awareness
        // requires windows10.0.15063
        // ERROR_ACCESS_DENIED means the process DPI was already set
        if (FAILED(SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2)))
            if (GetLastError() == ERROR_ACCESS_DENIED)
                log.info("DPI awareness already set", .{})
            else
                return error.SetDpiAwarenessFailed;

        const wnd_class = WNDCLASS{
            .style = WNDCLASS_STYLES.initFlags(.{ .DBLCLKS = 1 }),
            .lpfnWndProc = window_proc,
            .cbClsExtra = 0,
            .cbWndExtra = 0,
            .hInstance = GetModuleHandle(null),
            .hIcon = null,
            .hCursor = null,
            .hbrBackground = null,
            .lpszMenuName = null,
            .lpszClassName = L(class_name),
        };

        if (RegisterClass(&wnd_class) == 0) {
            log.crit("failed to register class with name '{s}'", .{class_name});
            return error.RegisterClassFailed;
        }

        const wnd_handle = CreateWindowEx(
            WINDOW_EX_STYLE.initFlags(.{}),
            wnd_class.lpszClassName,
            L(title),
            WS_OVERLAPPEDWINDOW,
            CW_USEDEFAULT,
            CW_USEDEFAULT,
            CW_USEDEFAULT,
            CW_USEDEFAULT,
            null,
            null,
            wnd_class.hInstance,
            null,
        );

        if (wnd_handle) |wnd| {
            return SimpleWindow{
                .title = title,
                .class_name = class_name,
                .handle = wnd,
            };
        } else return error.CreateWindowFailed;
    }

    pub fn show(self: *SimpleWindow) void {
        _ = ShowWindow(self.handle, SHOW_WINDOW_CMD.initFlags(.{ .SHOWNORMAL = 1 }));
        self.updateDpi();
    }

    pub fn getCaret(self: *SimpleWindow, width: f32, height: f32) !Caret {
        if (self.caret) |caret| {
            if (caret.width == width and caret.height == height) {
                log.info("caret already exists", .{});
                return caret;
            }
            log.info("caret already exists, but wrong size", .{});
            caret.destroy() catch {};
        }

        if (FAILED(CreateCaret(self.handle, null, self.toPhysicalPixels(width), self.toPhysicalPixels(height))))
            return error.Failed;

        const _caret = Caret{ .window = self, .width = width, .height = height };
        self.caret = _caret;
        return _caret;
    }

    pub fn updateDpi(self: *SimpleWindow) void {
        self.dpi_scaling_factor = @intToFloat(f32, GetDpiForWindow(self.handle)) / 96;
    }

    pub inline fn toPhysicalPixels(self: *SimpleWindow, value: f32) i32 {
        self.dpi_scaling_factor = 2;
        return @floatToInt(i32, value * self.dpi_scaling_factor);
    }

    pub inline fn toDIPixels(self: SimpleWindow, value: i32) f32 {
        return @intToFloat(f32, value) / self.dpi_scaling_factor;
    }

    pub fn clientRect(self: SimpleWindow) !Rect {
        var rect: RECT = undefined;
        if (GetClientRect(self.handle, &rect) == 0)
            return error.Failed;

        return Rect.fromRECT(rect);
    }

    pub fn screenToClient(self: SimpleWindow, point: Point) !Point {
        var win_point = POINT{ .x = point.x, .y = point.y };
        if (ScreenToClient(self.handle, &win_point) == 0)
            return error.Failed;

        return Point{ .x = win_point.x, .y = win_point.y };
    }

    pub fn beginPaint(self: *SimpleWindow) void {
        _ = BeginPaint(self.handle, &self.paint_struct);
    }

    pub fn endPaint(self: *SimpleWindow) void {
        // return value is always non-zero
        _ = EndPaint(self.handle, &self.paint_struct);
    }

    pub fn invalidate(self: *SimpleWindow, erase: enum { NO_ERASE, ERASE }) !void {
        if (FAILED(InvalidateRect(self.handle, null, if (erase == .NO_ERASE) 0 else 1)))
            return error.Failed;
    }

    pub fn deinit(self: *SimpleWindow) void {
        log.warn("deinit unimplemented...", .{});
        _ = self;
        // TODO:
        // SafeRelease(something);
        if (self.caret) |_caret| _caret.destroy() catch {};
    }
};
