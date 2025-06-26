const std = @import("std");
const core = @import("core");
const GltfAsset = core.asset_loader.GltfAsset;

// Integration test for GLB loading workflow
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test with Box.glb - should be the simplest GLB file
    const root = "/Users/john/Dev/Assets/glTF-Sample-Models/2.0/";
    const glb_path = "Box/glTF-Binary/Box.glb";
    const full_path = try std.fmt.allocPrint(allocator, "{s}{s}", .{ root, glb_path });
    defer allocator.free(full_path);

    std.debug.print("🧪 Testing GLB loading integration with: {s}\n", .{full_path});

    // Check if file exists
    const file = std.fs.cwd().openFile(full_path, .{}) catch |err| {
        std.debug.print("❌ Could not open file: {any}\n", .{err});
        std.debug.print("   Please ensure glTF sample models are available at: {s}\n", .{root});
        return;
    };
    file.close();

    // Try to load the GLB file
    const asset = GltfAsset.init(allocator, "Box", full_path) catch |err| {
        std.debug.print("❌ Failed to create GltfAsset: {any}\n", .{err});
        return;
    };

    asset.load() catch |err| {
        std.debug.print("❌ Failed to load GLB file: {any}\n", .{err});
        asset.deinit();
        return;
    };

    // If we get here, loading succeeded!
    std.debug.print("✅ GLB file loaded successfully!\n", .{});
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
    
    std.debug.print("   Buffer data loaded: {d} chunks\n", .{asset.buffer_data.items.len});
    if (asset.buffer_data.items.len > 0) {
        std.debug.print("     First chunk size: {d} bytes\n", .{asset.buffer_data.items[0].len});
    }

    // Clean up
    asset.deinit();
    std.debug.print("✅ GLB loading integration test completed successfully!\n", .{});
}