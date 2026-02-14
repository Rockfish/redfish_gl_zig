const std = @import("std");
const gl = @import("zopengl").bindings;
const zstbi = @import("core").zstbi;

const Allocator = std.mem.Allocator;

const SIZE_OF_U32 = @sizeOf(u32);
const SIZE_OF_FLOAT = @sizeOf(f32);

const SKYBOX_VERTICES = [_]f32{
    // positions
    -1.0, 1.0,  -1.0,
    -1.0, -1.0, -1.0,
    1.0,  -1.0, -1.0,
    1.0,  -1.0, -1.0,
    1.0,  1.0,  -1.0,
    -1.0, 1.0,  -1.0,

    -1.0, -1.0, 1.0,
    -1.0, -1.0, -1.0,
    -1.0, 1.0,  -1.0,
    -1.0, 1.0,  -1.0,
    -1.0, 1.0,  1.0,
    -1.0, -1.0, 1.0,

    1.0,  -1.0, -1.0,
    1.0,  -1.0, 1.0,
    1.0,  1.0,  1.0,
    1.0,  1.0,  1.0,
    1.0,  1.0,  -1.0,
    1.0,  -1.0, -1.0,

    -1.0, -1.0, 1.0,
    -1.0, 1.0,  1.0,
    1.0,  1.0,  1.0,
    1.0,  1.0,  1.0,
    1.0,  -1.0, 1.0,
    -1.0, -1.0, 1.0,

    -1.0, 1.0,  -1.0,
    1.0,  1.0,  -1.0,
    1.0,  1.0,  1.0,
    1.0,  1.0,  1.0,
    -1.0, 1.0,  1.0,
    -1.0, 1.0,  -1.0,

    -1.0, -1.0, -1.0,
    -1.0, -1.0, 1.0,
    1.0,  -1.0, -1.0,
    1.0,  -1.0, -1.0,
    -1.0, -1.0, 1.0,
    1.0,  -1.0, 1.0,
};

pub const SkyboxFaces = struct {
    right: [:0]const u8,
    left: [:0]const u8,
    top: [:0]const u8,
    bottom: [:0]const u8,
    front: [:0]const u8,
    back: [:0]const u8,
};

pub const Skybox = struct {
    vao: u32,
    vbo: u32,
    gl_texture_id: u32,

    const Self = @This();

    pub fn init(allocator: Allocator, faces: SkyboxFaces) Self {
        const vao, const vbo = loadSkybox();
        const gl_texture_id = loadCubemap(allocator, faces);
        return .{
            .vao = vao,
            .vbo = vbo,
            .gl_texture_id = gl_texture_id,
        };
    }

    pub fn deinit(self: *const Self) void {
        gl.deleteVertexArrays(1, &self.vao);
        gl.deleteBuffers(1, &self.vbo);
        gl.deleteTextures(1, &self.gl_texture_id);
    }

    /// draw skybox as last
    pub fn draw(self: *const Self) void {
        // change depth function so depth test passes when values are equal to depth buffer's content
        gl.depthFunc(gl.LEQUAL);
        gl.bindVertexArray(self.vao);
        gl.activeTexture(gl.TEXTURE0);
        gl.drawArrays(gl.TRIANGLES, 0, 36);
        gl.bindVertexArray(0);
        // set depth function back to default
        gl.depthFunc(gl.LESS);
    }

    fn loadSkybox() struct { u32, u32 } {
        var vao: u32 = undefined;
        var vbo: u32 = undefined;

        gl.genVertexArrays(1, &vao);
        gl.genBuffers(1, &vbo);
        gl.bindVertexArray(vao);

        // vertices
        gl.bindBuffer(gl.ARRAY_BUFFER, vbo);
        gl.bufferData(
            gl.ARRAY_BUFFER,
            @as(isize, @intCast(SKYBOX_VERTICES.len * SIZE_OF_FLOAT)),
            &SKYBOX_VERTICES,
            gl.STATIC_DRAW,
        );

        // position
        gl.vertexAttribPointer(
            0,
            3,
            gl.FLOAT,
            gl.FALSE,
            SIZE_OF_FLOAT * 3,
            @ptrFromInt(0),
        );
        gl.enableVertexAttribArray(0);

        return .{ vao, vbo };
    }

    // loads a cubemap texture from 6 individual texture faces
    // order:
    // +X (right)
    // -X (left)
    // +Y (top)
    // -Y (bottom)
    // +Z (front)
    // -Z (back)
    // -------------------------------------------------------
    fn loadCubemap(allocator: Allocator, faces: SkyboxFaces) u32 {
        zstbi.init(allocator);
        defer zstbi.deinit();

        var gl_texture_id: u32 = undefined;

        gl.genTextures(1, &gl_texture_id);
        gl.bindTexture(gl.TEXTURE_CUBE_MAP, gl_texture_id);

        addFace(faces.right, 0);
        addFace(faces.left, 1);
        addFace(faces.top, 2);
        addFace(faces.bottom, 3);
        addFace(faces.front, 4);
        addFace(faces.back, 5);

        // for (faces, 0..) |face, i| {
        //     var image = zstbi.Image.loadFromFile(face, 0) catch |err| {
        //         std.debug.print("Texture loadFromFile error: {any}  filepath: {s}\n", .{ err, face });
        //         @panic(@errorName(err));
        //     };
        //     defer image.deinit();
        //
        //     const format: u32 = switch (image.num_components) {
        //         0 => gl.RED,
        //         3 => gl.RGB,
        //         4 => gl.RGBA,
        //         else => gl.RED,
        //     };
        //
        //     gl.texImage2D(
        //         gl.TEXTURE_CUBE_MAP_POSITIVE_X + @as(c_uint, @intCast(i)),
        //         0,
        //         gl.RGB,
        //         @as(c_int, @intCast(image.width)),
        //         @as(c_int, @intCast(image.height)),
        //         0,
        //         format,
        //         gl.UNSIGNED_BYTE,
        //         image.data.ptr,
        //     );
        // }
        gl.texParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
        gl.texParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
        gl.texParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_R, gl.CLAMP_TO_EDGE);

        return gl_texture_id;
    }

    fn addFace(face: [:0]const u8, target: c_uint) void {
        var image = zstbi.Image.loadFromFile(face, 0) catch |err| {
            std.debug.print("Texture loadFromFile error: {any}  filepath: {s}\n", .{ err, face });
            @panic(@errorName(err));
        };
        defer image.deinit();

        const format: u32 = switch (image.num_components) {
            0 => gl.RED,
            3 => gl.RGB,
            4 => gl.RGBA,
            else => gl.RED,
        };

        gl.texImage2D(
            gl.TEXTURE_CUBE_MAP_POSITIVE_X + target,
            0,
            gl.RGB,
            @as(c_int, @intCast(image.width)),
            @as(c_int, @intCast(image.height)),
            0,
            format,
            gl.UNSIGNED_BYTE,
            image.data.ptr,
        );
    }
};
