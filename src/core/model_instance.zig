const std = @import("std");
const Shader = @import("shader.zig").Shader;
const Mesh = @import("mesh.zig").Mesh;
const Animator = @import("animator.zig").Animator;
const AnimationClip = @import("animator.zig").AnimationClip;
const gltf_types = @import("gltf/gltf.zig");
const GltfAsset = @import("asset_loader.zig").GltfAsset;
const constants = @import("constants.zig");

const BakedAnimator = @import("bake_animation.zig").BakedAnimator;

const log = std.log.scoped(.model_instance);

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

pub const AnimatorType = union(enum) {
    none: void,
    animator: *Animator,
    baked_animator: *BakedAnimator,
};

pub const ModelInstance = struct {
    alloc: Allocator,
    name: []const u8,
    meshes: []*Mesh,
    animator: AnimatorType,
    gltf_asset: *GltfAsset,

    const Self = @This();

    pub fn init(
        alloc: Allocator,
        name: []const u8,
        animator: AnimatorType,
        gltf_asset: *GltfAsset,
    ) !*Self {
        const meshes = try alloc.alloc(*Mesh, gltf_asset.gltf.meshes.?.len);

        if (gltf_asset.gltf.meshes) |gltf_meshes| {
            for (gltf_meshes, 0..) |gltf_mesh, mesh_index| {
                meshes[mesh_index] = try Mesh.init(alloc, gltf_asset, gltf_mesh, mesh_index);
            }
        }

        const model = try alloc.create(ModelInstance);
        model.* = ModelInstance{
            .alloc = alloc,
            .name = try alloc.dupe(u8, name),
            .meshes = meshes,
            .animator = animator,
            .gltf_asset = gltf_asset,
        };

        return model;
    }

    pub fn deleteGlObjects(self: *Self) void {
        for (self.meshes) |mesh| {
            mesh.deleteGlObjects();
        }

        self.gltf_asset.deleteGlObjects();
    }

    pub fn updateAnimation(self: *Self, delta_time: f32) !void {
        switch (self.animator) {
            .animator => |obj| try obj.updateAnimation(delta_time),
            .baked_animator => |obj| try obj.updateAnimation(delta_time),
            else => {},
        }
    }

    pub fn playClip(self: *Self, clip: AnimationClip) !void {
        switch (self.animator) {
            .animator => |obj| try obj.playClip(clip),
            .baked_animator => |obj| obj.playClip(clip),
            else => {},
        }
    }

    pub fn draw(self: *Self, shader: *Shader, instance_count: u32) void {
        switch (self.animator) {
            .animator => |obj| obj.draw(self, shader, instance_count),
            .baked_animator => |obj| obj.draw(self, shader, instance_count),
            else => {
                for (self.meshes, 0..) |mesh, index| {
                    shader.setInt("meshID", @intCast(index));
                    mesh.draw(self.gltf_asset, shader, instance_count);
                }
            },
        }
    }
};
