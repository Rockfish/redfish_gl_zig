const std = @import("std");
const core = @import("core");
const zopengl = @import("zopengl");
const gl = zopengl.bindings;
const zstbi = @import("zstbi");
const Shader = core.Shader;

pub const FrameBuffer = struct {
    framebuffer_id: u32,
    texture_id: u32,
    depth_buffer_id: u32,
    width: i32,
    height: i32,
};

pub const ScreenshotManager = struct {
    capture: ScreenshotCapture,
    allocator: std.mem.Allocator,
    temp_dir: []const u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .capture = ScreenshotCapture.init(allocator),
            .allocator = allocator,
            .temp_dir = "temp",
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

        // Ensure temp directory exists
        std.fs.cwd().makeDir(self.temp_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        // Generate filenames with timestamp
        var uniform_filename_buf: [256]u8 = undefined;
        const uniform_filename = try std.fmt.bufPrint(&uniform_filename_buf, "{s}/{s}_pbr_uniforms.json", .{ self.temp_dir, timestamp_str });

        // Save uniform data (debug mode should already be enabled by caller)
        shader.saveDebugUniforms(uniform_filename, &timestamp_str) catch |err| {
            std.debug.print("Failed to save uniforms: {any}\n", .{err});
        };

        // Generate screenshot filename
        var screenshot_filename_buf: [256]u8 = undefined;
        const screenshot_filename = try std.fmt.bufPrint(&screenshot_filename_buf, "{s}/{s}_screenshot.png", .{ self.temp_dir, timestamp_str });

        // Save screenshot (framebuffer should already be configured by caller)
        self.capture.saveScreenshot(screenshot_filename) catch |err| {
            std.debug.print("Failed to save screenshot: {any}\n", .{err});
        };

        std.debug.print("Screenshot and uniform dump complete!\n", .{});
    }

    pub fn takeScreenshotWithRender(self: *Self, shader: *Shader, render_fn: fn () void) !void {
        // Generate timestamp for synchronized filenames
        const timestamp_str = core.utils.generateTimestamp();

        std.debug.print("Taking screenshot with draw callback, timestamp: {s}\n", .{timestamp_str});

        // Ensure temp directory exists
        std.fs.cwd().makeDir(self.temp_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        // Enable shader debug to capture uniforms
        const was_debug_enabled = shader.debug_enabled;
        if (!was_debug_enabled) {
            shader.enableDebug();
        }

        // Clear previous debug data
        shader.clearDebugUniforms();

        // Bind framebuffer for capture
        self.capture.bindForCapture();

        // Draw to framebuffer (this will capture uniforms)
        render_fn();

        // Restore default framebuffer
        self.capture.restoreDefault();

        // Generate filenames with timestamp
        var uniform_filename_buf: [256]u8 = undefined;
        const uniform_filename = try std.fmt.bufPrint(&uniform_filename_buf, "{s}/{s}_pbr_uniforms.json", .{ self.temp_dir, timestamp_str });

        // Save uniform data
        shader.saveDebugUniforms(uniform_filename, &timestamp_str) catch |err| {
            std.debug.print("Failed to save uniforms: {any}\n", .{err});
        };

        // Generate screenshot filename
        var screenshot_filename_buf: [256]u8 = undefined;
        const screenshot_filename = try std.fmt.bufPrint(&screenshot_filename_buf, "{s}/{s}_screenshot.png", .{ self.temp_dir, timestamp_str });

        // Save screenshot
        self.capture.saveScreenshot(screenshot_filename) catch |err| {
            std.debug.print("Failed to save screenshot: {any}\n", .{err});
        };

        // Restore debug state
        if (!was_debug_enabled) {
            shader.disableDebug();
        }

        std.debug.print("Screenshot and uniform dump complete!\n", .{});
    }
};

pub const ScreenshotCapture = struct {
    framebuffer: ?FrameBuffer,
    allocator: std.mem.Allocator,
    temp_dir: []const u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .framebuffer = null,
            .allocator = allocator,
            .temp_dir = "temp",
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.framebuffer) |fb| {
            gl.deleteFramebuffers(1, &fb.framebuffer_id);
            gl.deleteTextures(1, &fb.texture_id);
            gl.deleteRenderbuffers(1, &fb.depth_buffer_id);
        }
    }

    pub fn ensureFramebuffer(self: *Self, width: i32, height: i32) !void {
        // Recreate framebuffer if size changed or doesn't exist
        if (self.framebuffer == null or
            self.framebuffer.?.width != width or
            self.framebuffer.?.height != height)
        {

            // Clean up existing framebuffer
            if (self.framebuffer) |fb| {
                gl.deleteFramebuffers(1, &fb.framebuffer_id);
                gl.deleteTextures(1, &fb.texture_id);
                gl.deleteRenderbuffers(1, &fb.depth_buffer_id);
            }

            self.framebuffer = try createScreenshotFramebuffer(width, height);
        }
    }

    pub fn saveScreenshot(self: *Self, filename: []const u8) !void {
        const fb = self.framebuffer orelse return error.FramebufferNotInitialized;

        // Capture frame data
        const rgb_data = try self.captureFrame();
        defer self.allocator.free(rgb_data);

        // Create null-terminated filename for zstbi
        const filename_z = try self.allocator.dupeZ(u8, filename);
        defer self.allocator.free(filename_z);

        zstbi.init(self.allocator);
        defer zstbi.deinit();

        zstbi.setFlipVerticallyOnWrite(true);

        // Create Image struct for zstbi
        const image = zstbi.Image{
            .data = rgb_data,
            .width = @intCast(fb.width),
            .height = @intCast(fb.height),
            .num_components = 3, // RGB
            .bytes_per_component = 1,
            .bytes_per_row = @intCast(fb.width * 3),
            .is_hdr = false,
        };

        // Save as PNG using zstbi high-level API
        try image.writeToFile(filename_z, .png);

        std.debug.print("Screenshot saved: {s}\n", .{filename});
    }

    pub fn bindForCapture(self: *Self) void {
        if (self.framebuffer) |fb| {
            gl.bindFramebuffer(gl.FRAMEBUFFER, fb.framebuffer_id);
            gl.viewport(0, 0, fb.width, fb.height);
        }
    }

    pub fn restoreDefault(self: *Self) void {
        _ = self;
        gl.bindFramebuffer(gl.FRAMEBUFFER, 0);
    }

    pub fn captureFrame(self: *Self) ![]u8 {
        const fb = self.framebuffer orelse return error.FramebufferNotInitialized;

        // Bind framebuffer for reading
        gl.bindFramebuffer(gl.READ_FRAMEBUFFER, fb.framebuffer_id);

        // Allocate buffer for RGB data
        const pixel_count: usize = @intCast(fb.width * fb.height);
        const rgb_data = try self.allocator.alloc(u8, pixel_count * 3);

        // Read pixels (RGB format)
        gl.readPixels(0, 0, fb.width, fb.height, gl.RGB, gl.UNSIGNED_BYTE, rgb_data.ptr);

        // Restore default framebuffer
        gl.bindFramebuffer(gl.READ_FRAMEBUFFER, 0);

        return rgb_data;
    }
};

