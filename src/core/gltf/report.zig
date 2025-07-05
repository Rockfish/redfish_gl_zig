const std = @import("std");
const GltfAsset = @import("../asset_loader.zig").GltfAsset;
const gltf_types = @import("gltf.zig");

const Allocator = std.mem.Allocator;

pub const GltfReport = struct {
    /// Generate a comprehensive glTF report as a formatted string
    pub fn generateReport(allocator: Allocator, gltf_asset: *const GltfAsset) ![]u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        defer buffer.deinit();

        const writer = buffer.writer();

        try writeReportHeader(writer, gltf_asset);
        try writeSceneInfo(writer, gltf_asset, 0);
        try writeMeshInfo(writer, gltf_asset, 0);
        try writeAccessorInfo(writer, gltf_asset, 0);
        try writeAnimationInfo(writer, gltf_asset, 0);
        try writeMaterialInfo(writer, gltf_asset, 0);
        try writeTextureInfo(writer, gltf_asset, 0);

        return buffer.toOwnedSlice();
    }

    /// Print glTF report directly to console
    pub fn printReport(gltf_asset: *const GltfAsset) void {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const allocator = gpa.allocator();

        const report = generateReport(allocator, gltf_asset) catch {
            std.debug.print("Error generating glTF report\n", .{});
            return;
        };
        defer allocator.free(report);

        std.debug.print("{s}", .{report});
    }

    /// Write glTF report to a file
    pub fn writeReportToFile(allocator: Allocator, gltf_asset: *const GltfAsset, path: []const u8) !void {
        const report = try generateReport(allocator, gltf_asset);
        defer allocator.free(report);

        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        try file.writeAll(report);
    }
};

fn writeReportHeader(writer: anytype, gltf_asset: *const GltfAsset) !void {
    try writer.print("=== glTF Report ===\n");
    try writer.print("File: {s}\n", .{gltf_asset.name});

    if (gltf_asset.gltf.asset) |asset| {
        if (asset.version) |version| {
            try writer.print("glTF Version: {s}\n", .{version});
        }
        if (asset.generator) |generator| {
            try writer.print("Generator: {s}\n", .{generator});
        }
    }
    try writer.print("\n");
}

fn writeSceneInfo(writer: anytype, gltf_asset: *const GltfAsset, indent: u32) !void {
    try writer.print("=== Scenes ===\n");

    if (gltf_asset.gltf.scenes) |scenes| {
        for (scenes, 0..) |scene, i| {
            try writeIndent(writer, indent);
            const name = scene.name orelse "unnamed";
            try writer.print("Scene {d}: '{s}'\n", .{ i, name });

            if (scene.nodes) |nodes| {
                try writeIndent(writer, indent + 2);
                try writer.print("Root nodes: {d}\n", .{nodes.len});

                for (nodes, 0..) |node_idx, j| {
                    try writeIndent(writer, indent + 4);
                    try writer.print("Root {d}: Node {d}\n", .{ j, node_idx });
                    try writeNodeHierarchy(writer, gltf_asset, node_idx, indent + 6);
                }
            }
        }
    } else {
        try writer.print("No scenes found\n");
    }
    try writer.print("\n");
}

fn writeNodeHierarchy(writer: anytype, gltf_asset: *const GltfAsset, node_idx: u32, indent: u32) !void {
    if (gltf_asset.gltf.nodes == null or node_idx >= gltf_asset.gltf.nodes.?.len) return;

    const node = gltf_asset.gltf.nodes.?[node_idx];
    try writeIndent(writer, indent);

    const name = node.name orelse "unnamed";
    const mesh_count = if (node.mesh != null) @as(u32, 1) else @as(u32, 0);
    const children_count = if (node.children) |children| children.len else 0;
    const has_skin = node.skin != null;

    try writer.print("Node {d}: '{s}' (mesh: {d}, children: {d}, skin: {})\n", .{ node_idx, name, mesh_count, children_count, has_skin });

    if (node.children) |children| {
        for (children) |child_idx| {
            try writeNodeHierarchy(writer, gltf_asset, child_idx, indent + 2);
        }
    }
}

fn writeMeshInfo(writer: anytype, gltf_asset: *const GltfAsset, indent: u32) !void {
    try writer.print("=== Meshes ===\n");

    if (gltf_asset.gltf.meshes) |meshes| {
        for (meshes, 0..) |mesh, i| {
            try writeIndent(writer, indent);
            const name = mesh.name orelse "unnamed";
            try writer.print("Mesh {d}: '{s}'\n", .{ i, name });

            for (mesh.primitives, 0..) |primitive, j| {
                try writeIndent(writer, indent + 2);
                try writer.print("Primitive {d}:\n", .{j});

                try writeIndent(writer, indent + 4);
                try writer.print("Mode: {any}\n", .{primitive.mode});

                if (primitive.indices) |indices| {
                    try writeIndent(writer, indent + 4);
                    try writer.print("Indices: accessor {d}\n", .{indices});
                }

                if (primitive.material) |material| {
                    try writeIndent(writer, indent + 4);
                    try writer.print("Material: {d}\n", .{material});
                }

                try writeIndent(writer, indent + 4);
                try writer.print("Attributes:\n", .{});
                if (primitive.attributes.position) |pos| {
                    try writeIndent(writer, indent + 6);
                    try writer.print("POSITION: accessor {d}\n", .{pos});
                }
                if (primitive.attributes.normal) |norm| {
                    try writeIndent(writer, indent + 6);
                    try writer.print("NORMAL: accessor {d}\n", .{norm});
                }
                if (primitive.attributes.texcoord_0) |tex| {
                    try writeIndent(writer, indent + 6);
                    try writer.print("TEXCOORD_0: accessor {d}\n", .{tex});
                }
                if (primitive.attributes.color_0) |color| {
                    try writeIndent(writer, indent + 6);
                    try writer.print("COLOR_0: accessor {d}\n", .{color});
                }
                if (primitive.attributes.joints_0) |joints| {
                    try writeIndent(writer, indent + 6);
                    try writer.print("JOINTS_0: accessor {d}\n", .{joints});
                }
                if (primitive.attributes.weights_0) |weights| {
                    try writeIndent(writer, indent + 6);
                    try writer.print("WEIGHTS_0: accessor {d}\n", .{weights});
                }
            }
        }
    } else {
        try writer.print("No meshes found\n");
    }
    try writer.print("\n");
}

