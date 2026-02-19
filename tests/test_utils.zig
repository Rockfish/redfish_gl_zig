const std = @import("std");

// Shared utilities for tests

pub const SAMPLE_MODELS_ROOT = "/Users/john/Dev/Assets/glTF-Sample-Models/2.0/";

pub const TestModel = struct {
    name: []const u8,
    gltf_path: []const u8,
    glb_path: []const u8,
    description: []const u8,
};

// Curated test models for different scenarios
pub const test_models = [_]TestModel{
    .{
        .name = "Box",
        .gltf_path = "Box/glTF/Box.gltf",
        .glb_path = "Box/glTF-Binary/Box.glb",
        .description = "Simple textured cube - minimal geometry",
    },
    .{
        .name = "BoxTextured",
        .gltf_path = "BoxTextured/glTF/BoxTextured.gltf",
        .glb_path = "BoxTextured/glTF-Binary/BoxTextured.glb",
        .description = "Textured cube with diffuse texture",
    },
    .{
        .name = "BoxAnimated",
        .gltf_path = "BoxAnimated/glTF/BoxAnimated.gltf",
        .glb_path = "BoxAnimated/glTF-Binary/BoxAnimated.glb",
        .description = "Animated cube with rotation",
    },
    .{
        .name = "Triangle",
        .gltf_path = "Triangle/glTF/Triangle.gltf",
        .glb_path = null, // No GLB version available
        .description = "Simplest possible geometry",
    },
};

pub fn getFullPath(allocator: std.mem.Allocator, relative_path: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}{s}", .{ SAMPLE_MODELS_ROOT, relative_path });
}

pub fn fileExists(path: []const u8) bool {
    const file = std.fs.cwd().openFile(path, .{}) catch return false;
    file.close();
    return true;
}

pub fn printTestHeader(test_name: []const u8) void {
    std.debug.print("\n🧪 Running test: {s}\n", .{test_name});
    std.debug.print("{'=':<50}\n", .{""});
}

pub fn printTestResult(success: bool, message: []const u8) void {
    if (success) {
        std.debug.print("✅ {s}\n", .{message});
    } else {
        std.debug.print("❌ {s}\n", .{message});
    }
}

pub fn printTestFooter() void {
    std.debug.print("{'=':<50}\n", .{""});
}
