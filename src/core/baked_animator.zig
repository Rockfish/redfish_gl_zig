const std = @import("std");
const math = @import("math");
const log = std.log.scoped(.baked_animator);

const zopengl = @import("zopengl");
const gl = zopengl.bindings;

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

const ModelInstance = @import("model_instance.zig").ModelInstance;
const Context = @import("context.zig").Context;
const Model = @import("model.zig").Model;
const GltfAsset = @import("asset_loader.zig").GltfAsset;

const animation = @import("animator.zig");
const Shader = @import("shader.zig").Shader;
const TextureBuffer = @import("texture_buffer.zig").TextureBuffer;

const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const vec2 = math.vec2;
const vec3 = math.vec3;
const Mat4 = math.Mat4;
const Quat = math.Quat;

const Animator = animation.Animator;
const AnimationClip = animation.AnimationClip;
const AnimationRepeat = animation.AnimationRepeatMode;

const print = log.debug;

const FrameData = struct {
    data: []Mat4,
};

pub const BakedHeader = struct {
    frame_delta: f32,
    duration: f32,
    num_frames: u32,
    num_meshes: u32,
    num_joints: u32,
    animation_offset: u32,
};

pub const BakedAnimationConfig = struct {
    frame_rate: f32 = 30.0,
    capture: union(enum) {
        all,
        indexes: []const u32,
        clips: []const AnimationClip,
    },
};

pub const BakedAnimator = struct {
    anim_id: usize,
    start_time: f32,
    delta_time: f32,
    current_time: f32,
    headers: []BakedHeader,
    gl_texture_id: c_uint = 0,

    const Self = @This();

    pub fn init(context: Context, animator: *Animator, config: BakedAnimationConfig) !*BakedAnimator {
        log.debug("config: {any}", .{config});

        const baked_data = try BakedData.captureAnimationsData(context.temp_alloc, animator, config);
        const baked_texture = TextureBuffer.createTextureBuffer(math.Mat4, baked_data.data);

        const headers = try context.alloc.alloc(BakedHeader, baked_data.headers.len);
        std.mem.copyForwards(BakedHeader, headers, baked_data.headers);

        const bakedAnimator = try context.alloc.create(BakedAnimator);
        bakedAnimator.* = BakedAnimator{
            .anim_id = 0,
            .start_time = 0,
            .delta_time = 0,
            .current_time = 0,
            .headers = headers,
            .gl_texture_id = baked_texture.gl_texture_id,
        };
        return bakedAnimator;
    }

    pub fn playClip(self: *Self, clip: AnimationClip) void {
        self.anim_id = clip.animation_index;
        self.current_time = clip.start_time;
    }

    pub fn playAnimationById(self: *Self, anim_id: u32) void {
        self.anim_id = @intCast(anim_id);
        self.current_time = 0;
    }

    pub fn updateAnimation(self: *Self, delta_time: f32) !void {
        self.delta_time = delta_time;
    }

    pub fn draw(self: *Self, model: *ModelInstance, shader: *Shader, instance_count: u32) void {
        shader.useShader();

        const frame_index = self.getFrame(self.delta_time);
        shader.setInt("frameId", @intCast(frame_index));

        shader.setInt("numMeshes", @intCast(self.headers[self.anim_id].num_meshes));
        shader.setInt("numJoints", @intCast(self.headers[self.anim_id].num_joints));
        shader.setInt("animationOffset", @intCast(self.headers[self.anim_id].animation_offset));

        shader.bindTextureBufferAuto("animationData", self.gl_texture_id);

        for (0..self.headers[self.anim_id].num_meshes) |index| {
            shader.setInt("meshId", @intCast(index));
            const mesh = model.gltf_asset.meshes[index];
            mesh.draw(model.gltf_asset, shader, instance_count);
        }
    }

    fn getFrame(self: *Self, delta_time: f32) u32 {
        var frame_index: u32 = @intFromFloat(@round(self.current_time / self.headers[self.anim_id].frame_delta));
        self.current_time += delta_time;
        if (frame_index > self.headers[self.anim_id].num_frames - 1) {
            self.current_time = 0;
            frame_index = 0;
        }
        return frame_index;
    }
};

const BakedData = struct {
    headers: []BakedHeader,
    data: []Mat4,

    pub fn captureAnimationsData(allocator: Allocator, animator: *Animator, config: BakedAnimationConfig) !*BakedData {
        var baked_animations: []*BakedAnimation = undefined;

        switch (config.capture) {
            .all => {
                const num_animations = animator.animations.len;
                baked_animations = try allocator.alloc(*BakedAnimation, num_animations);

                for (0..num_animations) |i| {
                    try animator.playAnimationById(@intCast(i));
                    baked_animations[i] = try BakedAnimation.bakeAnimation(allocator, animator, config.frame_rate);
                }
            },
            .indexes => |indexes| {
                const num_animations = indexes.len;
                baked_animations = try allocator.alloc(*BakedAnimation, num_animations);

                for (indexes, 0..) |index, i| {
                    try animator.playAnimationById(index);
                    baked_animations[i] = try BakedAnimation.bakeAnimation(allocator, animator, config.frame_rate);
                }
            },
            .clips => |clips| {
                const num_animations = clips.len;
                baked_animations = try allocator.alloc(*BakedAnimation, num_animations);

                for (0..num_animations) |i| {
                    try animator.playClip(clips[i]);
                    baked_animations[i] = try BakedAnimation.bakeAnimation(allocator, animator, config.frame_rate);
                }
            },
        }

        const baked_data = try allocator.create(BakedData);
        baked_data.*.headers = try allocator.alloc(BakedHeader, baked_animations.len);

        for (0..baked_animations.len) |i| {
            baked_data.*.headers[i] = baked_animations[i].header;
        }

        var data_size: u32 = 0;
        for (baked_animations) |baked_anim| {
            data_size += baked_anim.header.num_frames * (baked_anim.header.num_meshes + baked_anim.header.num_joints);
        }

        baked_data.*.data = try allocator.alloc(Mat4, data_size);

        var offset: usize = 0;
        for (baked_animations, 0..) |baked_anim, i| {
            baked_data.headers[i].animation_offset = @intCast(offset);
            const baked_anim_data = try baked_anim.getBakedData(allocator);
            log.debug("animation: {d}  header: {any}  data.len: {d}", .{ i, baked_anim.header, baked_anim_data.len });
            std.mem.copyForwards(Mat4, baked_data.data[offset .. offset + baked_anim_data.len], baked_anim_data);
            offset += baked_anim_data.len;
        }

        return baked_data;
    }
};

