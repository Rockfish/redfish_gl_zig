const std = @import("std");
const math = @import("math");
const Shader = @import("shader.zig").Shader;
const Mesh = @import("mesh.zig").Mesh;
const Animator = @import("animator.zig").Animator;
const AnimationClip = @import("animator.zig").AnimationClip;
const gltf_types = @import("gltf/gltf.zig");
const GltfAsset = @import("gltf_asset.zig").GltfAsset;
const constants = @import("constants.zig");
const Context = @import("context.zig").Context;

const BakedAnimator = @import("baked_animator.zig").BakedAnimator;

const log = std.log.scoped(.model_instance);

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

pub const AnimatorType = enum {
    none,
    live_animator,
    baked_animator,
};

// const NullAnimator = struct {
    // pub fn init(allocator: Allocator) !*NullAnimator {
        // const null_animator = try allocator.create(NullAnimator);
        // null_animator.* = NullAnimator{};
        // return null_animator;
    // }
// };

const AnimatorImpl = union(enum) {
    //none: *NullAnimator,
    null_animator,
    live_animator: *Animator,
    baked_animator: *BakedAnimator,
};

pub const ModelConfig = struct {
    name: []const u8,
    file_path: []const u8,
    animator_type: AnimatorType = .none,
    // addTextures: []const TexConfigs,
};

pub const ModelInstance = struct {
    // alloc: Allocator,
    name: []const u8,
    animator_impl: AnimatorImpl,
    gltf_asset: *GltfAsset,

    const Self = @This();

    pub fn init(
        alloc: Allocator,
        name: []const u8,
        animator: AnimatorImpl,
        gltf_asset: *GltfAsset,
    ) !*Self {
        const model = try alloc.create(ModelInstance);
        model.* = ModelInstance{
            .name = try alloc.dupe(u8, name),
            .animator_impl = animator,
            .gltf_asset = gltf_asset,
        };

        return model;
    }

    pub fn initWithConfig(context: Context, config: ModelConfig) !*Self {
        var gltf_asset = try GltfAsset.init(context, config.name, config.file_path);
        try gltf_asset.load();

        const animator = try Animator.init(context, gltf_asset);

        const animator_impl: AnimatorImpl = switch (config.animator_type) {
            //.none => .{ .none = try NullAnimator.init(context.alloc)},
            .none => .null_animator,
            .live_animator => .{ .live_animator = animator },
            .baked_animator => .{ .baked_animator = try BakedAnimator.init(context, animator, .{ .frame_rate = 30.0, .capture = .all })},
        };

        const model = try context.alloc.create(ModelInstance);
        model.* = ModelInstance{
            .name = try context.alloc.dupe(u8, config.name),
            .animator_impl = animator_impl,
            .gltf_asset = gltf_asset,
        };

        return model;
    }

    pub fn deleteGlObjects(self: *Self) void {
        for (self.gltf_asset.meshes) |mesh| {
            mesh.deleteGlObjects();
        }
        self.gltf_asset.deleteGlObjects();
    }

    pub fn updateAnimation(self: *Self, delta_time: f32) !void {
        switch (self.animator_impl) {
            .live_animator => |obj| try obj.updateAnimation(delta_time),
            .baked_animator => |obj| try obj.updateAnimation(delta_time),
            else => {},
        }
    }

    pub fn playClip(self: *Self, clip: AnimationClip) !void {
        switch (self.animator_impl) {
            .live_animator => |obj| try obj.playClip(clip),
            .baked_animator => |obj| obj.playClip(clip),
            else => {},
        }
    }

    pub fn playAnimationById(self: *Self, anim_id: u32) !void {
        switch (self.animator_impl) {
            .live_animator => |obj| try obj.playAnimationById(anim_id),
            .baked_animator => |obj| obj.playAnimationById(anim_id),
            else => {},
        }
    }

    pub fn playAllAnimations(self: *Self) !void {
        switch (self.animator_impl) {
            .live_animator => |obj| try obj.playAllAnimations(),
            else => {},
        }
    }

    pub fn getAnimationCount(self: *Self) u32 {
        switch (self.animator_impl) {
            .live_animator => |obj| return obj.getAnimationCount(),
            .baked_animator => |obj| return obj.getAnimationCount(),
            else => return 0,
        }
    }

    pub fn draw(self: *Self, shader: *Shader, instance_count: u32) void {
        switch (self.animator_impl) {
            .live_animator => |obj| obj.draw(self, shader, instance_count),
            .baked_animator => |obj| obj.draw(self, shader, instance_count),
            else => {
                shader.setBool("hasSkin", false);
                shader.setMat4(constants.Uniforms.Node_Transform, &math.Mat4.Identity);
                for (self.gltf_asset.meshes, 0..) |mesh, index| {
                    shader.setInt("meshID", @intCast(index));
                    mesh.draw(self.gltf_asset, shader, instance_count);
                }
            },
        }
    }
};
