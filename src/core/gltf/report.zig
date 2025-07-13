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

    /// Generate detailed glTF report with animation keyframes and skin data
    pub fn generateDetailedReport(allocator: Allocator, gltf_asset: *const GltfAsset, animation_limit: ?u32, skin_limit: ?u32) ![]u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        defer buffer.deinit();

        const writer = buffer.writer();

        try writeReportHeader(writer, gltf_asset);
        try writeSceneInfo(writer, gltf_asset, 0);
        try writeMeshInfo(writer, gltf_asset, 0);
        try writeAccessorInfo(writer, gltf_asset, 0);
        try writeDetailedAnimationInfo(writer, allocator, gltf_asset, 0, animation_limit);
        try writeDetailedSkinInfo(writer, allocator, gltf_asset, 0, skin_limit);
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

    /// Write detailed glTF report to a file with animation keyframes and skin data
    pub fn writeDetailedReportToFile(allocator: Allocator, gltf_asset: *const GltfAsset, path: []const u8, animation_limit: ?u32, skin_limit: ?u32) !void {
        const report = try generateDetailedReport(allocator, gltf_asset, animation_limit, skin_limit);
        defer allocator.free(report);

        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        try file.writeAll(report);
    }
};

fn writeReportHeader(writer: anytype, gltf_asset: *const GltfAsset) !void {
    try writer.print("=== glTF Report ===\n", .{});
    try writer.print("File: {s}\n", .{gltf_asset.name});

    const asset = gltf_asset.gltf.asset;
    try writer.print("glTF Version: {s}\n", .{asset.version});
    if (asset.generator) |generator| {
        try writer.print("Generator: {s}\n", .{generator});
    }
    try writer.print("\n", .{});
}

fn writeSceneInfo(writer: anytype, gltf_asset: *const GltfAsset, indent: u32) !void {
    try writer.print("=== Scenes ===\n", .{});

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
        try writer.print("No scenes found\n", .{});
    }
    try writer.print("\n", .{});
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
    try writer.print("=== Meshes ===\n", .{});

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
                if (primitive.attributes.tex_coord_0) |tex| {
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
        try writer.print("No meshes found\n", .{});
    }
    try writer.print("\n", .{});
}

fn writeAccessorInfo(writer: anytype, gltf_asset: *const GltfAsset, indent: u32) !void {
    try writer.print("=== Accessors ===\n", .{});

    if (gltf_asset.gltf.accessors) |accessors| {
        for (accessors, 0..) |accessor, i| {
            try writeIndent(writer, indent);
            try writer.print("Accessor {d}:\n", .{i});

            try writeIndent(writer, indent + 2);
            try writer.print("Type: {any}\n", .{accessor.type_});

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
        try writer.print("No accessors found\n", .{});
    }
    try writer.print("\n", .{});
}

fn writeAnimationInfo(writer: anytype, gltf_asset: *const GltfAsset, indent: u32) !void {
    try writer.print("=== Animations ===\n", .{});

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
        try writer.print("No animations found\n", .{});
    }
    try writer.print("\n", .{});
}

fn writeMaterialInfo(writer: anytype, gltf_asset: *const GltfAsset, indent: u32) !void {
    try writer.print("=== Materials ===\n", .{});

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
        try writer.print("No materials found\n", .{});
    }
    try writer.print("\n", .{});
}

fn writeTextureInfo(writer: anytype, gltf_asset: *const GltfAsset, indent: u32) !void {
    try writer.print("=== Textures ===\n", .{});

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
        try writer.print("No textures found\n", .{});
    }
    try writer.print("\n", .{});
}

fn writeDetailedAnimationInfo(writer: anytype, allocator: Allocator, gltf_asset: *const GltfAsset, indent: u32, limit: ?u32) !void {
    try writer.print("=== Detailed Animation Data ===\n", .{});

    if (gltf_asset.gltf.animations) |animations| {
        for (animations, 0..) |animation, i| {
            try writeIndent(writer, indent);
            const name = animation.name orelse "unnamed";
            try writer.print("## Animation {d}: '{s}'\n", .{ i, name });

            try writeIndent(writer, indent + 2);
            try writer.print("Channels: {d} | Samplers: {d}\n\n", .{ animation.channels.len, animation.samplers.len });

            for (animation.channels, 0..) |channel, j| {
                try writeIndent(writer, indent + 2);
                const target_node = channel.target.node orelse 999;
                const target_node_name = if (gltf_asset.gltf.nodes != null and channel.target.node != null and channel.target.node.? < gltf_asset.gltf.nodes.?.len)
                    gltf_asset.gltf.nodes.?[channel.target.node.?].name orelse "unnamed"
                else
                    "unknown";

                try writer.print("### Channel {d}: {s} -> Node {d} ('{s}')\n", .{ j, @tagName(channel.target.path), target_node, target_node_name });

                if (channel.sampler < animation.samplers.len) {
                    const sampler = animation.samplers[channel.sampler];
                    try writeIndent(writer, indent + 4);
                    try writer.print("Interpolation: {s}\n", .{@tagName(sampler.interpolation)});

                    try writeAnimationKeyframes(writer, allocator, gltf_asset, sampler, channel.target.path, indent + 4, limit);
                }
                try writer.print("\n", .{});
            }
        }
    } else {
        try writer.print("No animations found\n", .{});
    }
    try writer.print("\n", .{});
}

