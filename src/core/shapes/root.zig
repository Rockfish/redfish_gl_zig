const std = @import("std");
pub const Cube = @import("cube.zig").Cube;
pub const cubeboid = @import("cubeboid.zig");
pub const Cylinder = @import("cylinder.zig").Cylinder;
pub const Sphere = @import("sphere.zig").Sphere;
pub const Square = @import("square.zig").Square;
pub const Skybox = @import("skybox.zig").Skybox;
pub const SkyboxFaces = @import("skybox.zig").SkyboxFaces;
pub const Lines = @import("lines.zig").Lines;
pub const SimpleLines = @import("lines.zig").SimpleLines;
pub const LineSegment = @import("lines.zig").LineSegment;
pub const Plane = @import("plane.zig").Plane;

pub const Shape = @import("shape.zig").Shape;
pub const obj_loader = @import("obj_loader.zig");

pub fn loadOBJ(allocator: std.mem.Allocator, filepath: []const u8) !*Shape {
    return obj_loader.loadOBJ(allocator, filepath);
}

pub fn createSquare(allocator: std.mem.Allocator) !*Shape {
    return try Square.init(allocator);
}

pub const CubeConfig = cubeboid.CubeConfig;
pub fn createCube(allocator: std.mem.Allocator, config: cubeboid.CubeConfig) !*Shape {
    return try cubeboid.Cubeboid.init(allocator, config);
}

pub fn createCylinder(allocator: std.mem.Allocator, radius: f32, height: f32, sides: u32) !*Shape {
    return try Cylinder.init(allocator, radius, height, sides);
}

pub fn createSphere(allocator: std.mem.Allocator, radius: f32, poly_countX: u32, poly_countY: u32) !*Shape {
    return try Sphere.init(allocator, radius, poly_countX, poly_countY);
}

// Either skybox is not a shape, or need better way of wrapping types with different fields and draw functions
pub fn createSkybox(allocator: std.mem.Allocator, faces: SkyboxFaces) Skybox {
    return Skybox.init(allocator, faces);
}
