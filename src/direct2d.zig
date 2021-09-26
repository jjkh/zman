const std = @import("std");
const log = std.log.scoped(.direct2d);

const win32 = @import("win32");
usingnamespace win32.zig;
usingnamespace win32.foundation;
usingnamespace win32.system.com;
usingnamespace win32.graphics.direct2d;
usingnamespace win32.graphics.direct_write;

const trace = @import("trace.zig").trace;
const SimpleWindow = @import("window.zig").SimpleWindow;

fn safeRelease(ppT: anytype) void {
    trace(@src(), .{});

    log.debug("releasing {s}", .{@typeName(@TypeOf(ppT.*.*))});
    _ = ppT.*.IUnknown_Release();
}

pub const PointF = struct {
    x: f32 = 0,
    y: f32 = 0,

    pub fn neg(self: PointF) PointF {
        return .{ .x = -self.x, .y = -self.y };
    }

    pub fn add(self: PointF, other: PointF) PointF {
        return .{ .x = self.x + other.x, .y = self.y + other.y };
    }

    pub fn sub(self: PointF, other: PointF) PointF {
        return .{ .x = self.x - other.x, .y = self.y - other.y };
    }

    pub fn scale(self: PointF, scalar: f32) PointF {
        return .{ .x = self.x * scalar, .y = self.y * scalar };
    }

    pub fn fromD2DSizeF(size: D2D_SIZE_F) PointF {
        return .{ .x = size.width, .y = size.height };
    }

    pub fn toD2DSizeF(self: PointF) D2D_SIZE_F {
        return .{ .width = self.x, .height = self.y };
    }

    pub fn toRect(self: PointF) RectF {
        return .{
            .top = 0,
            .bottom = self.y,
            .left = 0,
            .right = self.x,
        };
    }

    pub fn midpoint(self: PointF, other: PointF) PointF {
        return .{
            .x = (self.x + other.x) / 2,
            .y = (self.y + other.y) / 2,
        };
    }

    pub fn format(self: PointF, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        try std.fmt.format(writer, "{{{d}, {d}}}", .{ self.x, self.y });
    }
};

pub const Point = struct {
    x: i32 = 0,
    y: i32 = 0,
};

pub const RectF = struct {
    top: f32 = 0,
    bottom: f32 = 0,
    left: f32 = 0,
    right: f32 = 0,

    pub fn fromD2DRectF(rect: D2D_RECT_F) RectF {
        return .{
            .top = rect.top,
            .bottom = rect.bottom,
            .left = rect.left,
            .right = rect.right,
        };
    }

    pub fn toD2DRectF(self: RectF) D2D_RECT_F {
        return .{
            .top = self.top,
            .bottom = self.bottom,
            .left = self.left,
            .right = self.right,
        };
    }

    pub fn addPoint(self: RectF, other: PointF) RectF {
        return .{
            .top = self.top + other.y,
            .bottom = self.bottom + other.y,
            .left = self.left + other.x,
            .right = self.right + other.x,
        };
    }

    pub fn add(self: RectF, other: RectF) RectF {
        return .{
            .top = self.top + other.top,
            .bottom = self.bottom + other.bottom,
            .left = self.left + other.left,
            .right = self.right + other.right,
        };
    }

    // elementwise multiply
    pub fn mul(self: RectF, other: RectF) RectF {
        return .{
            .top = self.top * other.top,
            .bottom = self.bottom * other.bottom,
            .left = self.left * other.left,
            .right = self.right * other.right,
        };
    }

    // scalar multiply
    pub fn scale(self: RectF, scalar: f32) RectF {
        return .{
            .top = self.top * scalar,
            .bottom = self.bottom * scalar,
            .left = self.left * scalar,
            .right = self.right * scalar,
        };
    }

    pub fn grow(self: RectF, scalar: f32) RectF {
        return .{
            .top = self.top - scalar,
            .bottom = self.bottom + scalar,
            .left = self.left - scalar,
            .right = self.right + scalar,
        };
    }

    pub fn offset(self: RectF, scalar: f32) RectF {
        return .{
            .top = self.top + scalar,
            .bottom = self.bottom + scalar,
            .left = self.left + scalar,
            .right = self.right + scalar,
        };
    }

    pub fn topLeft(self: RectF) PointF {
        return .{
            .x = self.left,
            .y = self.top,
        };
    }

    pub fn bottomRight(self: RectF) PointF {
        return .{
            .x = self.right,
            .y = self.bottom,
        };
    }

    pub fn centerPoint(self: RectF) PointF {
        return .{
            .x = (self.right - self.left) / 2,
            .y = (self.bottom - self.top) / 2,
        };
    }

    pub fn width(self: RectF) f32 {
        return self.right - self.left;
    }

    pub fn height(self: RectF) f32 {
        return self.bottom - self.top;
    }

    pub fn size(self: RectF) PointF {
        return .{
            .x = self.width(),
            .y = self.height(),
        };
    }

    pub fn centerWithin(self: RectF, outer: RectF) RectF {
        return self.addPoint(outer.centerPoint().sub(self.centerPoint()));
    }

    pub fn contains(self: RectF, point: PointF) bool {
        return point.x >= self.left and point.x <= self.right and point.y >= self.top and point.y <= self.bottom;
    }

    pub fn format(self: RectF, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        try std.fmt.format(writer, "{{{d}, {d}, {d}, {d}}}", .{ self.top, self.bottom, self.left, self.right });
    }
};