fn writeAnimationKeyframes(writer: anytype, allocator: Allocator, gltf_asset: *const GltfAsset, sampler: gltf_types.AnimationSampler, target_path: gltf_types.TargetProperty, indent: u32, limit: ?u32) !void {
    if (gltf_asset.gltf.accessors == null) return;

    const accessors = gltf_asset.gltf.accessors.?;
    if (sampler.input >= accessors.len or sampler.output >= accessors.len) return;

    const input_accessor = accessors[sampler.input];
    const output_accessor = accessors[sampler.output];

    try writeIndent(writer, indent);
    try writer.print("Input (time): {d} keyframes | Output: {d} values\n", .{ input_accessor.count, output_accessor.count });

    const max_frames = if (limit) |l| @min(l, input_accessor.count) else input_accessor.count;
    const show_truncated = limit != null and input_accessor.count > limit.?;

    const input_data = try getAccessorData(allocator, gltf_asset, sampler.input, f32);
    defer if (input_data) |data| allocator.free(data);

    if (input_data == null) {
        try writeIndent(writer, indent);
        try writer.print("Unable to read keyframe input data\n", .{});
        return;
    }

    try writeIndent(writer, indent);
    try writer.print("Keyframes (showing first {d}):\n", .{max_frames});

    switch (target_path) {
        .translation, .scale => {
            const output_data = try getAccessorData(allocator, gltf_asset, sampler.output, [3]f32);
            defer if (output_data) |data| allocator.free(data);

            if (output_data == null) {
                try writeIndent(writer, indent);
                try writer.print("Unable to read keyframe output data\n", .{});
                return;
            }

            for (0..max_frames) |frame_idx| {
                if (frame_idx >= input_data.?.len) break;

                const time = input_data.?[frame_idx];
                try writeIndent(writer, indent + 2);
                try writer.print("[{d:>2}] t={d:.3}s: ", .{ frame_idx, time });

                if (frame_idx < output_data.?.len) {
                    const vec3_data = output_data.?[frame_idx];
                    try writer.print("({d:.3}, {d:.3}, {d:.3})\n", .{ vec3_data[0], vec3_data[1], vec3_data[2] });
                }
            }
        },
        .rotation => {
            const output_data = try getAccessorData(allocator, gltf_asset, sampler.output, [4]f32);
            defer if (output_data) |data| allocator.free(data);

            if (output_data == null) {
                try writeIndent(writer, indent);
                try writer.print("Unable to read keyframe output data\n", .{});
                return;
            }

            for (0..max_frames) |frame_idx| {
                if (frame_idx >= input_data.?.len) break;

                const time = input_data.?[frame_idx];
                try writeIndent(writer, indent + 2);
                try writer.print("[{d:>2}] t={d:.3}s: ", .{ frame_idx, time });

                if (frame_idx < output_data.?.len) {
                    const quat_data = output_data.?[frame_idx];
                    try writer.print("quat({d:.3}, {d:.3}, {d:.3}, {d:.3})\n", .{ quat_data[0], quat_data[1], quat_data[2], quat_data[3] });
                }
            }
        },
        .weights => {
            const output_data = try getAccessorData(allocator, gltf_asset, sampler.output, f32);
            defer if (output_data) |data| allocator.free(data);

            if (output_data == null) {
                try writeIndent(writer, indent);
                try writer.print("Unable to read keyframe output data\n", .{});
                return;
            }

            for (0..max_frames) |frame_idx| {
                if (frame_idx >= input_data.?.len) break;

                const time = input_data.?[frame_idx];
                try writeIndent(writer, indent + 2);
                try writer.print("[{d:>2}] t={d:.3}s: ", .{ frame_idx, time });

                if (frame_idx < output_data.?.len) {
                    const weight_data = output_data.?[frame_idx];
                    try writer.print("{d:.3}\n", .{weight_data});
                }
            }
        },
    }

    if (show_truncated) {
        try writeIndent(writer, indent);
        try writer.print("... ({d} more keyframes truncated)\n", .{input_data.?.len - max_frames});
    }
}

