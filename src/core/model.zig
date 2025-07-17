const std = @import("std");
const math = @import("math");
const gltf_types = @import("gltf/gltf.zig");
const GltfAsset = @import("asset_loader.zig").GltfAsset;
const Shader = @import("shader.zig").Shader;
const Mesh = @import("mesh.zig").Mesh;
const MeshPrimitive = @import("mesh.zig").MeshPrimitive;
const Animator = @import("animator.zig").Animator;
const Transform = @import("transform.zig").Transform;
const AABB = @import("aabb.zig").AABB;

const Mat4 = math.Mat4;
const mat4 = math.mat4;
const Vec3 = math.Vec3;
const vec3 = math.vec3;
const vec4 = math.vec4;
const Quat = math.Quat;

const animation = @import("animator.zig");

const ArenaAllocator = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

// const Animator = animation.Animator;
// const WeightedAnimation = animation.WeightedAnimation;

const MAX_JOINTS = 100;

pub const Model = struct {
    arena: *ArenaAllocator,
    name: []const u8,
    scene: usize,
    meshes: *ArrayList(*Mesh),
    animator: *Animator,
    single_mesh_select: i32 = -1,
    gltf_asset: *GltfAsset,

    const Self = @This();

    pub fn init(
        arena: *ArenaAllocator,
        name: []const u8,
        meshes: *ArrayList(*Mesh),
        animator: *Animator,
        gltf_asset: *GltfAsset,
    ) !*Self {
        const allocator = arena.allocator();
        const model = try allocator.create(Model);
        model.* = Model{
            .arena = arena,
            .scene = 0,
            .name = try allocator.dupe(u8, name),
            .meshes = meshes,
            .animator = animator,
            .gltf_asset = gltf_asset,
        };

        return model;
    }

    pub fn deinit(self: *Self) void {

        // Cleanup GL resources first
        for (self.meshes.items) |mesh| {
            mesh.cleanUp();
        }

        var texture_iterator = self.gltf_asset.loaded_textures.valueIterator();
        while (texture_iterator.next()) |tex| {
            tex.*.deleteGlTexture();
        }

        // Cleanup animator
        self.animator.deinit();

        // Then free all memory at once
        const parent_allocator = self.arena.child_allocator;
        const arena = self.arena;
        arena.deinit();
        parent_allocator.destroy(arena);
    }

    // pub fn playClip(self: *Self, clip: AnimationClip) !void {
    //     try self.animator.playClip(clip);
    // }

    pub fn playTick(self: *Self, tick: f32) !void {
        try self.animator.playTick(tick);
    }

    // pub fn play_clip_with_transition(self: *Self, clip: AnimationClip, transition_duration: f32) !void {
    //     try self.animator.play_clip_with_transition(clip, transition_duration);
    // }

    pub fn playWeightAnimations(self: *Self, weighted_animations: []const animation.WeightedAnimation, frame_time: f32) !void {
        try self.animator.playWeightAnimations(weighted_animations, frame_time);
    }

    pub fn render(self: *Self, shader: *const Shader) void {
        shader.useShader();
        var buf: [256:0]u8 = undefined;
        for (0..MAX_JOINTS) |i| {
            const joint_transform = self.animator.joint_matrices[i];
            const uniform = std.fmt.bufPrintZ(&buf, "jointMatrices[{d}]", .{i}) catch unreachable;
            shader.setMat4(uniform, &joint_transform);
        }

        const scene = self.gltf_asset.gltf.scenes.?[self.scene];

        if (scene.nodes) |nodes| {
            for (nodes) |node_index| {
                const node = self.gltf_asset.gltf.nodes.?[node_index];
                self.renderNodes(shader, node, Mat4.identity());
            }
        }
    }

    pub fn debugPrintNodeStructure(self: *Self) void {
        debugPrintModelNodeStructure(self);
    }

    fn renderNodes(self: *Self, shader: *const Shader, node: gltf_types.Node, parent_transform: Mat4) void {
        const transform = Transform{
            .translation = node.translation orelse vec3(0.0, 0.0, 0.0),
            .rotation = node.rotation orelse math.quat(0.0, 0.0, 0.0, 1.0),
            .scale = node.scale orelse vec3(1.0, 1.0, 1.0),
        };
        const local_matrix = transform.toMatrix();
        const global_matrix = parent_transform.mulMat4(&local_matrix);

        // Debug output for node transforms (only print once per model load)
        const debug_nodes = false; // Disabled for now
        if (debug_nodes and node.mesh != null) {
            // Extract translation from global matrix
            const global_translation = vec3(global_matrix.data[0][3], global_matrix.data[1][3], global_matrix.data[2][3]);
            std.debug.print("Node with mesh {}: local_trans=({d:.2}, {d:.2}, {d:.2}) -> global_trans=({d:.2}, {d:.2}, {d:.2})\n", .{ node.mesh.?, transform.translation.x, transform.translation.y, transform.translation.z, global_translation.x, global_translation.y, global_translation.z });
        }

        shader.setMat4("nodeTransform", &global_matrix);

        if (node.mesh) |mesh_index| {
            const mesh = self.meshes.items[mesh_index];
            mesh.render(self.gltf_asset, shader);
        }

        if (node.children) |children| {
            for (children) |node_index| {
                const child = self.gltf_asset.gltf.nodes.?[node_index];
                self.renderNodes(shader, child, global_matrix);
            }
        }
    }

    pub fn set_shader_bones_for_mesh(self: *Self, shader: *const Shader, mesh: *MeshPrimitive) !void {
        var buf: [256:0]u8 = undefined;

        for (0..MAX_JOINTS) |i| {
            const joint_transform = self.animator.joint_matrices[i];
            const uniform = try std.fmt.bufPrintZ(&buf, "jointMatrices[{d}]", .{i});
            shader.set_mat4(uniform, &joint_transform);
        }
        // Use node matrix directly with bounds checking
        const node_matrix = if (mesh.id < self.animator.node_matrices.len)
            &self.animator.node_matrices[mesh.id]
        else
            &Mat4.identity();
        shader.setMat4("nodeTransform", node_matrix);
    }

    pub fn updateAnimation(self: *Self, delta_time: f32) !void {
        try self.animator.updateAnimation(delta_time);
    }

    pub fn calculateBoundingBox(self: *Self) AABB {
        var bbox = AABB.init();

        // Get the scene nodes and calculate bounds
        const scene = self.gltf_asset.gltf.scenes.?[self.scene];
        if (scene.nodes) |nodes| {
            for (nodes) |node_index| {
                const node = self.gltf_asset.gltf.nodes.?[node_index];
                self.calculateNodeBounds(&bbox, node, Mat4.identity());
            }
        }

        return bbox;
    }

    fn calculateNodeBounds(self: *Self, bbox: *AABB, node: gltf_types.Node, parent_transform: Mat4) void {
        const transform = Transform{
            .translation = node.translation orelse vec3(0.0, 0.0, 0.0),
            .rotation = node.rotation orelse math.quat(0.0, 0.0, 0.0, 1.0),
            .scale = node.scale orelse vec3(1.0, 1.0, 1.0),
        };
        const local_matrix = transform.toMatrix();
        const global_matrix = parent_transform.mulMat4(&local_matrix);

        // If this node has a mesh, calculate its bounds
        if (node.mesh) |mesh_index| {
            if (self.gltf_asset.gltf.meshes) |meshes| {
                const mesh = meshes[mesh_index];
                self.calculateMeshBounds(bbox, mesh, global_matrix);
            }
        }

        // Process child nodes
        if (node.children) |children| {
            for (children) |child_index| {
                const child_node = self.gltf_asset.gltf.nodes.?[child_index];
                self.calculateNodeBounds(bbox, child_node, global_matrix);
            }
        }
    }

    fn calculateMeshBounds(self: *Self, bbox: *AABB, mesh: gltf_types.Mesh, transform: Mat4) void {
        for (mesh.primitives) |primitive| {
            if (primitive.attributes.position) |position_accessor_index| {
                const accessor = self.gltf_asset.gltf.accessors.?[position_accessor_index];

                // Use accessor min/max if available (optimized path)
                if (accessor.min != null and accessor.max != null) {
                    const min_pos = vec3(accessor.min.?[0], accessor.min.?[1], accessor.min.?[2]);
                    const max_pos = vec3(accessor.max.?[0], accessor.max.?[1], accessor.max.?[2]);

                    // Transform the min/max corners and expand bounding box
                    const corners = [_]Vec3{
                        min_pos,
                        vec3(min_pos.x, min_pos.y, max_pos.z),
                        vec3(min_pos.x, max_pos.y, min_pos.z),
                        vec3(min_pos.x, max_pos.y, max_pos.z),
                        vec3(max_pos.x, min_pos.y, min_pos.z),
                        vec3(max_pos.x, min_pos.y, max_pos.z),
                        vec3(max_pos.x, max_pos.y, min_pos.z),
                        max_pos,
                    };

                    for (corners) |corner| {
                        const transformed_pos = transform.mulVec4(&vec4(corner.x, corner.y, corner.z, 1.0)).toVec3();
                        bbox.expand_to_include(transformed_pos);
                    }
                }
            }
        }
    }

    pub fn getVertexCount(self: *Self) u32 {
        var total_vertices: u32 = 0;
        for (self.meshes.items) |mesh| {
            for (mesh.primitives.items) |primitive| {
                total_vertices += primitive.vertex_count;
            }
        }
        return total_vertices;
    }

    pub fn getTextureCount(self: *Self) u32 {
        return @intCast(self.gltf_asset.loaded_textures.count());
    }

    pub fn getAnimationCount(self: *Self) u32 {
        if (self.gltf_asset.gltf.animations) |animations| {
            return @intCast(animations.len);
        }
        return 0;
    }

    pub fn getMeshPrimitiveCount(self: *Self) u32 {
        var total_primitives: u32 = 0;
        for (self.meshes.items) |mesh| {
            total_primitives += @intCast(mesh.primitives.items.len);
        }
        return total_primitives;
    }
};