// extension of D2D1_COLOR_F with helper functions
pub const Color = struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32 = 1,

    pub const Black = Color{ .r = 0, .g = 0, .b = 0 };
    pub const White = Color{ .r = 1, .g = 1, .b = 1 };
    pub const LightGray = Color{ .r = 0.75, .g = 0.75, .b = 0.75 };
    pub const Gray = Color{ .r = 0.5, .g = 0.5, .b = 0.5 };
    pub const DarkGray = Color{ .r = 0.25, .g = 0.25, .b = 0.25 };

    pub const Red = Color{ .r = 1, .g = 0, .b = 0 };
    pub const Green = Color{ .r = 0, .g = 1, .b = 0 };
    pub const Blue = Color{ .r = 0, .g = 0, .b = 1 };
    pub const Yellow = Color{ .r = 1, .g = 1, .b = 0 };
    pub const Magenta = Color{ .r = 1, .g = 0, .b = 1 };
    pub const Cyan = Color{ .r = 0, .g = 1, .b = 1 };

    pub const Transparent = Color{ .r = 0, .g = 0, .b = 0, .a = 1 };

    pub fn fromU8(rgba: struct { r: u8, g: u8, b: u8, a: u8 = 255 }) Color {
        return .{
            .r = @intToFloat(f32, rgba.r) / 255,
            .g = @intToFloat(f32, rgba.g) / 255,
            .b = @intToFloat(f32, rgba.b) / 255,
            .a = @intToFloat(f32, rgba.a) / 255,
        };
    }

    pub fn fromU24(rgba: struct { rgb: u24, a: f32 = 1 }) Color {
        return .{
            .r = @intToFloat(f32, (rgba.rgb >> 16) & 0xFF) / 255,
            .g = @intToFloat(f32, (rgba.rgb >> 8) & 0xFF) / 255,
            .b = @intToFloat(f32, rgba.rgb & 0xFF) / 255,
            .a = rgba.a,
        };
    }

    pub fn fromU32(rgba: u32) Color {
        return .{
            .r = @intToFloat(f32, (rgba >> 24) & 0xFF) / 255,
            .g = @intToFloat(f32, (rgba >> 16) & 0xFF) / 255,
            .b = @intToFloat(f32, (rgba >> 8) & 0xFF) / 255,
            .a = @intToFloat(f32, rgba & 0xFF) / 255,
        };
    }

    pub fn toU24(self: Color) u24 {
        return @floatToInt(u24, self.r * 255) << 16 | @floatToInt(u24, self.g * 255) << 8 | @floatToInt(u24, self.b * 255);
    }

    pub fn toU32(self: Color) u32 {
        return @floatToInt(u32, self.r * 255) << 24 | @floatToInt(u32, self.g * 255) << 16 | @floatToInt(u32, self.b * 255) << 8 | @floatToInt(u32, self.a * 255);
    }

    pub fn toStr(self: Color) [10:0]u8 {
        var buf: [10:0]u8 = undefined;
        _ = std.fmt.bufPrint(&buf, "0x{X:0>8}", .{self.toU32()}) catch unreachable;
        return buf;
    }

    pub fn toD2DColorF(self: Color) D2D1_COLOR_F {
        return .{
            .r = self.r,
            .g = self.g,
            .b = self.b,
            .a = self.a,
        };
    }
};