fn writeDetailedSkinInfo(writer: anytype, allocator: Allocator, gltf_asset: *const GltfAsset, indent: u32, limit: ?u32) !void {
    try writer.print("=== Detailed Skin Data ===\n", .{});

    if (gltf_asset.gltf.skins) |skins| {
        for (skins, 0..) |skin, i| {
            try writeIndent(writer, indent);
            const name = skin.name orelse "unnamed";
            try writer.print("## Skin {d}: '{s}'\n", .{ i, name });

            try writeIndent(writer, indent + 2);
            try writer.print("Joints: {d}", .{skin.joints.len});
            if (skin.skeleton) |skeleton| {
                const skeleton_name = if (gltf_asset.gltf.nodes != null and skeleton < gltf_asset.gltf.nodes.?.len)
                    gltf_asset.gltf.nodes.?[skeleton].name orelse "unnamed"
                else
                    "unknown";
                try writer.print(" | Skeleton Root: Node {d} ('{s}')", .{ skeleton, skeleton_name });
            }
            try writer.print("\n\n", .{});

            const max_joints = if (limit) |l| @min(l, skin.joints.len) else skin.joints.len;
            const show_truncated = limit != null and skin.joints.len > limit.?;

            try writeIndent(writer, indent + 2);
            try writer.print("### Joint Hierarchy (showing first {d}):\n", .{max_joints});

            for (0..max_joints) |joint_idx| {
                const joint_node_idx = skin.joints[joint_idx];
                const joint_name = if (gltf_asset.gltf.nodes != null and joint_node_idx < gltf_asset.gltf.nodes.?.len)
                    gltf_asset.gltf.nodes.?[joint_node_idx].name orelse "unnamed"
                else
                    "unknown";

                try writeIndent(writer, indent + 4);
                try writer.print("[{d:>2}] Joint {d}: Node {d} ('{s}')\n", .{ joint_idx, joint_idx, joint_node_idx, joint_name });
            }

            if (show_truncated) {
                try writeIndent(writer, indent + 4);
                try writer.print("... ({d} more joints truncated)\n", .{skin.joints.len - max_joints});
            }

            if (skin.inverse_bind_matrices) |ibm_accessor_idx| {
                try writeIndent(writer, indent + 2);
                try writer.print("### Inverse Bind Matrices:\n", .{});
                try writeIndent(writer, indent + 4);
                try writer.print("Accessor {d} contains {d} 4x4 matrices\n", .{ ibm_accessor_idx, max_joints });

                if (gltf_asset.gltf.accessors != null and ibm_accessor_idx < gltf_asset.gltf.accessors.?.len) {
                    const ibm_data = getAccessorData(allocator, gltf_asset, ibm_accessor_idx, [16]f32) catch null;
                    defer if (ibm_data) |data| allocator.free(data);

                    if (ibm_data) |matrices| {
                        const max_matrices = @min(max_joints, matrices.len);
                        for (0..max_matrices) |mat_idx| {
                            try writeIndent(writer, indent + 4);
                            try writer.print("Matrix[{d}]: [{d:.3}, {d:.3}, {d:.3}, {d:.3}] (first row)\n", .{ mat_idx, matrices[mat_idx][0], matrices[mat_idx][1], matrices[mat_idx][2], matrices[mat_idx][3] });
                        }
                    } else {
                        try writeIndent(writer, indent + 4);
                        try writer.print("Unable to read inverse bind matrix data\n", .{});
                    }
                }
            }
            try writer.print("\n", .{});
        }
    } else {
        try writer.print("No skins found\n", .{});
    }
    try writer.print("\n", .{});
}

fn getAccessorData(allocator: Allocator, gltf_asset: *const GltfAsset, accessor_idx: u32, comptime T: type) !?[]T {
    if (gltf_asset.gltf.accessors == null or accessor_idx >= gltf_asset.gltf.accessors.?.len) {
        return null;
    }

    const accessor = gltf_asset.gltf.accessors.?[accessor_idx];
    if (gltf_asset.gltf.buffer_views == null or gltf_asset.gltf.buffers == null) {
        return null;
    }

    if (accessor.buffer_view == null or accessor.buffer_view.? >= gltf_asset.gltf.buffer_views.?.len) {
        return null;
    }

    const buffer_view = gltf_asset.gltf.buffer_views.?[accessor.buffer_view.?];
    if (buffer_view.buffer >= gltf_asset.gltf.buffers.?.len) {
        return null;
    }

    // Use the correct buffer data access pattern - buffer_data.items instead of buffer.data
    if (buffer_view.buffer >= gltf_asset.buffer_data.items.len) {
        return null;
    }

    const buffer_data = gltf_asset.buffer_data.items[buffer_view.buffer];
    if (buffer_data.len == 0) {
        return null;
    }

    const element_size = @sizeOf(T);
    const total_size = accessor.count * element_size;
    const required_bytes = buffer_view.byte_offset + accessor.byte_offset + total_size;

    if (required_bytes > buffer_data.len) {
        return null;
    }

    const data_start = buffer_data.ptr + buffer_view.byte_offset + accessor.byte_offset;
    const result = try allocator.alloc(T, accessor.count);

    @memcpy(result, @as([*]const T, @ptrCast(@alignCast(data_start)))[0..accessor.count]);
    return result;
}

fn writeIndent(writer: anytype, count: u32) !void {
    for (0..count) |_| {
        try writer.print(" ", .{});
    }
}
