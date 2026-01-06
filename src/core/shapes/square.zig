const std = @import("std");
const shape = @import("shape.zig");

pub const Square = struct {
    pub fn init() !shape.Shape {
        const positions = [_][3]f32{
            .{ -0.5, -0.5, 0.0 }, // 1
            .{ 0.5, -0.5, 0.0 }, // 2
            .{ 0.5, 0.5, 0.0 }, // 3
            .{ -0.5, 0.5, 0.0 }, // 4
        };

        const texcoords = [_][2]f32{
            .{ 0.0, 0.0 },
            .{ 1.0, 0.0 },
            .{ 1.0, 1.0 },
            .{ 0.0, 1.0 },
        };

        const normals = [_][3]f32{};

        const indices = [_]u32{ 0, 2, 1, 0, 3, 2 };

        return shape.initGLBuffers(
            .square,
            &positions,
            &texcoords,
            &normals,
            &indices,
            false,
        );
    }
};