test "Color" {
    const testing = std.testing;

    const color_from_u8 = Color.fromU8(.{ .r = 0, .g = 51, .b = 102, .a = 255 });
    try testing.expectEqual(color_from_u8.r, 0.0);
    try testing.expectEqual(color_from_u8.g, 0.2);
    try testing.expectEqual(color_from_u8.b, 0.4);
    try testing.expectEqual(color_from_u8.a, 1);

    const color_from_u24 = Color.fromU24(.{ .rgb = 0x003366 });
    try testing.expectEqual(color_from_u8, color_from_u24);

    const color_from_u32 = Color.fromU32(0x003366FF);
    try testing.expectEqual(color_from_u8, color_from_u32);

    const u24_from_color = color_from_u8.toU24();
    try testing.expectEqual(@as(u24, 0x003366), u24_from_color);

    const u32_from_color = color_from_u8.toU32();
    try testing.expectEqual(@as(u32, 0x003366FF), u32_from_color);

    const str_from_color = color_from_u8.toStr();
    try testing.expectEqualStrings("0x003366FF", &str_from_color);
}

/// created with Direct2D.createSolidBrush()
pub const SolidColorBrush = struct {
    color: Color,
    brush_ptr: ?*ID2D1SolidColorBrush = null,

    pub fn deinit(self: *SolidColorBrush) void {
        trace(@src(), .{});

        if (self.brush_ptr) |*brush_ptr| safeRelease(brush_ptr);
        self.brush_ptr = null;
    }

    pub fn brush(self: *SolidColorBrush, d2d: *Direct2D, reuse_existing: enum { REUSE, RECREATE }) !*ID2D1SolidColorBrush {
        trace(@src(), .{self.color});

        if (self.brush_ptr) |brush_ptr| {
            if (reuse_existing == .REUSE)
                return brush_ptr;

            self.deinit();
        }

        if (d2d.render_target) |render_target| {
            const result = render_target.ID2D1RenderTarget_CreateSolidColorBrush(
                &self.color.toD2DColorF(),
                null,
                @ptrCast(*?*ID2D1SolidColorBrush, &self.brush_ptr),
            );
            if (FAILED(result) or self.brush_ptr == null) {
                self.brush_ptr = null;
                return error.CreateBrushFailed;
            }

            return self.brush_ptr.?;
        }

        return error.NoRenderTarget;
    }
};

pub const CaretInfo = struct {
    position: PointF,
    height: f32,
};

/// created with Direct2D.createTextFormat()
pub const TextFormat = struct {
    text_format: *IDWriteTextFormat,

    pub fn deinit(self: *TextFormat) void {
        trace(@src(), .{});

        safeRelease(&self.text_format);
    }

    pub fn setAlignment(self: *TextFormat, options: struct {
        horizontal: DWRITE_TEXT_ALIGNMENT = .LEADING,
        vertical: DWRITE_PARAGRAPH_ALIGNMENT = .NEAR,
    }) !void {
        if (FAILED(self.text_format.IDWriteTextFormat_SetTextAlignment(options.horizontal)))
            return error.SetTextAlignmentFailed;

        if (FAILED(self.text_format.IDWriteTextFormat_SetParagraphAlignment(options.vertical)))
            return error.SetParagraphAlignmentFailed;
    }

    pub fn setWordWrapping(self: *TextFormat, wrap_style: DWRITE_WORD_WRAPPING) !void {
        if (FAILED(self.text_format.IDWriteTextFormat_SetWordWrapping(wrap_style)))
            return error.Failed;
    }

    pub fn setOverflow(self: *TextFormat, overflow: enum { Shown, Hidden }) !void {
        var trim_style = DWRITE_TRIMMING{
            .granularity = if (overflow == .Shown) .NONE else .CHARACTER,
            .delimiter = 0,
            .delimiterCount = 0,
        };

        if (FAILED(self.text_format.IDWriteTextFormat_SetTrimming(&trim_style, null)))
            return error.Failed;
    }
};

