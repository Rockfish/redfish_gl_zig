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

// const animation = @import("animator.zig");
// const AnimationClip = @import("animator.zig").AnimationClip;

const ArenaAllocator = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

// const Animator = animation.Animator;
// const WeightedAnimation = animation.WeightedAnimation;

const MAX_BONES = 4;
const MAX_NODES = 200;

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

    // pub fn play_weight_animations(self: *Self, weighted_animation: []const WeightedAnimation, frame_time: f32) !void {
    //     try self.animator.play_weight_animations(weighted_animation, frame_time);
    // }

    pub fn render(self: *Self, shader: *const Shader) void {
        // var buf: [256:0]u8 = undefined;
        // for (0..MAX_BONES) |i| {
        //     const bone_transform = self.animator.final_bone_matrices[i];
        //     const uniform = std.fmt.bufPrintZ(&buf, "finalBonesMatrices[{d}]", .{i}) catch unreachable;
        //     shader.set_mat4(uniform, &bone_transform);
        // }

        const scene = self.gltf_asset.gltf.scenes.?[self.scene];

        if (scene.nodes) |nodes| {
            for (nodes) |node_index| {
                const node = self.gltf_asset.gltf.nodes.?[node_index];
                self.renderNodes(shader, node, Mat4.identity());
            }
        }
    }

    fn renderNodes(self: *Self, shader: *const Shader, node: gltf_types.Node, parent_transform: Mat4) void {
        const transform = Transform{
            .translation = node.translation orelse vec3(0.0, 0.0, 0.0),
            .rotation = node.rotation orelse math.quat(0.0, 0.0, 0.0, 1.0),
            .scale = node.scale orelse vec3(1.0, 1.0, 1.0),
        };
        const local_matrix = transform.getMatrix();
        const global_matrix = parent_transform.mulMat4(&local_matrix);

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

        for (0..MAX_BONES) |i| {
            const bone_transform = self.animator.final_bone_matrices[i];
            const uniform = try std.fmt.bufPrintZ(&buf, "finalBonesMatrices[{d}]", .{i});
            shader.set_mat4(uniform, &bone_transform);
        }
        shader.setMat4("nodeTransform", &self.animator.final_node_matrices[@intCast(mesh.id)]);
    }

    pub fn update_animation(self: *Self, delta_time: f32) !void {
        try self.animator.update_animation(delta_time);
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
        const local_matrix = transform.getMatrix();
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
};

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
