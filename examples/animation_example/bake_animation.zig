const std = @import("std");
const glfw = @import("zglfw");
const zopengl = @import("zopengl");
const zstbi = @import("zstbi");
const core = @import("core");
const math = @import("math");
const containers = @import("containers");

const gl = zopengl.bindings;

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

const Context = core.Context;
const Model = core.Model;
const GltfAsset = core.asset_loader.GltfAsset;
const TextureConfig = core.texture.TextureConfig;
const animation = core.animation;
const Camera = core.Camera;
const Shader = core.Shader;
// const String = core.string.String;
const FrameCounter = core.FrameCounter;
const Input = core.Input;
const constants = core.constants;

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

const print = std.debug.print;

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
    current_time: f32,
    model: *Model,
    baked_animation: *BakedAnimation,
    gl_texture_id: c_uint = 0,

    const Self = @This();

    pub fn init(model: *Model, baked_animation: *BakedAnimation) BakedAnimator {
        return BakedAnimator{
            .start_time = 0,
            .current_time = 0,
            .model = model,
            .baked_animation = baked_animation,
        };
    }

    pub fn getFrame(self: *Self, delta_time: f32) u32 {
        var frame_index: u32 = @intFromFloat(@round(self.current_time / self.baked_animation.header.frame_delta));
        self.current_time += delta_time;
        if (frame_index > self.baked_animation.header.num_frames - 1) {
            self.current_time = 0;
            frame_index = 0;
        }
        print("frame: {d} current time: {d}\n", .{frame_index, self.current_time});
        return frame_index;
    }

    pub fn draw(self: *Self, shader: *Shader, instance_count: u32, delta_time: f32) void {
        shader.useShader();
        const frame_index = self.getFrame(delta_time);
        const frame = &self.baked_animation.frames[frame_index];
        // print("frame: {d}  frame_time: {d}  current time: {d}\n", .{frame_index, frame.frame_time, self.current_time});

        if (self.model.animator.skin_index != null) {
            shader.setMat4Array(constants.Uniforms.Joint_Matrices, frame.joint_data);
        }

        for (0..self.baked_animation.header.num_meshes) |mesh_index| {
            const mesh_data = &frame.mesh_data[mesh_index];
            shader.setMat4(constants.Uniforms.Node_Transform, &mesh_data.node_transform);
            const mesh = self.model.meshes.list.items[mesh_index];
            mesh.draw(self.model.gltf_asset, shader, instance_count);
        }
    }

    pub fn getTextureData(self: *Self, alloc: Allocator) ![]Mat4 {
        const data_size = self.baked_animation.header.num_frames * (self.baked_animation.header.num_meshes + self.baked_animation.header.num_joints);
        const data = try alloc.alloc(Mat4, data_size);
        var index: usize = 0;
        for (self.baked_animation.frames) |frame| {
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

    pub fn drawData(self: *Self, shader: *Shader, instance_count: u32, delta_time: f32, data: []Mat4) void {
        shader.useShader();
        const frame_index = self.getFrame(delta_time);
        const frame_size = self.baked_animation.header.num_meshes + self.baked_animation.header.num_joints;
        const num_meshes = self.baked_animation.header.num_meshes;
        const joint_start = frame_index * frame_size + num_meshes;
        const joint_end = frame_index * frame_size + frame_size;

        if (self.model.animator.skin_index != null) {
            shader.setMat4Array(constants.Uniforms.Joint_Matrices, data[joint_start..joint_end]);
        }

        for (0..num_meshes) |index| {
            const mesh_data = &data[frame_index * frame_size + index];
            shader.setMat4(constants.Uniforms.Node_Transform, mesh_data);
            const mesh = self.model.meshes.list.items[index];
            mesh.draw(self.model.gltf_asset, shader, instance_count);
        }
    }

    pub fn drawWithTexture(self: *Self, shader: *Shader, instance_count: u32, delta_time: f32) void {
        shader.useShader();

        const frame_index = self.getFrame(delta_time);
        const num_meshes = self.baked_animation.header.num_meshes;

        shader.setInt("frameID", @intCast(frame_index));
        shader.setInt("numMeshes", @intCast(self.baked_animation.header.num_meshes));
        shader.setInt("numJoints", @intCast(self.baked_animation.header.num_joints));
        shader.bindTexture1DAuto("animationData", self.gl_texture_id);

        for (0..num_meshes) |index| {
            shader.setInt("meshID", @intCast(index));
            const mesh = self.model.meshes.list.items[index];
            mesh.draw(self.model.gltf_asset, shader, instance_count);
        }
    }

    pub fn createTexture(self: *Self, data: []Mat4) c_uint {
        _ = self;

        var gl_texture_id: gl.Uint = undefined;
        gl.genTextures(1, &gl_texture_id);
        gl.bindTexture(gl.TEXTURE_1D, gl_texture_id);

        gl.texImage1D(
            gl.TEXTURE_1D,
            0,
            gl.RGBA32F,
            @intCast(data.len * 4),
            @intCast(0),
            gl.RGBA,
            gl.FLOAT,
            data.ptr,
        );

        gl.texParameteri(gl.TEXTURE_1D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
        gl.texParameteri(gl.TEXTURE_1D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
        gl.texParameteri(gl.TEXTURE_1D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);

        gl.bindTexture(gl.TEXTURE_1D, 0);

        core.gl_debug.check("glTexImage1D");
        return gl_texture_id;
    }
};

pub const BakedAnimation = struct {
    header: BakedHeader,
    frames: []FrameData,

    const Self = @This();

    pub fn bakeAnimation(context: Context, animator: *Animator, frame_rate: f32) !*Self {

        const animation_state = &animator.active_animations.list.items[0];

        const state_duration = animation_state.end_time - animation_state.start_time;
        const frame_delta = 1.0 / frame_rate;
        const num_frames: u32 = @as(u32, @ceil(state_duration/frame_delta)) + 1;

        const self = try context.alloc.create(BakedAnimation);
        self.* = .{
            .header = .{
                .frame_rate = frame_rate,
                .frame_delta = frame_delta,
                .duration = state_duration,
                .num_frames = num_frames,
                .num_meshes = @intCast(animator.gltf_asset.gltf.meshes.?.len),
                .num_joints = @intCast(animator.gltf_asset.gltf.skins.?[0].joints.len),
            },
            .frames = try context.alloc.alloc(FrameData, num_frames),
        };

        std.debug.print("Initial bake data: {any}\n", .{self.header});

        var delta_time: f32 = 0;
        var frame_time: f32 = 0;
        var frames: u32 = 0;

        std.debug.print("Frame rate; {d}  frame_delta: {d}\n", .{frame_rate, self.header.frame_delta});
        std.debug.print("Number joints: {d}\n", .{self.header.num_joints});

        const completions = animation_state.repeat_completions;

        // while (completions == animation_state.repeat_completions) {
        for (0..self.header.num_frames) |frame_index| {
            std.debug.print("Frame number: {d}  frame_time: {d}  animation_state.current_time: {d}\n", .{frame_index, frame_time, animation_state.current_time});
            try animator.updateAnimation(delta_time);
            try self.generateFrameData(context, animator, frame_index, frame_time);
            frames += 1;
            delta_time = self.header.frame_delta;
            frame_time += self.header.frame_delta;
        } else {
            std.debug.print("Animation completed, stopping bake\n", .{});
       }

        // Assert frame count is correct. One more update should bump completions
        try animator.updateAnimation(delta_time);
        std.debug.assert(animation_state.repeat_completions > completions); // Animation frame count is incorrect;

        // self.header.num_frames = frames;
        return self;
    }

    pub fn generateFrameData(self: *BakedAnimation, context: Context, animator: *Animator, frame_index: usize, frame_time: f32) !void {

        var mesh_animation_data = try context.alloc.alloc(MeshAnimationData, self.header.num_meshes);
        const joint_data = try context.alloc.alloc(Mat4, self.header.num_joints);

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

        // var buf0: [256]u8 = undefined;
        // for (mesh_animation_data, 0..) |data, mesh_id| {
            // const animator_node = animator.nodes[data.node_index];
            // std.debug.print("Node: {d:2}  name: {s}  mesh: {d}  NodeTransform: {s}\n", .{data.node_index, animator_node.name.?, mesh_id, data.node_transform.asString(&buf0)});
        // }

        // for (0..num_joints) |joint_index| {
            // const joint_matrix = animator.joint_matrices[joint_index];
            // std.debug.print("Joint: {d:2}  matrix: {s}\n", .{joint_index, joint_matrix.asString(&buf0)});
            // joint_data[joint_index] = joint_matrix;
        // }

        std.mem.copyForwards(Mat4, joint_data, animator.joint_matrices[0..num_joints]);

        self.frames[frame_index] = FrameData{
            .frame_time = frame_time,
            .mesh_data = mesh_animation_data,
            .joint_data = joint_data,
        };
    }

    pub fn printData(self: *BakedAnimation) void {
        print("BakedAnimation header: \n", .{});
        print("   frame_rate: {d}\n", .{self.header.frame_rate});
        print("   frame_delta: {d}\n", .{self.header.frame_delta});
        print("   clip_duration: {d}\n", .{self.header.duration});
        print("   num_frames: {d}\n", .{self.header.num_frames});
        print("   num_meshes: {d}\n", .{self.header.num_meshes});
        print("   num_joints: {d}\n", .{self.header.num_joints});
        // var buf: [256]u8 = undefined;
        // for (self.frames, 0..) |frame, frame_index| {
        //     print("      Frame {d}: frame_time: {d}\n", .{frame_index, frame.frame_time});
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