// Debug functions for model analysis
pub fn debugPrintModelNodeStructure(model: *Model) void {
    std.debug.print("\n--- Model Node Structure for: {s} ---\n", .{model.name});
    const scene = model.gltf_asset.gltf.scenes.?[model.scene];
    if (scene.nodes) |nodes| {
        for (nodes) |node_index| {
            const node = model.gltf_asset.gltf.nodes.?[node_index];
            debugPrintNode(model.gltf_asset, node, node_index, 0);
        }
    }

    // Matrix multiplication is now fixed - debug disabled

    std.debug.print("--- End Node Structure ---\n\n", .{});
}

pub fn debugMatrixMultiplication() void {
    std.debug.print("\n=== MATRIX MULTIPLICATION DEBUG ===\n", .{});

    // Create parent transform (180° Y rotation)
    const parent_transform = Transform{
        .translation = vec3(0.0, 0.0, 0.0),
        .rotation = math.quat(0.0, 1.0, 0.0, 0.0), // 180° Y rotation
        .scale = vec3(1.0, 1.0, 1.0),
    };
    const parent_matrix = parent_transform.toMatrix();

    // Create child transform (translation only)
    const child_transform = Transform{
        .translation = vec3(-3.82, 13.02, 0.0),
        .rotation = math.quat(0.0, 0.0, 0.0, 1.0), // Identity
        .scale = vec3(1.0, 1.0, 1.0),
    };
    const child_matrix = child_transform.toMatrix();

    // Test multiplication
    const result_matrix = parent_matrix.mulMat4(&child_matrix);

    // Extract translation from result
    const result_translation = vec3(result_matrix.data[3][0], result_matrix.data[3][1], result_matrix.data[3][2]);

    // Debug the matrices themselves
    std.debug.print(
        "Parent matrix [3] (translation): ({d:.2}, {d:.2}, {d:.2}, {d:.2})\n",
        .{ parent_matrix.data[3][0], parent_matrix.data[3][1], parent_matrix.data[3][2], parent_matrix.data[3][3] },
    );
    std.debug.print(
        "Parent matrix [0]: ({d:.2}, {d:.2}, {d:.2}, {d:.2})\n",
        .{ parent_matrix.data[0][0], parent_matrix.data[0][1], parent_matrix.data[0][2], parent_matrix.data[0][3] },
    );
    std.debug.print(
        "Parent matrix [1]: ({d:.2}, {d:.2}, {d:.2}, {d:.2})\n",
        .{ parent_matrix.data[1][0], parent_matrix.data[1][1], parent_matrix.data[1][2], parent_matrix.data[1][3] },
    );
    std.debug.print(
        "Parent matrix [2]: ({d:.2}, {d:.2}, {d:.2}, {d:.2})\n",
        .{ parent_matrix.data[2][0], parent_matrix.data[2][1], parent_matrix.data[2][2], parent_matrix.data[2][3] },
    );

    std.debug.print(
        "Child matrix [3] (translation): ({d:.2}, {d:.2}, {d:.2}, {d:.2})\n",
        .{ child_matrix.data[3][0], child_matrix.data[3][1], child_matrix.data[3][2], child_matrix.data[3][3] },
    );

    std.debug.print(
        "Parent quaternion: ({d:.2}, {d:.2}, {d:.2}, {d:.2})\n",
        .{ parent_transform.rotation.data[0], parent_transform.rotation.data[1], parent_transform.rotation.data[2], parent_transform.rotation.data[3] },
    );
    std.debug.print(
        "Child translation: ({d:.2}, {d:.2}, {d:.2})\n",
        .{ child_transform.translation.x, child_transform.translation.y, child_transform.translation.z },
    );
    std.debug.print(
        "Result matrix [3] (translation): ({d:.2}, {d:.2}, {d:.2}, {d:.2})\n",
        .{ result_matrix.data[3][0], result_matrix.data[3][1], result_matrix.data[3][2], result_matrix.data[3][3] },
    );
    std.debug.print(
        "Result matrix [0]: ({d:.2}, {d:.2}, {d:.2}, {d:.2})\n",
        .{ result_matrix.data[0][0], result_matrix.data[0][1], result_matrix.data[0][2], result_matrix.data[0][3] },
    );
    std.debug.print(
        "Result translation: ({d:.2}, {d:.2}, {d:.2})\n",
        .{ result_translation.x, result_translation.y, result_translation.z },
    );
    std.debug.print(
        "Expected (manual): ({d:.2}, {d:.2}, {d:.2})\n",
        .{ 3.82, 13.02, 0.0 },
    ); // 180° Y rotation should flip X sign
    std.debug.print("=== END MATRIX DEBUG ===\n\n", .{});
}

