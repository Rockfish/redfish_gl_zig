const std = @import("std");
const zopengl = @import("zopengl");
const gl = zopengl.bindings;
const zstbi = @import("zstbi");

pub const FrameBuffer = struct {
    framebuffer_id: u32,
    texture_id: u32,
    depth_buffer_id: u32,
    width: i32,
    height: i32,
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
            .temp_dir = "/tmp/redfish_screenshots",
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

    pub fn captureFrame(self: *Self) ![]u8 {
        const fb = self.framebuffer orelse return error.FramebufferNotInitialized;

        // Bind framebuffer for reading
        gl.bindFramebuffer(gl.READ_FRAMEBUFFER, fb.framebuffer_id);

        // Allocate buffer for RGB data
        const pixel_count = @as(usize, @intCast(fb.width * fb.height));
        const rgb_data = try self.allocator.alloc(u8, pixel_count * 3);

        // Read pixels (RGB format)
        gl.readPixels(0, 0, fb.width, fb.height, gl.RGB, gl.UNSIGNED_BYTE, rgb_data.ptr);

        // Restore default framebuffer
        gl.bindFramebuffer(gl.READ_FRAMEBUFFER, 0);

        return rgb_data;
    }

    pub fn saveScreenshot(self: *Self, timestamp: []const u8) !void {
        const fb = self.framebuffer orelse return error.FramebufferNotInitialized;

        // Ensure temp directory exists
        std.fs.cwd().makeDir(self.temp_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        // Generate filename
        var filename_buf: [256]u8 = undefined;
        const filename = try std.fmt.bufPrint(&filename_buf, "{s}/{s}_screenshot.png", .{ self.temp_dir, timestamp });

        // Capture frame data
        const rgb_data = try self.captureFrame();
        defer self.allocator.free(rgb_data);

        // Flip image vertically (OpenGL uses bottom-left origin)
        const flipped_data = try self.flipImageVertically(rgb_data, fb.width, fb.height);
        defer self.allocator.free(flipped_data);

        // Create null-terminated filename for zstbi
        const filename_z = try self.allocator.dupeZ(u8, filename);
        defer self.allocator.free(filename_z);

        zstbi.init(self.allocator);

        // Create Image struct for zstbi
        const image = zstbi.Image{
            .data = flipped_data,
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

    fn flipImageVertically(self: *Self, data: []u8, width: i32, height: i32) ![]u8 {
        const flipped = try self.allocator.alloc(u8, data.len);
        const row_size = @as(usize, @intCast(width * 3)); // 3 bytes per pixel (RGB)

        for (0..@intCast(height)) |y| {
            const src_row = y * row_size;
            const dst_row = (@as(usize, @intCast(height)) - 1 - y) * row_size;
            @memcpy(flipped[dst_row .. dst_row + row_size], data[src_row .. src_row + row_size]);
        }

        return flipped;
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

pub fn generateTimestamp() [23]u8 {
    const timestamp = std.time.timestamp();
    const epoch_seconds = @as(u64, @intCast(timestamp));
    const millis = @as(u64, @intCast(std.time.milliTimestamp())) % 1000;

    // Convert to local time structure
    const epoch_day = epoch_seconds / (24 * 60 * 60);
    const day_seconds = epoch_seconds % (24 * 60 * 60);

    const hour = day_seconds / 3600;
    const minute = (day_seconds % 3600) / 60;
    const second = day_seconds % 60;

    // Simple date calculation (approximate)
    const days_since_epoch = epoch_day;
    const year = 1970 + days_since_epoch / 365;
    const month = ((days_since_epoch % 365) / 30) + 1;
    const day = ((days_since_epoch % 365) % 30) + 1;

    var result: [23]u8 = undefined;
    _ = std.fmt.bufPrint(&result, "{d:0>4}-{d:0>2}-{d:0>2}_{d:0>2}.{d:0>2}.{d:0>2}.{d:0>3}", .{ year, month, day, hour, minute, second, millis }) catch unreachable;

    return result;
}
