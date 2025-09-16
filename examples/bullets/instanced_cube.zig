const gl = @import("zopengl").bindings;
const math = @import("math");

const Mat4 = math.Mat4;

const SIZE_OF_FLOAT = @sizeOf(f32);
const SIZE_OF_VEC4 = @sizeOf(math.Vec4);
const SIZE_OF_MAT4 = @sizeOf(math.Mat4);

const CUBE_VERTICES = [_]f32{
    // positions      // texture Coords
    -0.5, -0.5, -0.5, 0.0, 0.0,
    0.5,  -0.5, -0.5, 1.0, 0.0,
    0.5,  0.5,  -0.5, 1.0, 1.0,
    0.5,  0.5,  -0.5, 1.0, 1.0,
    -0.5, 0.5,  -0.5, 0.0, 1.0,
    -0.5, -0.5, -0.5, 0.0, 0.0,

    -0.5, -0.5, 0.5,  0.0, 0.0,
    0.5,  -0.5, 0.5,  1.0, 0.0,
    0.5,  0.5,  0.5,  1.0, 1.0,
    0.5,  0.5,  0.5,  1.0, 1.0,
    -0.5, 0.5,  0.5,  0.0, 1.0,
    -0.5, -0.5, 0.5,  0.0, 0.0,

    -0.5, 0.5,  0.5,  1.0, 0.0,
    -0.5, 0.5,  -0.5, 1.0, 1.0,
    -0.5, -0.5, -0.5, 0.0, 1.0,
    -0.5, -0.5, -0.5, 0.0, 1.0,
    -0.5, -0.5, 0.5,  0.0, 0.0,
    -0.5, 0.5,  0.5,  1.0, 0.0,

    0.5,  0.5,  0.5,  1.0, 0.0,
    0.5,  0.5,  -0.5, 1.0, 1.0,
    0.5,  -0.5, -0.5, 0.0, 1.0,
    0.5,  -0.5, -0.5, 0.0, 1.0,
    0.5,  -0.5, 0.5,  0.0, 0.0,
    0.5,  0.5,  0.5,  1.0, 0.0,

    -0.5, -0.5, -0.5, 0.0, 1.0,
    0.5,  -0.5, -0.5, 1.0, 1.0,
    0.5,  -0.5, 0.5,  1.0, 0.0,
    0.5,  -0.5, 0.5,  1.0, 0.0,
    -0.5, -0.5, 0.5,  0.0, 0.0,
    -0.5, -0.5, -0.5, 0.0, 1.0,

    -0.5, 0.5,  -0.5, 0.0, 1.0,
    0.5,  0.5,  -0.5, 1.0, 1.0,
    0.5,  0.5,  0.5,  1.0, 0.0,
    0.5,  0.5,  0.5,  1.0, 0.0,
    -0.5, 0.5,  0.5,  0.0, 0.0,
    -0.5, 0.5,  -0.5, 0.0, 1.0,
};

pub const InstancedCube = struct {
    vao: u32,
    vbo: u32,
    transforms_vbo: u32,

    const Self = @This();

    pub fn deinit(self: *Self) void {
        gl.DeleteVertexArrays(1, &self.vao);
        gl.DeleteBuffers(1, &self.vbo);
        gl.DeleteBuffers(1, &self.transforms_vbo);
    }

    pub fn init() Self {
        var vao: u32 = undefined;
        var vbo: u32 = undefined;
        var transforms_vbo: gl.Uint = 0;

        gl.genVertexArrays(1, &vao);
        gl.genBuffers(1, &vbo);

        gl.bindVertexArray(vao);

        // vertices
        gl.bindBuffer(gl.ARRAY_BUFFER, vbo);
        gl.bufferData(
            gl.ARRAY_BUFFER,
            @as(isize, @intCast(CUBE_VERTICES.len * SIZE_OF_FLOAT)),
            &CUBE_VERTICES,
            gl.STATIC_DRAW,
        );

        // position
        gl.enableVertexAttribArray(0);
        gl.vertexAttribPointer(
            0,
            3,
            gl.FLOAT,
            gl.FALSE,
            SIZE_OF_FLOAT * 5,
            @ptrFromInt(0),
        );

        // texture coordinates
        gl.enableVertexAttribArray(1);
        gl.vertexAttribPointer(
            1,
            2,
            gl.FLOAT,
            gl.FALSE,
            SIZE_OF_FLOAT * 5,
            @ptrFromInt(SIZE_OF_FLOAT * 3),
        );

        // Per instance transform matrix (locations 2, 3, 4, 5)
        gl.genBuffers(1, &transforms_vbo);
        gl.bindBuffer(gl.ARRAY_BUFFER, transforms_vbo);

        // Mat4 is 4 Vec4s, so we need 4 attribute locations
        for (0..4) |i| {
            const location: c_uint = @intCast(2 + i);
            gl.enableVertexAttribArray(location);
            gl.vertexAttribPointer(
                location,
                4,
                gl.FLOAT,
                gl.FALSE,
                SIZE_OF_MAT4,
                @ptrFromInt(i * SIZE_OF_VEC4),
            );
            // one matrix per bullet instance
            gl.vertexAttribDivisor(location, 1);
        }

        return .{
            .vao = vao,
            .vbo = vbo,
            .transforms_vbo = transforms_vbo,
        };
    }

    pub fn draw(self: *const Self, transforms: []Mat4, count: usize) void {
        gl.bindVertexArray(self.vao);

        gl.bindBuffer(gl.ARRAY_BUFFER, self.transforms_vbo);
        gl.bufferData(
            gl.ARRAY_BUFFER,
            @intCast(transforms.len * SIZE_OF_MAT4),
            transforms.ptr,
            gl.STREAM_DRAW,
        );

        gl.drawArraysInstanced(gl.TRIANGLES, 0, 36, @intCast(count));
        gl.bindVertexArray(0);
    }
};