fn debugPrintNode(gltf_asset: *GltfAsset, node: gltf_types.Node, node_index: usize, depth: usize) void {
    var indent_buf: [20]u8 = undefined;
    for (0..depth * 2) |i| {
        if (i < indent_buf.len) indent_buf[i] = ' ';
    }
    const indent = indent_buf[0..@min(depth * 2, indent_buf.len)];

    const transform = Transform{
        .translation = node.translation orelse vec3(0.0, 0.0, 0.0),
        .rotation = node.rotation orelse math.quat(0.0, 0.0, 0.0, 1.0),
        .scale = node.scale orelse vec3(1.0, 1.0, 1.0),
    };

    std.debug.print(
        "{s}Node[{}]: mesh={?} translation=({d:.2}, {d:.2}, {d:.2}) rotation=({d:.2}, {d:.2}, {d:.2}, {d:.2}) scale=({d:.2}, {d:.2}, {d:.2})\n",
        .{ indent, node_index, node.mesh, transform.translation.x, transform.translation.y, transform.translation.z, transform.rotation.data[0], transform.rotation.data[1], transform.rotation.data[2], transform.rotation.data[3], transform.scale.x, transform.scale.y, transform.scale.z },
    );

    if (node.children) |children| {
        for (children) |child_index| {
            const child_node = gltf_asset.gltf.nodes.?[child_index];
            debugPrintNode(gltf_asset, child_node, child_index, depth + 1);
        }
    }
}

pub fn dumpModelNodes(model: *Model) !void {
    std.debug.print("\n--- Dumping nodes ---\n", .{});
    var buf: [1024:0]u8 = undefined;

    var node_iterator = model.animator.node_transform_map.iterator();
    while (node_iterator.next()) |entry| { // |node_name, node_transform| {
        const name = entry.key_ptr.*;
        const transform = entry.value_ptr.*;
        const str = transform.transform.asString(&buf);
        std.debug.print("node_name: {s} : {s}\n", .{ name, str });
    }
    std.debug.print("\n", .{});

    var bone_iterator = model.animator.bone_map.iterator();
    while (bone_iterator.next()) |entry| { // |node_name, node_transform| {
        const name = entry.key_ptr.*;
        const transform = entry.value_ptr.*;
        const str = transform.offset_transform.asString(&buf);
        std.debug.print("bone_name: {s} : {s}\n", .{ name, str });
    }
}
