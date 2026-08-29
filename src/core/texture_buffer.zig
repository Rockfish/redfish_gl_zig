const std = @import("std");
const math = @import("math");
const gl = @import("zopengl").bindings;
const gl_debug = @import("gl_debug.zig");

const log = std.log.scoped(.texture_buffer);

pub const TextureBuffer = struct {
    gl_texture_id: c_uint,
    gl_buffer_id: c_uint,

    const Self = @This();

    pub fn createTextureBuffer(comptime T: type, data: []T) TextureBuffer {
        log.debug("Creating texture buffer for [] of type: {s}  length: {d}  sizeof: {d}", .{ @typeName(T), data.len, @sizeOf(T) });
        // 1. Create a regular Buffer Object (VBO) to hold the matrix data
        var tbo_buffer: gl.Uint = undefined;
        gl.genBuffers(1, &tbo_buffer);
        gl.bindBuffer(gl.TEXTURE_BUFFER, tbo_buffer);

        // Upload raw matrix data size = data.len * 64 bytes
        gl.bufferData(
            gl.TEXTURE_BUFFER,
            @intCast(data.len * @sizeOf(T)),
            data.ptr,
            gl.STATIC_DRAW,
        );

        gl_debug.check("1. glBufferData");

        // 2. Create the Buffer Texture
        // Attach the buffer storage to the texture target using RGBA32F
        // Each Mat4 takes exactly 4 texels (16 floats total)
        var gl_texture_id: gl.Uint = undefined;

        gl.genTextures(1, &gl_texture_id);
        gl.bindTexture(gl.TEXTURE_BUFFER, gl_texture_id);
        gl.texBuffer(gl.TEXTURE_BUFFER, gl.RGBA32F, tbo_buffer);

        gl_debug.check("2. glTexBuffer");

        log.debug("texture buffer created", .{});

        gl.bindBuffer(gl.TEXTURE_BUFFER, 0);
        gl.bindTexture(gl.TEXTURE_BUFFER, 0);

        return TextureBuffer{
            .gl_texture_id = gl_texture_id,
            .gl_buffer_id = tbo_buffer,
        };
    }

    /// Replaces the whole buffer. `gl.bufferData` reallocates, so `data` can be a
    /// of different lengths. The GPU can keep reading the old contents
    /// while the new store is filled. `gl.DYNAMIC_DRAW` hints that this buffer gets updated.
    pub fn updateTextureBuffer(self: *Self, comptime T: type, data: []T) void {
        gl.bindBuffer(gl.TEXTURE_BUFFER, self.gl_buffer_id);
        gl.bufferData(
            gl.TEXTURE_BUFFER,
            @intCast(data.len * @sizeOf(T)),
            data.ptr,
            gl.DYNAMIC_DRAW,
        );
        gl.bindBuffer(gl.TEXTURE_BUFFER, 0);
    }

    pub fn deleteGlObjects(self: *Self) void {
        gl.deleteBuffers(1, &self.gl_buffer_id);
        gl.deleteTextures(1, &self.gl_texture_id);
    }
};