pub const TextLayout = struct {
    text_layout: *IDWriteTextLayout,
    text_format: TextFormat,
    text: [:0]const u16,
    width: f32,
    height: f32,

    pub fn deinit(self: *TextLayout) void {
        trace(@src(), .{});
        safeRelease(&self.text_layout);
    }

    pub fn caretInfo(self: *TextLayout, text_index: usize, options: struct { hit_pos: enum { Leading, Trailing } = .Trailing }) !CaretInfo {
        var caret_info: CaretInfo = undefined;
        var hit_test_metrics: DWRITE_HIT_TEST_METRICS = undefined;

        if (FAILED(self.text_layout.IDWriteTextLayout_HitTestTextPosition(
            @intCast(u32, text_index),
            if (options.hit_pos == .Trailing) TRUE else FALSE,
            &caret_info.position.x,
            &caret_info.position.y,
            &hit_test_metrics,
        ))) {
            return error.HitTestTextPositionFailed;
        }

        caret_info.height = hit_test_metrics.height;

        // should be init method?
        return caret_info;
    }
};

pub const Direct2D = struct {
    d2d1_factory: *ID2D1Factory,
    dwrite_factory: *IDWriteFactory,
    render_target: ?*ID2D1HwndRenderTarget,
    window: SimpleWindow,

    /// creates "device-independent" the d2d1 and dwrite factories
    /// also initalises the "device-dependent" render target 
    pub fn init(window: SimpleWindow) !Direct2D {
        trace(@src(), .{});

        var self = Direct2D{
            .d2d1_factory = undefined,
            .dwrite_factory = undefined,
            .render_target = null,
            .window = window,
        };
        {
            const result = D2D1CreateFactory(
                D2D1_FACTORY_TYPE_SINGLE_THREADED,
                IID_ID2D1Factory,
                null,
                @ptrCast(**c_void, &self.d2d1_factory),
            );
            if (FAILED(result))
                return error.CreateD2D1FactoryFailed;
        }
        {
            const result = DWriteCreateFactory(
                DWRITE_FACTORY_TYPE_SHARED,
                IID_IDWriteFactory,
                @ptrCast(*?*IUnknown, &self.dwrite_factory),
            );
            if (FAILED(result))
                return error.CreateDWriteFactoryFailed;
        }
        try self.initRenderTarget();

        return self;
    }

    /// TODO: how can I manage this better?
    /// render target - device-dependent
    pub fn initRenderTarget(self: *Direct2D) !void {
        trace(@src(), .{});

        if (self.render_target != null)
            return;

        log.debug("creating render target", .{});
        const result = self.d2d1_factory.ID2D1Factory_CreateHwndRenderTarget(
            &std.mem.zeroes(D2D1_RENDER_TARGET_PROPERTIES), // default
            &D2D1_HWND_RENDER_TARGET_PROPERTIES{
                .hwnd = self.window.handle,
                .pixelSize = (try self.window.clientRect()).toSizeU(),
                .presentOptions = D2D1_PRESENT_OPTIONS_NONE,
            },
            @ptrCast(*?*ID2D1HwndRenderTarget, &self.render_target),
        );

        if (FAILED(result))
            return error.CreateRenderTargetFailed;
    }

    // TODO: how can i also clear brushes, etc.?
    pub fn deinitRenderTarget(self: *Direct2D) void {
        trace(@src(), .{});

        log.warn("Only releasing render target...", .{});

        if (self.render_target) |render_target|
            safeRelease(&render_target);

        self.render_target = null;
    }

    /// device-independent
    pub fn createTextFormat(self: *Direct2D, comptime font: []const u8, size: f32) !TextFormat {
        trace(@src(), .{});

        var text_format: ?*IDWriteTextFormat = undefined;
        const result = self.dwrite_factory.IDWriteFactory_CreateTextFormat(
            L(font),
            null,
            DWRITE_FONT_WEIGHT_NORMAL,
            DWRITE_FONT_STYLE_NORMAL,
            DWRITE_FONT_STRETCH_NORMAL,
            size,
            // L(""), // doesn't work with empty string? seems wrong...
            &[0:0]u16{}, // however this works??
            &text_format,
        );

        if (FAILED(result)) {
            log.crit("failed to create text format with font '{s}' and size {}", .{ font, size });
            return error.CreateTextFormatFailed;
        }
        var format = TextFormat{ .text_format = text_format.? };
        try format.setOverflow(.Hidden);
        return format;
    }

    pub fn createTextLayout(self: *Direct2D, text: [:0]const u16, text_format: TextFormat, width: f32, height: f32) !TextLayout {
        var text_layout: *IDWriteTextLayout = undefined;

        const result = self.dwrite_factory.IDWriteFactory_CreateTextLayout(
            text.ptr,
            @intCast(u32, text.len),
            text_format.text_format,
            width,
            height,
            &text_layout,
        );

        if (FAILED(result)) {
            log.crit("failed to create text layout", .{});
            return error.CreateTextLayoutFailed;
        }

        return TextLayout{
            .text_layout = text_layout,
            .text_format = text_format,
            .text = text,
            .width = width,
            .height = height,
        };
    }

    pub fn deinit(self: *Direct2D) void {
        trace(@src(), .{});

        self.deinitRenderTarget();
        safeRelease(&self.d2d1_factory);
        safeRelease(&self.dwrite_factory);
    }

    pub fn beginDraw(self: *Direct2D) !void {
        trace(@src(), .{});

        // initialise the render target in case it was destroyed last paint
        try self.initRenderTarget();

        // TODO: should this be here?
        self.window.beginPaint();

        if (self.render_target) |render_target|
            render_target.ID2D1RenderTarget_BeginDraw()
        else
            return error.NoRenderTarget;
    }

    pub fn endDraw(self: *Direct2D) !void {
        trace(@src(), .{});

        defer self.window.endPaint();
        // if there is a failure to draw, destroy the render target and recreate next paint
        errdefer self.deinitRenderTarget();

        if (self.render_target) |render_target| {
            const result = render_target.ID2D1RenderTarget_EndDraw(null, null);
            if (FAILED(result)) {
                log.err("endDraw failed with return code {}", .{result});
                return error.EndDrawFailed;
            } else if (result == D2DERR_RECREATE_TARGET) {
                log.warn("recreate target required", .{});
                return error.D2DRecreateTarget;
            }
        } else {
            log.err("endDraw called but render target not initialised", .{});
            return error.NoRenderTarget;
        }
    }

    pub fn clear(self: *Direct2D, color: Color) void {
        trace(@src(), .{color});

        if (self.render_target) |render_target|
            render_target.ID2D1RenderTarget_Clear(&color.toD2DColorF())
        else
            log.err("clear called but render target not initialised", .{});
    }

    pub fn pushAxisAlignedClip(self: *Direct2D, rect: RectF) void {
        trace(@src(), .{rect});

        if (self.render_target) |render_target| {
            render_target.ID2D1RenderTarget_PushAxisAlignedClip(&rect.toD2DRectF(), .PER_PRIMITIVE);
        } else log.err("pushAxisAlignedClip called but render target not initialised", .{});
    }

    pub fn popAxisAlignedClip(self: *Direct2D) void {
        trace(@src(), .{});

        if (self.render_target) |render_target| {
            render_target.ID2D1RenderTarget_PopAxisAlignedClip();
        } else log.err("popAxisAlignedClip called but render target not initialised", .{});
    }

    pub fn fillRect(self: *Direct2D, rect: RectF, brush: *SolidColorBrush) !void {
        trace(@src(), .{rect});

        if (self.render_target) |render_target| {
            render_target.ID2D1RenderTarget_FillRectangle(&rect.toD2DRectF(), @ptrCast(*ID2D1Brush, try brush.brush(self, .REUSE)));
        } else log.err("fillRect called but render target not initialised", .{});
    }

    pub fn fillRoundedRect(self: *Direct2D, rect: RectF, brush: *SolidColorBrush, radius: f32) !void {
        trace(@src(), .{rect});

        if (self.render_target) |render_target| {
            render_target.ID2D1RenderTarget_FillRoundedRectangle(&D2D1_ROUNDED_RECT{ .rect = rect.toD2DRectF(), .radiusX = radius, .radiusY = radius }, @ptrCast(*ID2D1Brush, try brush.brush(self, .REUSE)));
        } else log.err("fillRoundedRect called but render target not initialised", .{});
    }

    pub fn outlineRect(self: *Direct2D, rect: RectF, width: f32, brush: *SolidColorBrush) !void {
        trace(@src(), .{rect});

        if (self.render_target) |render_target|
            render_target.ID2D1RenderTarget_DrawRectangle(&rect.grow(-0.5).toD2DRectF(), @ptrCast(*ID2D1Brush, try brush.brush(self, .REUSE)), width, null)
        else
            log.err("outlineRect called but render target not initialised", .{});
    }

    pub fn outlineRoundedRect(self: *Direct2D, rect: RectF, width: f32, brush: *SolidColorBrush, radius: f32) !void {
        trace(@src(), .{rect});

        if (self.render_target) |render_target|
            render_target.ID2D1RenderTarget_DrawRoundedRectangle(&D2D1_ROUNDED_RECT{ .rect = rect.grow(-0.5).toD2DRectF(), .radiusX = radius, .radiusY = radius }, @ptrCast(*ID2D1Brush, try brush.brush(self, .REUSE)), width, null)
        else
            log.err("outlineRoundedRect called but render target not initialised", .{});
    }

    pub fn getSize(self: *Direct2D) !PointF {
        trace(@src(), .{});

        if (self.render_target) |render_target|
            return PointF.fromD2DSizeF(render_target.ID2D1RenderTarget_GetSize())
        else
            return error.NoRenderTarget;
    }

    pub fn resize(self: *Direct2D) !void {
        trace(@src(), .{});

        if (self.render_target) |render_target|
            _ = render_target.ID2D1HwndRenderTarget_Resize(&(try self.window.clientRect()).toSizeU())
        else
            return error.NoRenderTarget;

        try self.window.invalidate(.NO_ERASE);
    }

    pub fn drawTextW(
        self: *Direct2D,
        text: [:0]const u16,
        text_format: TextFormat,
        rect: RectF,
        brush: *SolidColorBrush,
    ) !void {
        trace(@src(), .{text});

        if (self.render_target) |render_target|
            _ = render_target.ID2D1RenderTarget_DrawText(
                text,
                @intCast(u32, text.len),
                text_format.text_format,
                &rect.toD2DRectF(),
                @ptrCast(*ID2D1Brush, try brush.brush(self, .REUSE)),
                D2D1_DRAW_TEXT_OPTIONS_ENABLE_COLOR_FONT,
                DWRITE_MEASURING_MODE_NATURAL,
            )
        else
            return error.NoRenderTarget;
    }

    /// allocator required to convert utf-8 to utf-16
    /// max buffer size required is text.len*2 + 1 (?)
    pub fn drawTextAlloc(
        self: *Direct2D,
        allocator: *std.mem.Allocator,
        text: []const u8,
        text_format: TextFormat,
        rect: RectF,
        brush: *SolidColorBrush,
    ) !void {
        trace(@src(), .{text});
        const w_text = try std.unicode.utf8ToUtf16LeWithNull(allocator, text);
        defer allocator.free(w_text);
        try self.drawTextW(w_text, text_format, rect, brush);
    }

    pub fn drawTextBuf(
        self: *Direct2D,
        buf: []u16,
        text: []const u8,
        text_format: TextFormat,
        rect: RectF,
        brush: *SolidColorBrush,
    ) !void {
        const len = try std.unicode.utf8ToUtf16Le(buf, text);
        buf[len] = 0;

        try self.drawTextW(buf[0..len :0], text_format, rect, brush);
    }

    pub fn drawTextLayout(
        self: *Direct2D,
        text_layout: TextLayout,
        origin: PointF,
        default_fill_brush: *SolidColorBrush,
    ) !void {
        trace(@src(), .{});

        if (self.render_target) |render_target| {
            _ = render_target.ID2D1RenderTarget_DrawTextLayout(
                .{ .x = origin.x, .y = origin.y },
                text_layout.text_layout,
                @ptrCast(*ID2D1Brush, try default_fill_brush.brush(self, .REUSE)),
                D2D1_DRAW_TEXT_OPTIONS_ENABLE_COLOR_FONT,
            );
        } else {
            return error.NoRenderTarget;
        }
    }
};
