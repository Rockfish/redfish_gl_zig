const std = @import("std");
const math = @import("math");
const gltf_types = @import("gltf/gltf.zig");
const GltfAsset = @import("asset_loader.zig").GltfAsset;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;

const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const vec2 = math.vec2;
const vec3 = math.vec3;
const vec4 = math.vec4;
const Mat4 = math.Mat4;
const Quat = math.Quat;
const quat = math.quat;

pub const MAX_BONES: usize = 100;
pub const MAX_NODES: usize = 100;

pub const AnimationRepeatMode = enum {
    Once,
    Count,
    Forever,
};

/// Animation clip that references a glTF animation by index
/// Maintains the same interface as the previous ASSIMP-based system
pub const AnimationClip = struct {
    animation_index: u32,
    start_time: f32 = 0.0,
    end_time: f32,
    repeat_mode: AnimationRepeatMode,

    pub fn init(animation_index: u32, end_time: f32, repeat_mode: AnimationRepeatMode) AnimationClip {
        return .{
            .animation_index = animation_index,
            .end_time = end_time,
            .repeat_mode = repeat_mode,
        };
    }
};

/// glTF-specific animation state that tracks time in seconds
pub const GltfAnimationState = struct {
    animation_index: u32,
    current_time: f32,
    start_time: f32,
    end_time: f32,
    repeat_mode: AnimationRepeatMode,
    repeat_completions: u32,

    pub fn init(animation_index: u32, start_time: f32, end_time: f32, repeat_mode: AnimationRepeatMode) GltfAnimationState {
        return .{
            .animation_index = animation_index,
            .current_time = start_time,
            .start_time = start_time,
            .end_time = end_time,
            .repeat_mode = repeat_mode,
            .repeat_completions = 0,
        };
    }

    pub fn update(self: *GltfAnimationState, delta_time: f32) void {
        self.current_time += delta_time;

        if (self.current_time > self.end_time) {
            switch (self.repeat_mode) {
                .Once => {
                    self.current_time = self.end_time;
                },
                .Count => {
                    // TODO: implement count-based repeating
                    self.current_time = self.start_time;
                    self.repeat_completions += 1;
                },
                .Forever => {
                    // Loop back to start
                    const duration = self.end_time - self.start_time;
                    self.current_time = self.start_time + @mod(self.current_time - self.start_time, duration);
                },
            }
        }
    }
};

/// Joint information from glTF skin
pub const Joint = struct {
    node_index: u32,
    inverse_bind_matrix: Mat4,
};

/// Interpolated animation values for a single node
pub const NodeAnimation = struct {
    translation: Vec3,
    rotation: Quat,
    scale: Vec3,

    pub fn init() NodeAnimation {
        return .{
            .translation = vec3(0.0, 0.0, 0.0),
            .rotation = quat(0.0, 0.0, 0.0, 1.0),
            .scale = vec3(1.0, 1.0, 1.0),
        };
    }

    pub fn toMatrix(self: NodeAnimation) Mat4 {
        const translation_matrix = Mat4.createTranslation(self.translation.x, self.translation.y, self.translation.z);
        const rotation_matrix = self.rotation.toMat4();
        const scale_matrix = Mat4.createScale(self.scale.x, self.scale.y, self.scale.z);
        
        return translation_matrix.mulMat4(&rotation_matrix.mulMat4(&scale_matrix));
    }
};

/// Keyframe interpolation utilities
pub const AnimationInterpolation = struct {
    /// Linear interpolation for Vec3
    pub fn lerpVec3(a: Vec3, b: Vec3, t: f32) Vec3 {
        return vec3(
            a.x + (b.x - a.x) * t,
            a.y + (b.y - a.y) * t,
            a.z + (b.z - a.z) * t,
        );
    }

    /// Spherical linear interpolation for quaternions
    pub fn slerpQuat(a: Quat, b: Quat, t: f32) Quat {
        return a.slerp(b, t);
    }

    /// Find interpolation factor and surrounding keyframe indices
    pub fn findKeyframeIndices(times: []const f32, current_time: f32) struct { usize, usize, f32 } {
        if (times.len == 0) return .{ 0, 0, 0.0 };
        if (times.len == 1) return .{ 0, 0, 0.0 };

        // Find the keyframes that surround the current time
        for (0..times.len - 1) |i| {
            if (current_time >= times[i] and current_time <= times[i + 1]) {
                const duration = times[i + 1] - times[i];
                const factor = if (duration > 0.0) (current_time - times[i]) / duration else 0.0;
                return .{ i, i + 1, factor };
            }
        }

        // If we're past the end, use the last keyframe
        if (current_time >= times[times.len - 1]) {
            return .{ times.len - 1, times.len - 1, 0.0 };
        }

        // If we're before the start, use the first keyframe
        return .{ 0, 0, 0.0 };
    }
};

