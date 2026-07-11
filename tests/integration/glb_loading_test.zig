const std = @import("std");
const core = @import("core");
const GltfAsset = core.asset_loader.GltfAsset;

// Integration test for GLB loading workflow
pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    // Use a GLB shipped with the project so the test does not depend on external sample packs
    const glb_path = "assets/models/sphere.glb";

    std.debug.print("Testing GLB loading integration with: {s}\n", .{glb_path});

    // Check if file exists via Io
    const file = std.Io.Dir.cwd().openFile(io, glb_path, .{}) catch |err| {
        std.debug.print("Could not open file: {any}\n", .{err});
        std.debug.print("   Expected project-relative path: {s}\n", .{glb_path});
        return error.FileNotFound;
    };
    file.close(io);

    // Try to load the GLB file
    const asset = GltfAsset.init(io, allocator, "Sphere", glb_path) catch |err| {
        std.debug.print("Failed to create GltfAsset: {any}\n", .{err});
        return err;
    };

    asset.load() catch |err| {
        std.debug.print("Failed to load GLB file: {any}\n", .{err});
        asset.deinit();
        return err;
    };

    // If we get here, loading succeeded
    std.debug.print("GLB file loaded successfully!\n", .{});
    std.debug.print("   Asset version: {s}\n", .{asset.gltf.asset.version});

    if (asset.gltf.meshes) |meshes| {
        std.debug.print("   Meshes: {d}\n", .{meshes.len});
        for (meshes, 0..) |mesh, i| {
            std.debug.print("     Mesh {d}: {d} primitives\n", .{ i, mesh.primitives.len });
        }
    }

    if (asset.gltf.buffers) |buffers| {
        std.debug.print("   Buffers: {d}\n", .{buffers.len});
        for (buffers, 0..) |buffer, i| {
            std.debug.print("     Buffer {d}: {d} bytes", .{ i, buffer.byte_length });
            if (buffer.uri) |uri| {
                std.debug.print(" (URI: {s})", .{uri});
            } else {
                std.debug.print(" (embedded)", .{});
            }
            std.debug.print("\n", .{});
        }
    }

    const buffer_chunks = asset.buffer_data.items();
    std.debug.print("   Buffer data loaded: {d} chunks\n", .{buffer_chunks.len});
    if (buffer_chunks.len > 0) {
        std.debug.print("     First chunk size: {d} bytes\n", .{buffer_chunks[0].len});
    }

    // Free arena-owned GltfAsset (normally owned by Model after buildModel)
    const arena = asset.arena;
    const parent_allocator = arena.child_allocator;
    asset.deinit();
    arena.deinit();
    parent_allocator.destroy(arena);

    std.debug.print("GLB loading integration test completed successfully!\n", .{});
}