fn writeAccessorInfo(writer: anytype, gltf_asset: *const GltfAsset, indent: u32) !void {
    try writer.print("=== Accessors ===\n");

    if (gltf_asset.gltf.accessors) |accessors| {
        for (accessors, 0..) |accessor, i| {
            try writeIndent(writer, indent);
            try writer.print("Accessor {d}:\n", .{i});

            try writeIndent(writer, indent + 2);
            try writer.print("Type: {any}\n", .{accessor.type});

            try writeIndent(writer, indent + 2);
            try writer.print("Component Type: {any}\n", .{accessor.component_type});

            try writeIndent(writer, indent + 2);
            try writer.print("Count: {d}\n", .{accessor.count});

            if (accessor.buffer_view) |buffer_view| {
                try writeIndent(writer, indent + 2);
                try writer.print("Buffer View: {d}\n", .{buffer_view});
            }

            if (accessor.byte_offset > 0) {
                try writeIndent(writer, indent + 2);
                try writer.print("Byte Offset: {d}\n", .{accessor.byte_offset});
            }

            if (accessor.normalized) {
                try writeIndent(writer, indent + 2);
                try writer.print("Normalized: true\n", .{});
            }
        }
    } else {
        try writer.print("No accessors found\n");
    }
    try writer.print("\n");
}

fn writeAnimationInfo(writer: anytype, gltf_asset: *const GltfAsset, indent: u32) !void {
    try writer.print("=== Animations ===\n");

    if (gltf_asset.gltf.animations) |animations| {
        for (animations, 0..) |animation, i| {
            try writeIndent(writer, indent);
            const name = animation.name orelse "unnamed";
            try writer.print("Animation {d}: '{s}'\n", .{ i, name });

            try writeIndent(writer, indent + 2);
            try writer.print("Channels: {d}\n", .{animation.channels.len});

            try writeIndent(writer, indent + 2);
            try writer.print("Samplers: {d}\n", .{animation.samplers.len});

            for (animation.channels, 0..) |channel, j| {
                try writeIndent(writer, indent + 4);
                try writer.print("Channel {d}: Node {d}, Path: {any}\n", .{ j, channel.target.node orelse 999, channel.target.path });
            }
        }
    } else {
        try writer.print("No animations found\n");
    }
    try writer.print("\n");
}

fn writeMaterialInfo(writer: anytype, gltf_asset: *const GltfAsset, indent: u32) !void {
    try writer.print("=== Materials ===\n");

    if (gltf_asset.gltf.materials) |materials| {
        for (materials, 0..) |material, i| {
            try writeIndent(writer, indent);
            const name = material.name orelse "unnamed";
            try writer.print("Material {d}: '{s}'\n", .{ i, name });

            if (material.pbr_metallic_roughness) |pbr| {
                try writeIndent(writer, indent + 2);
                try writer.print("PBR Metallic Roughness:\n", .{});

                if (pbr.base_color_texture) |texture| {
                    try writeIndent(writer, indent + 4);
                    try writer.print("Base Color Texture: {d}\n", .{texture.index});
                }

                if (pbr.metallic_roughness_texture) |texture| {
                    try writeIndent(writer, indent + 4);
                    try writer.print("Metallic Roughness Texture: {d}\n", .{texture.index});
                }

                try writeIndent(writer, indent + 4);
                try writer.print("Metallic Factor: {d:.3}\n", .{pbr.metallic_factor});

                try writeIndent(writer, indent + 4);
                try writer.print("Roughness Factor: {d:.3}\n", .{pbr.roughness_factor});
            }

            if (material.normal_texture) |texture| {
                try writeIndent(writer, indent + 2);
                try writer.print("Normal Texture: {d}\n", .{texture.index});
            }

            if (material.emissive_texture) |texture| {
                try writeIndent(writer, indent + 2);
                try writer.print("Emissive Texture: {d}\n", .{texture.index});
            }
        }
    } else {
        try writer.print("No materials found\n");
    }
    try writer.print("\n");
}

fn writeTextureInfo(writer: anytype, gltf_asset: *const GltfAsset, indent: u32) !void {
    try writer.print("=== Textures ===\n");

    if (gltf_asset.gltf.textures) |textures| {
        for (textures, 0..) |texture, i| {
            try writeIndent(writer, indent);
            try writer.print("Texture {d}:\n", .{i});

            if (texture.source) |source| {
                try writeIndent(writer, indent + 2);
                try writer.print("Image Source: {d}\n", .{source});
            }

            if (texture.sampler) |sampler| {
                try writeIndent(writer, indent + 2);
                try writer.print("Sampler: {d}\n", .{sampler});
            }
        }
    } else {
        try writer.print("No textures found\n");
    }
    try writer.print("\n");
}

fn writeIndent(writer: anytype, count: u32) !void {
    for (0..count) |_| {
        try writer.print(" ", .{});
    }
}