pub const Animator = struct {
    allocator: Allocator,
    
    // glTF animation data references
    gltf_asset: *const GltfAsset,
    skin_index: ?u32,
    joints: []Joint,
    
    // Animation state
    current_animation: ?GltfAnimationState,
    
    // Node transform cache (indexed by node index)
    node_transforms: []NodeAnimation,
    node_matrices: []Mat4,
    
    // Final matrices for rendering
    final_bone_matrices: [MAX_BONES]Mat4,
    final_node_matrices: [MAX_NODES]Mat4,

    const Self = @This();

    pub fn init(allocator: Allocator, gltf_asset: *const GltfAsset, skin_index: ?u32) !*Self {
        const animator = try allocator.create(Animator);
        
        // Initialize joint data from skin
        var joints = ArrayList(Joint).init(allocator);
        if (skin_index) |skin_idx| {
            if (gltf_asset.gltf.skins) |skins| {
                const skin = skins[skin_idx];
                
                // Get inverse bind matrices
                var inverse_bind_matrices: []Mat4 = &[_]Mat4{};
                if (skin.inverse_bind_matrices) |_| {
                    // TODO: Extract matrices from accessor data
                    // For now, use identity matrices
                    inverse_bind_matrices = try allocator.alloc(Mat4, skin.joints.len);
                    for (0..skin.joints.len) |i| {
                        inverse_bind_matrices[i] = Mat4.identity();
                    }
                }
                
                // Create joint array
                for (0..skin.joints.len) |i| {
                    const joint = Joint{
                        .node_index = skin.joints[i],
                        .inverse_bind_matrix = if (inverse_bind_matrices.len > i) inverse_bind_matrices[i] else Mat4.identity(),
                    };
                    try joints.append(joint);
                }
            }
        }
        
        const node_count = if (gltf_asset.gltf.nodes) |nodes| nodes.len else 0;
        
        animator.* = Animator{
            .allocator = allocator,
            .gltf_asset = gltf_asset,
            .skin_index = skin_index,
            .joints = try joints.toOwnedSlice(),
            .current_animation = null,
            .node_transforms = try allocator.alloc(NodeAnimation, node_count),
            .node_matrices = try allocator.alloc(Mat4, node_count),
            .final_bone_matrices = [_]Mat4{Mat4.identity()} ** MAX_BONES,
            .final_node_matrices = [_]Mat4{Mat4.identity()} ** MAX_NODES,
        };
        
        // Initialize node transforms to identity
        for (0..animator.node_transforms.len) |i| {
            animator.node_transforms[i] = NodeAnimation.init();
            animator.node_matrices[i] = Mat4.identity();
        }
        
        return animator;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.joints);
        self.allocator.free(self.node_transforms);
        self.allocator.free(self.node_matrices);
        self.allocator.destroy(self);
    }

    /// Play an animation clip - maintains the same interface as ASSIMP version
    pub fn playClip(self: *Self, clip: AnimationClip) !void {
        if (self.gltf_asset.gltf.animations == null or clip.animation_index >= self.gltf_asset.gltf.animations.?.len) {
            std.debug.print("Invalid animation index: {d}\n", .{clip.animation_index});
            return;
        }
        
        self.current_animation = GltfAnimationState.init(
            clip.animation_index,
            clip.start_time,
            clip.end_time,
            clip.repeat_mode
        );
        
        std.debug.print("Playing glTF animation {d}\n", .{clip.animation_index});
    }

    /// Play animation by index - convenience method
    pub fn playAnimationById(self: *Self, animation_index: u32) !void {
        if (self.gltf_asset.gltf.animations == null or animation_index >= self.gltf_asset.gltf.animations.?.len) {
            std.debug.print("Invalid animation index: {d}\n", .{animation_index});
            return;
        }
        
        // Calculate animation duration from samplers
        const animation = self.gltf_asset.gltf.animations.?[animation_index];
        var max_time: f32 = 0.0;
        
        for (animation.samplers) |_| {
            // TODO: Get actual time values from accessor
            // For now, assume 1 second duration
            max_time = @max(max_time, 1.0);
        }
        
        const clip = AnimationClip.init(animation_index, max_time, .Forever);
        try self.playClip(clip);
    }

    /// Play animation at specific time - maintains same interface
    pub fn playTick(self: *Self, time: f32) !void {
        if (self.current_animation) |*anim_state| {
            anim_state.current_time = time;
            try self.updateNodeTransformations();
            try self.updateShaderMatrices();
        }
    }

    /// Update animation with delta time - maintains same interface
    pub fn updateAnimation(self: *Self, delta_time: f32) !void {
        if (self.current_animation) |*anim_state| {
            anim_state.update(delta_time);
            try self.updateNodeTransformations();
            try self.updateShaderMatrices();
        }
    }

    // Compatibility method name
    pub fn update_animation(self: *Self, delta_time: f32) !void {
        try self.updateAnimation(delta_time);
    }

    /// Update node transformations from current animation state
    fn updateNodeTransformations(self: *Self) !void {
        if (self.current_animation == null or self.gltf_asset.gltf.animations == null) return;
        
        const anim_state = self.current_animation.?;
        const animation = self.gltf_asset.gltf.animations.?[anim_state.animation_index];
        
        // Reset all node transforms to their default values
        if (self.gltf_asset.gltf.nodes) |nodes| {
            for (0..nodes.len) |i| {
                const node = nodes[i];
                self.node_transforms[i] = NodeAnimation{
                    .translation = node.translation orelse vec3(0.0, 0.0, 0.0),
                    .rotation = node.rotation orelse quat(0.0, 0.0, 0.0, 1.0),
                    .scale = node.scale orelse vec3(1.0, 1.0, 1.0),
                };
            }
        }
        
        // Apply animation channels
        for (animation.channels) |channel| {
            if (channel.target.node) |node_index| {
                if (node_index < self.node_transforms.len) {
                    try self.evaluateAnimationChannel(channel, animation.samplers[channel.sampler], anim_state.current_time, node_index);
                }
            }
        }
        
        // Calculate node matrices
        try self.calculateNodeMatrices();
    }

    /// Evaluate a single animation channel at the given time
    fn evaluateAnimationChannel(
        self: *Self, 
        channel: gltf_types.AnimationChannel, 
        sampler: gltf_types.AnimationSampler, 
        current_time: f32, 
        node_index: usize
    ) !void {
        // Get time values from the input accessor
        const times = try self.readAccessorAsF32Slice(sampler.input);
        if (times.len == 0) return;
        
        // Find the keyframe indices and interpolation factor
        const keyframe_info = AnimationInterpolation.findKeyframeIndices(times, current_time);
        const index0 = keyframe_info[0];
        const index1 = keyframe_info[1];
        const factor = keyframe_info[2];
        
        // Apply the animation based on the target property
        switch (channel.target.path) {
            .translation => {
                const values = try self.readAccessorAsVec3Slice(sampler.output);
                if (values.len > index0) {
                    const start_value = values[index0];
                    const end_value = if (index1 < values.len) values[index1] else start_value;
                    
                    self.node_transforms[node_index].translation = switch (sampler.interpolation) {
                        .linear => AnimationInterpolation.lerpVec3(start_value, end_value, factor),
                        .step => start_value,
                        .cubic_spline => start_value, // TODO: implement cubic spline
                    };
                }
            },
            .rotation => {
                const values = try self.readAccessorAsQuatSlice(sampler.output);
                if (values.len > index0) {
                    const start_value = values[index0];
                    const end_value = if (index1 < values.len) values[index1] else start_value;
                    
                    self.node_transforms[node_index].rotation = switch (sampler.interpolation) {
                        .linear => AnimationInterpolation.slerpQuat(start_value, end_value, factor),
                        .step => start_value,
                        .cubic_spline => start_value, // TODO: implement cubic spline
                    };
                }
            },
            .scale => {
                const values = try self.readAccessorAsVec3Slice(sampler.output);
                if (values.len > index0) {
                    const start_value = values[index0];
                    const end_value = if (index1 < values.len) values[index1] else start_value;
                    
                    self.node_transforms[node_index].scale = switch (sampler.interpolation) {
                        .linear => AnimationInterpolation.lerpVec3(start_value, end_value, factor),
                        .step => start_value,
                        .cubic_spline => start_value, // TODO: implement cubic spline
                    };
                }
            },
            .weights => {
                // TODO: implement morph target weights
            },
        }
    }

    /// Read accessor data as f32 slice
    fn readAccessorAsF32Slice(self: *Self, accessor_index: u32) ![]const f32 {
        const accessor = self.gltf_asset.gltf.accessors.?[accessor_index];
        const buffer_view = self.gltf_asset.gltf.buffer_views.?[accessor.buffer_view.?];
        const buffer_data = self.gltf_asset.buffer_data.items[buffer_view.buffer];
        
        const start = accessor.byte_offset + buffer_view.byte_offset;
        const data_size = @sizeOf(f32) * accessor.count;
        const end = start + data_size;
        
        const data = buffer_data[start..end];
        return @as([*]const f32, @ptrCast(@alignCast(data)))[0..accessor.count];
    }

    /// Read accessor data as Vec3 slice
    fn readAccessorAsVec3Slice(self: *Self, accessor_index: u32) ![]const Vec3 {
        const accessor = self.gltf_asset.gltf.accessors.?[accessor_index];
        const buffer_view = self.gltf_asset.gltf.buffer_views.?[accessor.buffer_view.?];
        const buffer_data = self.gltf_asset.buffer_data.items[buffer_view.buffer];
        
        const start = accessor.byte_offset + buffer_view.byte_offset;
        const data_size = @sizeOf(Vec3) * accessor.count;
        const end = start + data_size;
        
        const data = buffer_data[start..end];
        return @as([*]const Vec3, @ptrCast(@alignCast(data)))[0..accessor.count];
    }

    /// Read accessor data as Quat slice
    fn readAccessorAsQuatSlice(self: *Self, accessor_index: u32) ![]const Quat {
        const accessor = self.gltf_asset.gltf.accessors.?[accessor_index];
        const buffer_view = self.gltf_asset.gltf.buffer_views.?[accessor.buffer_view.?];
        const buffer_data = self.gltf_asset.buffer_data.items[buffer_view.buffer];
        
        const start = accessor.byte_offset + buffer_view.byte_offset;
        const data_size = @sizeOf(Quat) * accessor.count;
        const end = start + data_size;
        
        const data = buffer_data[start..end];
        return @as([*]const Quat, @ptrCast(@alignCast(data)))[0..accessor.count];
    }

    /// Calculate world matrices for all nodes
    fn calculateNodeMatrices(self: *Self) !void {
        if (self.gltf_asset.gltf.nodes == null) return;
        
        const nodes = self.gltf_asset.gltf.nodes.?;
        
        // Calculate matrices for all nodes (assuming they're in dependency order)
        for (0..nodes.len) |i| {
            self.node_matrices[i] = self.node_transforms[i].toMatrix();
        }
        
        // Apply parent transforms
        for (0..nodes.len) |i| {
            const node = nodes[i];
            if (node.children) |children| {
                for (children) |child_index| {
                    if (child_index < self.node_matrices.len) {
                        self.node_matrices[child_index] = self.node_matrices[i].mulMat4(&self.node_matrices[child_index]);
                    }
                }
            }
        }
    }

    /// Update final matrices for shader rendering
    fn updateShaderMatrices(self: *Self) !void {
        // Update joint matrices for skinned meshes
        for (0..@min(self.joints.len, MAX_BONES)) |i| {
            const joint = self.joints[i];
            if (joint.node_index < self.node_matrices.len) {
                self.final_bone_matrices[i] = self.node_matrices[joint.node_index].mulMat4(&joint.inverse_bind_matrix);
            }
        }
        
        // Update node matrices for non-skinned meshes
        for (0..@min(self.node_matrices.len, MAX_NODES)) |i| {
            self.final_node_matrices[i] = self.node_matrices[i];
        }
    }
};