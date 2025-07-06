const std = @import("std");
const core = @import("core");
const screenshot = @import("screenshot.zig");
const Shader = core.Shader;

const ScreenshotCapture = screenshot.ScreenshotCapture;

pub const ScreenshotManager = struct {
    capture: ScreenshotCapture,
    allocator: std.mem.Allocator,
    temp_dir: []const u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .capture = ScreenshotCapture.init(allocator),
            .allocator = allocator,
            .temp_dir = "/tmp/redfish_screenshots",
        };
    }

    pub fn deinit(self: *Self) void {
        self.capture.deinit();
    }

    pub fn ensureFramebuffer(self: *Self, width: i32, height: i32) !void {
        try self.capture.ensureFramebuffer(width, height);
    }

    pub fn takeScreenshot(self: *Self, shader: *Shader) !void {
        // Generate timestamp for synchronized filenames
        const timestamp_str = core.utils.generateTimestamp();

        std.debug.print("Taking screenshot with timestamp: {s}\n", .{timestamp_str});

        // Generate filenames with timestamp
        var uniform_filename_buf: [256]u8 = undefined;
        const uniform_filename = try std.fmt.bufPrint(&uniform_filename_buf, "{s}/{s}_pbr_uniforms.json", .{ self.temp_dir, timestamp_str });

        // Save uniform data (debug mode should already be enabled by caller)
        shader.saveDebugUniforms(uniform_filename) catch |err| {
            std.debug.print("Failed to save uniforms: {any}\n", .{err});
        };

        // Save screenshot (framebuffer should already be configured by caller)
        self.capture.saveScreenshot(&timestamp_str) catch |err| {
            std.debug.print("Failed to save screenshot: {any}\n", .{err});
        };

        std.debug.print("Screenshot and uniform dump complete!\n", .{});
    }

    pub fn takeScreenshotWithRender(self: *Self, shader: *Shader, render_fn: fn () void) !void {
        // Generate timestamp for synchronized filenames
        const timestamp = core.utils.generateTimestamp();
        const timestamp_str = std.mem.sliceTo(&timestamp, 0);

        std.debug.print("Taking screenshot with render callback, timestamp: {s}\n", .{timestamp_str});

        // Enable shader debug to capture uniforms
        const was_debug_enabled = shader.debug_enabled;
        if (!was_debug_enabled) {
            shader.enableDebug();
        }

        // Clear previous debug data
        shader.clearDebugUniforms();

        // Bind framebuffer for capture
        self.capture.bindForCapture();

        // Render to framebuffer (this will capture uniforms)
        render_fn();

        // Restore default framebuffer
        self.capture.restoreDefault();

        // Generate filenames with timestamp
        var uniform_filename_buf: [256]u8 = undefined;
        const uniform_filename = try std.fmt.bufPrint(&uniform_filename_buf, "{s}/{s}_pbr_uniforms.json", .{ self.temp_dir, timestamp_str });

        // Save uniform data
        shader.saveDebugUniforms(uniform_filename) catch |err| {
            std.debug.print("Failed to save uniforms: {any}\n", .{err});
        };

        // Save screenshot
        self.capture.saveScreenshot(timestamp_str) catch |err| {
            std.debug.print("Failed to save screenshot: {any}\n", .{err});
        };

        // Restore debug state
        if (!was_debug_enabled) {
            shader.disableDebug();
        }

        std.debug.print("Screenshot and uniform dump complete!\n", .{});
    }
};