pub const BakedAnimation = struct {
    header: BakedHeader,
    frames: []FrameData,

    const Self = @This();

    pub fn bakeAnimation(allocator: Allocator, animator: *Animator, frame_rate: f32) !*Self {
        const animation_state = &animator.active_animations.list.items[0];

        const state_duration = animation_state.end_time - animation_state.start_time;
        const frame_delta = 1.0 / frame_rate;
        const num_frames: u32 = @as(u32, @ceil(state_duration / frame_delta)) + 1;

        const self = try allocator.create(BakedAnimation);
        self.* = .{
            .header = .{
                .frame_delta = frame_delta,
                .duration = state_duration,
                .num_frames = num_frames,
                .num_meshes = @intCast(animator.gltf_asset.gltf.meshes.?.len),
                .num_joints = @intCast(animator.gltf_asset.gltf.skins.?[0].joints.len),
                .animation_offset = 0,
            },
            .frames = try allocator.alloc(FrameData, num_frames),
        };

        log.debug("Initial bake data: {any}", .{self.header});

        var delta_time: f32 = 0;
        var frame_time: f32 = 0;

        log.debug("Frame rate; {d}  frame_delta: {d}", .{ frame_rate, frame_delta });
        log.debug("Number joints: {d}", .{self.header.num_joints});

        const completions = animation_state.num_completions;

        for (0..self.header.num_frames) |frame_index| {
            // Advance animator to create the frame data
            try animator.updateAnimation(delta_time);
            try self.saveFrameData(allocator, animator, frame_index);
            log.debug("Frame number: {d}  frame_time: {d}  animation_state.current_time: {d}", .{ frame_index, frame_time, animation_state.current_time });
            delta_time = frame_delta;
            frame_time += frame_delta;
        } else {
            log.debug("Animation completed, stopping bake", .{});
        }

        // Assert frame count is correct. One more update should bump completions
        try animator.updateAnimation(delta_time);
        std.debug.assert(animation_state.num_completions > completions);

        return self;
    }

    fn saveFrameData(self: *BakedAnimation, allocator: Allocator, animator: *Animator, frame_index: usize) !void {
        const data = try allocator.alloc(Mat4, self.header.num_meshes + self.header.num_joints);

        const num_joints = animator.gltf_asset.gltf.skins.?[0].joints.len;

        for (animator.gltf_asset.gltf.nodes.?, 0..) |node, node_index| {
            const animator_node = animator.nodes[node_index];
            if (node.mesh) |mesh| {
                data[mesh] = animator_node.calculated_transform.?.toMatrix();
            }
        }

        std.mem.copyForwards(Mat4, data[self.header.num_meshes..], animator.joint_matrices[0..num_joints]);

        self.frames[frame_index] = FrameData{
            .data = data,
        };
    }

    pub fn getBakedData(self: *Self, allocator: Allocator) ![]Mat4 {
        const data_size = self.header.num_frames * (self.header.num_meshes + self.header.num_joints);
        const data = try allocator.alloc(Mat4, data_size);
        var index: usize = 0;
        for (self.frames) |frame| {
            std.mem.copyForwards(Mat4, data[index..], frame.data);
            index += frame.data.len;
        }
        return data;
    }

    pub fn printData(self: *BakedAnimation) void {
        log.info("BakedAnimation header: \n", .{});
        log.info("   frame_rate: {d}\n", .{self.header.frame_rate});
        log.info("   frame_delta: {d}\n", .{self.header.frame_delta});
        log.info("   clip_duration: {d}\n", .{self.header.duration});
        log.info("   num_frames: {d}\n", .{self.header.num_frames});
        log.info("   num_meshes: {d}\n", .{self.header.num_meshes});
        log.info("   num_joints: {d}\n", .{self.header.num_joints});
        // var buf: [256]u8 = undefined;
        // for (self.frames, 0..) |frame, frame_index| {
        //     log.info("      Frame {d}: frame_time: {d}\n", .{frame_index, frame.frame_time});
        //     for (frame.mesh_data, 0..) |mesh_data, mesh_index| {
        //         // print("      Mesh {d}: node_index: {d}  node_transform: {s}\n", .{mesh_index, mesh_data.node_index, mesh_data.node_transform.asString(&buf)});
        //         print("      Mesh: {d:2}: node_transform: {s}\n", .{mesh_index, mesh_data.node_transform.asString(&buf)});
        //     }
        //     for (0..self.header.num_joints) |joint_index| {
        //         print("      Joint: {d:2}  matrix: {s}\n", .{joint_index, frame.joint_data[joint_index].asString(&buf)});
        //     }
        // }
    }
};
