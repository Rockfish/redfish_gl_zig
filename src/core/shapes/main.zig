const std = @import("std");
pub const Cube = @import("cube.zig").Cube;
pub const cubeboid = @import("cubeboid.zig");
pub const Cylinder = @import("cylinder.zig").Cylinder;
pub const Sphere = @import("sphere.zig").Sphere;
pub const Square = @import("square.zig").Square;
pub const Skybox = @import("skybox.zig").Skybox;
pub const SkyboxFaces = @import("skybox.zig").SkyboxFaces;

pub const Shape = @import("shape.zig").Shape;

pub fn createSquare() !Shape {
    return try Square.init();
}

pub const CubeConfig = cubeboid.CubeConfig;
pub fn createCube(config: cubeboid.CubeConfig) !Shape {
    return try cubeboid.Cubeboid.init(config);
}

pub fn createCylinder(allocator: std.mem.Allocator, radius: f32, height: f32, sides: u32) !Shape {
    return try Cylinder.init(allocator, radius, height, sides);
}

pub fn createSphere(allocator: std.mem.Allocator, radius: f32, poly_countX: u32, poly_countY: u32) !Shape {
    return try Sphere.init(allocator, radius, poly_countX, poly_countY);
}

// Either skybox is not a shape, or need better way of wrapping types with different fields and draw functions
pub fn createSkybox(allocator: std.mem.Allocator, faces: SkyboxFaces) Skybox {
    return Skybox.init(allocator, faces);
}