fn createScreenshotFramebuffer(width: i32, height: i32) !FrameBuffer {
    var framebuffer_id: u32 = 0;
    var texture_id: u32 = 0;
    var depth_buffer_id: u32 = 0;

    // Generate framebuffer
    gl.genFramebuffers(1, &framebuffer_id);
    gl.bindFramebuffer(gl.FRAMEBUFFER, framebuffer_id);

    // Create color texture
    gl.genTextures(1, &texture_id);
    gl.bindTexture(gl.TEXTURE_2D, texture_id);
    gl.texImage2D(
        gl.TEXTURE_2D,
        0,
        gl.RGB8,
        width,
        height,
        0,
        gl.RGB,
        gl.UNSIGNED_BYTE,
        null,
    );
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);

    // Attach color texture to framebuffer
    gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, texture_id, 0);

    // Create depth renderbuffer
    gl.genRenderbuffers(1, &depth_buffer_id);
    gl.bindRenderbuffer(gl.RENDERBUFFER, depth_buffer_id);
    gl.renderbufferStorage(gl.RENDERBUFFER, gl.DEPTH_COMPONENT24, width, height);
    gl.framebufferRenderbuffer(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.RENDERBUFFER, depth_buffer_id);

    // Check framebuffer completeness
    if (gl.checkFramebufferStatus(gl.FRAMEBUFFER) != gl.FRAMEBUFFER_COMPLETE) {
        return error.FramebufferIncomplete;
    }

    // Restore default framebuffer
    gl.bindFramebuffer(gl.FRAMEBUFFER, 0);

    return FrameBuffer{
        .framebuffer_id = framebuffer_id,
        .texture_id = texture_id,
        .depth_buffer_id = depth_buffer_id,
        .width = width,
        .height = height,
    };
}
