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

const MeshAnimationData = struct {
    node_index: usize,
    node_transform: Mat4,
};

const FrameData = struct {
    frame_time: f32,
    mesh_data: []MeshAnimationData,
    joint_data: []Mat4,
};

pub const BakedHeader = struct {
    frame_rate: f32,
    frame_delta: f32,
    duration: f32,
    num_frames: u32,
    num_meshes: u32,
    num_joints: u32,
};

pub const BakedAnimator = struct {
    start_time: f32,
    delta_time: f32,
    current_time: f32,
    header: BakedHeader,
    gl_texture_id: c_uint = 0,

    const Self = @This();

    pub fn init(allocator: Allocator, baked_header: BakedHeader) !*BakedAnimator {
        const bakedAnimator = try allocator.create(BakedAnimator);
        bakedAnimator.* = BakedAnimator{
            .start_time = 0,
            .delta_time = 0,
            .current_time = 0,
            .header = baked_header,
        };
        return bakedAnimator;
    }

    pub fn playClip(self: *Self, clip: AnimationClip) void {
        _ = self;
        _ = clip;
    }

    pub fn updateAnimation(self: *Self, delta_time: f32) !void {
        self.delta_time = delta_time;
    }

    pub fn draw(self: *Self, model: *ModelInstance, shader: *Shader, instance_count: u32) void {
        shader.useShader();

        const frame_index = self.getFrame(self.delta_time);
        shader.setInt("frameID", @intCast(frame_index));
        shader.setInt("numMeshes", @intCast(self.header.num_meshes));
        shader.setInt("numJoints", @intCast(self.header.num_joints));

        shader.bindTextureBufferAuto("animationData", self.gl_texture_id);

        for (0..self.header.num_meshes) |index| {
            shader.setInt("meshID", @intCast(index));
            const mesh = model.meshes[index];
            mesh.draw(model.gltf_asset, shader, instance_count);
        }
    }

    fn getFrame(self: *Self, delta_time: f32) u32 {
        var frame_index: u32 = @intFromFloat(@round(self.current_time / self.header.frame_delta));
        self.current_time += delta_time;
        if (frame_index > self.header.num_frames - 1) {
            self.current_time = 0;
            frame_index = 0;
        }
        // log.debug("frame: {d} current time: {d}", .{frame_index, self.current_time});
        return frame_index;
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
                .frame_rate = frame_rate,
                .frame_delta = frame_delta,
                .duration = state_duration,
                .num_frames = num_frames,
                .num_meshes = @intCast(animator.gltf_asset.gltf.meshes.?.len),
                .num_joints = @intCast(animator.gltf_asset.gltf.skins.?[0].joints.len),
            },
            .frames = try allocator.alloc(FrameData, num_frames),
        };

        log.debug("Initial bake data: {any}\n", .{self.header});

        var delta_time: f32 = 0;
        var frame_time: f32 = 0;
        var frames: u32 = 0;

        log.debug("Frame rate; {d}  frame_delta: {d}\n", .{ frame_rate, self.header.frame_delta });
        log.debug("Number joints: {d}\n", .{self.header.num_joints});

        const completions = animation_state.repeat_completions;

        for (0..self.header.num_frames) |frame_index| {
            log.debug("Frame number: {d}  frame_time: {d}  animation_state.current_time: {d}\n", .{ frame_index, frame_time, animation_state.current_time });
            try animator.updateAnimation(delta_time);
            try self.generateFrameData(allocator, animator, frame_index, frame_time);
            frames += 1;
            delta_time = self.header.frame_delta;
            frame_time += self.header.frame_delta;
        } else {
            log.debug("Animation completed, stopping bake\n", .{});
        }

        // Assert frame count is correct. One more update should bump completions
        try animator.updateAnimation(delta_time);
        std.debug.assert(animation_state.repeat_completions > completions); // Animation frame count is incorrect;

        return self;
    }

    fn generateFrameData(self: *BakedAnimation, allocator: Allocator, animator: *Animator, frame_index: usize, frame_time: f32) !void {
        var mesh_animation_data = try allocator.alloc(MeshAnimationData, self.header.num_meshes);
        const joint_data = try allocator.alloc(Mat4, self.header.num_joints);

        const num_joints = animator.gltf_asset.gltf.skins.?[0].joints.len;

        for (animator.gltf_asset.gltf.nodes.?, 0..) |node, node_index| {
            const animator_node = animator.nodes[node_index];
            if (node.mesh) |mesh| {
                mesh_animation_data[mesh] = MeshAnimationData{
                    .node_index = node_index,
                    .node_transform = animator_node.calculated_transform.?.toMatrix(),
                };
            }
        }

        std.mem.copyForwards(Mat4, joint_data, animator.joint_matrices[0..num_joints]);

        self.frames[frame_index] = FrameData{
            .frame_time = frame_time,
            .mesh_data = mesh_animation_data,
            .joint_data = joint_data,
        };
    }

    pub fn getBakedData(self: *Self, allocator: Allocator) ![]Mat4 {
        const data_size = self.header.num_frames * (self.header.num_meshes + self.header.num_joints);
        const data = try allocator.alloc(Mat4, data_size);
        var index: usize = 0;
        for (self.frames) |frame| {
            for (frame.mesh_data) |mesh_data| {
                data[index] = mesh_data.node_transform;
                index += 1;
            }
            for (frame.joint_data) |joint_matrix| {
                data[index] = joint_matrix;
                index += 1;
            }
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
