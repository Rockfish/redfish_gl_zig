const std = @import("std");
const math = @import("math");
const gltf_types = @import("gltf/gltf.zig");
const GltfAsset = @import("asset_loader.zig").GltfAsset;
const Transform = @import("transform.zig").Transform;

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
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

pub const MAX_JOINTS: usize = 100;

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

    pub fn init(animation_index: u32, start_time: f32, end_time: f32, repeat_mode: AnimationRepeatMode) AnimationClip {
        return .{
            .animation_index = animation_index,
            .start_time = start_time,
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

/// Weighted animation for blending multiple animations simultaneously
/// Compatible with ASSIMP-based game_angrybot system
pub const WeightedAnimation = struct {
    weight: f32,
    start_time: f32,    // Animation start time in seconds
    end_time: f32,      // Animation end time in seconds  
    offset: f32,        // Time offset for animation synchronization
    start_real_time: f32, // Real-world start time for non-looped animations

    pub fn init(weight: f32, start_time: f32, end_time: f32, offset: f32, start_real_time: f32) WeightedAnimation {
        return .{
            .weight = weight,
            .start_time = start_time,
            .end_time = end_time,
            .offset = offset,
            .start_real_time = start_real_time,
        };
    }
};

/// Joint information from glTF skin
pub const Joint = struct {
    node_index: u32,
    inverse_bind_matrix: Mat4,
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
        return a.slerp(&b, t);
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
    arena: *ArenaAllocator,

    // glTF animation data references
    gltf_asset: *const GltfAsset,
    skin_index: ?u32,
    joints: []Joint,

    // Animation state
    current_animation: ?GltfAnimationState,

    // Node transform cache (indexed by node index)
    node_transforms: []Transform,
    node_matrices: []Mat4,

    // Final matrices for rendering
    joint_matrices: [MAX_JOINTS]Mat4,

    const Self = @This();

    pub fn init(arena: *ArenaAllocator, gltf_asset: *const GltfAsset, skin_index: ?u32) !*Self {
        const allocator = arena.allocator();
        const animator = try allocator.create(Animator);

        // Initialize joint data from skin
        var joints = ArrayList(Joint).init(allocator);
        if (skin_index) |skin_idx| {
            if (gltf_asset.gltf.skins) |skins| {
                const skin = skins[skin_idx];

                // Get inverse bind matrices
                var inverse_bind_matrices: []Mat4 = &[_]Mat4{};
                if (skin.inverse_bind_matrices) |ibm_accessor_index| {
                    // Read actual inverse bind matrices from accessor data
                    const accessor = gltf_asset.gltf.accessors.?[ibm_accessor_index];
                    const buffer_view = gltf_asset.gltf.buffer_views.?[accessor.buffer_view.?];
                    const buffer_data = gltf_asset.buffer_data.items[buffer_view.buffer];

                    const start = accessor.byte_offset + buffer_view.byte_offset;
                    const data_size = @sizeOf(Mat4) * accessor.count;
                    const end = start + data_size;

                    const data = buffer_data[start..end];
                    const matrices_data = @as([*]const Mat4, @ptrCast(@alignCast(data)))[0..accessor.count];

                    inverse_bind_matrices = try allocator.alloc(Mat4, matrices_data.len);
                    @memcpy(inverse_bind_matrices, matrices_data);

                    std.debug.print("Loaded {d} inverse bind matrices for skin {d}\n", .{ inverse_bind_matrices.len, skin_idx });
                } else {
                    // Fallback to identity matrices if no inverse bind matrices provided
                    inverse_bind_matrices = try allocator.alloc(Mat4, skin.joints.len);
                    for (0..skin.joints.len) |i| {
                        inverse_bind_matrices[i] = Mat4.identity();
                    }
                    std.debug.print("No inverse bind matrices found for skin {d}, using identity matrices\n", .{skin_idx});
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
            .arena = arena,
            .gltf_asset = gltf_asset,
            .skin_index = skin_index,
            .joints = try joints.toOwnedSlice(),
            .current_animation = null,
            .node_transforms = try allocator.alloc(Transform, node_count),
            .node_matrices = try allocator.alloc(Mat4, node_count),
            .joint_matrices = [_]Mat4{Mat4.identity()} ** MAX_JOINTS,
        };

        // Initialize node transforms to identity
        for (0..animator.node_transforms.len) |i| {
            animator.node_transforms[i] = Transform.init();
            animator.node_matrices[i] = Mat4.identity();
        }

        return animator;
    }

    pub fn deinit(self: *Self) void {
        // All allocations are done via arena, so they'll be freed when the arena is deinitialized
        // No need to manually free individual allocations
        _ = self; // suppress unused parameter warning
    }

    /// Play an animation clip
    pub fn playClip(self: *Self, clip: AnimationClip) !void {
        if (self.gltf_asset.gltf.animations == null or clip.animation_index >= self.gltf_asset.gltf.animations.?.len) {
            std.debug.print("Invalid animation index: {d}\n", .{clip.animation_index});
            return;
        }

        self.current_animation = GltfAnimationState.init(
            clip.animation_index,
            clip.start_time,
            clip.end_time,
            clip.repeat_mode,
        );

        std.debug.print("Playing glTF animation {d}\n", .{clip.animation_index});
    }

    /// Play animation by index
    pub fn playAnimationById(self: *Self, animation_index: u32) !void {
        if (self.gltf_asset.gltf.animations == null or animation_index >= self.gltf_asset.gltf.animations.?.len) {
            std.debug.print("Invalid animation index: {d}\n", .{animation_index});
            return;
        }

        // Calculate animation duration from samplers
        const animation = self.gltf_asset.gltf.animations.?[animation_index];
        var max_time: f32 = 0.0;

        for (animation.samplers) |sampler| {
            // Get actual time values from input accessor
            const times = self.readAccessorAsF32Slice(sampler.input) catch |err| {
                std.debug.print("Error reading animation times: {}\n", .{err});
                continue;
            };
            if (times.len > 0) {
                max_time = @max(max_time, times[times.len - 1]);
            }
        }

        // Fallback to 1 second if no time data found
        if (max_time == 0.0) {
            max_time = 1.0;
            std.debug.print("Warning: No time data found for animation {d}, using 1 second duration\n", .{animation_index});
        }

        std.debug.print("Animation {d} duration: {d:.2}s, channels: {d}\n", .{ animation_index, max_time, animation.channels.len });
        const clip = AnimationClip.init(animation_index, 0.0, max_time, .Forever);
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

    /// Update node transformations from current animation state
    fn updateNodeTransformations(self: *Self) !void {
        if (self.current_animation == null or self.gltf_asset.gltf.animations == null) return;

        const anim_state = self.current_animation.?;
        const animation = self.gltf_asset.gltf.animations.?[anim_state.animation_index];

        // Reset all node transforms to their default values
        if (self.gltf_asset.gltf.nodes) |nodes| {
            for (0..nodes.len) |i| {
                const node = nodes[i];
                self.node_transforms[i] = Transform{
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
    fn evaluateAnimationChannel(self: *Self, channel: gltf_types.AnimationChannel, sampler: gltf_types.AnimationSampler, current_time: f32, node_index: usize) !void {
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

        // First, calculate local matrices for all nodes
        for (0..nodes.len) |i| {
            self.node_matrices[i] = self.node_transforms[i].toMatrix();
        }

        // Then calculate global matrices by traversing the scene hierarchy
        // Find root nodes (nodes that are not children of other nodes)
        const allocator = self.arena.allocator();
        var is_child = try allocator.alloc(bool, nodes.len);
        defer allocator.free(is_child);

        // Initialize all as root nodes
        for (0..nodes.len) |i| {
            is_child[i] = false;
        }

        // Mark child nodes
        for (0..nodes.len) |i| {
            const node = nodes[i];
            if (node.children) |children| {
                for (children) |child_index| {
                    if (child_index < is_child.len) {
                        is_child[child_index] = true;
                    }
                }
            }
        }

        // Process root nodes and their hierarchies
        for (0..nodes.len) |i| {
            if (!is_child[i]) {
                try self.calculateNodeMatrixRecursive(i, Mat4.identity());
            }
        }
    }

    /// Recursively calculate node matrices with proper parent-child relationships
    fn calculateNodeMatrixRecursive(self: *Self, node_index: usize, parent_matrix: Mat4) !void {
        if (node_index >= self.node_matrices.len) return;

        const nodes = self.gltf_asset.gltf.nodes.?;
        const node = nodes[node_index];

        // Calculate this node's global matrix
        const local_matrix = self.node_transforms[node_index].toMatrix();
        self.node_matrices[node_index] = parent_matrix.mulMat4(&local_matrix);

        // Process children
        if (node.children) |children| {
            for (children) |child_index| {
                if (child_index < self.node_matrices.len) {
                    try self.calculateNodeMatrixRecursive(child_index, self.node_matrices[node_index]);
                }
            }
        }
    }

    /// Update final matrices for shader rendering
    fn updateShaderMatrices(self: *Self) !void {
        // Debug first time
        const debug_joints = false;
        if (debug_joints and self.joints.len > 0) {
            std.debug.print("Processing {d} joints for shader matrices\n", .{self.joints.len});
        }

        // Update joint matrices for skinned meshes
        for (0..@min(self.joints.len, MAX_JOINTS)) |i| {
            const joint = self.joints[i];
            if (joint.node_index < self.node_matrices.len) {
                self.joint_matrices[i] = self.node_matrices[joint.node_index].mulMat4(&joint.inverse_bind_matrix);

                if (debug_joints and i < 3) {
                    std.debug.print("Joint {d}: node_index={d}, node_matrix=identity?={}, inverse_bind=identity?={}\n", .{ i, joint.node_index, self.node_matrices[joint.node_index].isIdentity(), joint.inverse_bind_matrix.isIdentity() });
                }
            } else {
                self.joint_matrices[i] = Mat4.identity();
                if (debug_joints and i < 3) {
                    std.debug.print("Joint {d}: node_index={d} out of range, using identity\n", .{ i, joint.node_index });
                }
            }
        }

        // Fill remaining slots with identity matrices
        for (self.joints.len..MAX_JOINTS) |i| {
            self.joint_matrices[i] = Mat4.identity();
        }
    }

    /// Play multiple animations with different weights - for animation blending
    /// Compatible with ASSIMP-based game_angrybot animation blending system
    pub fn playWeightAnimations(self: *Self, weighted_animations: []const WeightedAnimation, frame_time: f32) !void {
        if (self.gltf_asset.gltf.animations == null) return;
        
        const animations = self.gltf_asset.gltf.animations.?;
        const debug_blending = false;
        
        if (debug_blending) {
            std.debug.print("playWeightAnimations: frame_time={d:.3}, {d} animations\n", .{ frame_time, weighted_animations.len });
        }

        // Clear node transforms to default state
        if (self.gltf_asset.gltf.nodes) |nodes| {
            for (0..nodes.len) |i| {
                const node = nodes[i];
                self.node_transforms[i] = Transform{
                    .translation = node.translation orelse vec3(0.0, 0.0, 0.0),
                    .rotation = node.rotation orelse quat(0.0, 0.0, 0.0, 1.0),
                    .scale = node.scale orelse vec3(1.0, 1.0, 1.0),
                };
            }
        }

        // Temporary storage for blended transforms
        const allocator = self.arena.allocator();
        var blended_transforms = try allocator.alloc(Transform, self.node_transforms.len);
        var total_weights = try allocator.alloc(f32, self.node_transforms.len);
        defer allocator.free(blended_transforms);
        defer allocator.free(total_weights);

        // Initialize blended transforms and weights
        for (0..self.node_transforms.len) |i| {
            blended_transforms[i] = Transform.init();
            total_weights[i] = 0.0;
        }

        // Process each weighted animation
        for (weighted_animations) |weighted| {
            if (weighted.weight <= 0.0) {
                continue;
            }

            if (debug_blending) {
                std.debug.print("  Processing animation weight={d:.3}, start_time={d:.2}, end_time={d:.2}\n", .{ weighted.weight, weighted.start_time, weighted.end_time });
            }

            // Calculate animation time based on ASSIMP logic
            const time_range = weighted.end_time - weighted.start_time;
            var target_anim_time: f32 = 0.0;

            if (weighted.start_real_time > 0.0) {
                // Non-looped animation (like "dead" animation)
                const elapsed_time = frame_time - weighted.start_real_time;
                target_anim_time = @min(elapsed_time + weighted.offset, time_range);
            } else {
                // Looped animation (like idle, forward, back, etc.)
                target_anim_time = @mod((frame_time + weighted.offset), time_range);
            }

            target_anim_time += weighted.start_time;

            // Clamp to valid range
            target_anim_time = @max(weighted.start_time, @min(weighted.end_time, target_anim_time));

            if (debug_blending) {
                std.debug.print("    Calculated time: {d:.3}\n", .{target_anim_time});
            }

            // Since we only have one animation in glTF models, use animation index 0
            // The time-based subdivision is handled by the weighted animation parameters
            const animation_index: u32 = 0;
            if (animation_index >= animations.len) continue;

            // Apply this animation with the given weight
            try self.blendAnimationAtTime(animation_index, target_anim_time, weighted.weight, blended_transforms, total_weights);
        }

        // Normalize and apply blended transforms
        for (0..self.node_transforms.len) |i| {
            if (total_weights[i] > 0.0) {
                // Normalize by total weight
                const inv_weight = 1.0 / total_weights[i];
                blended_transforms[i].translation = blended_transforms[i].translation.mulScalar(inv_weight);
                blended_transforms[i].scale = blended_transforms[i].scale.mulScalar(inv_weight);
                
                // Quaternions need renormalization after weighted blending
                blended_transforms[i].rotation.normalize();
                
                self.node_transforms[i] = blended_transforms[i];
            }
        }

        // Calculate final matrices
        try self.calculateNodeMatrices();
        try self.updateShaderMatrices();
    }

    /// Blend a single animation at a specific time with a given weight
    fn blendAnimationAtTime(self: *Self, animation_index: u32, current_time: f32, weight: f32, blended_transforms: []Transform, total_weights: []f32) !void {
        const animation = self.gltf_asset.gltf.animations.?[animation_index];

        // Apply animation channels with blending
        for (animation.channels) |channel| {
            if (channel.target.node) |node_index| {
                if (node_index >= self.node_transforms.len) continue;

                const sampler = animation.samplers[channel.sampler];
                
                // Get time values from the input accessor
                const times = self.readAccessorAsF32Slice(sampler.input) catch continue;
                if (times.len == 0) continue;

                // Find the keyframe indices and interpolation factor
                const keyframe_info = AnimationInterpolation.findKeyframeIndices(times, current_time);
                const index0 = keyframe_info[0];
                const index1 = keyframe_info[1];
                const factor = keyframe_info[2];

                // Apply the animation based on the target property with blending
                switch (channel.target.path) {
                    .translation => {
                        const values = self.readAccessorAsVec3Slice(sampler.output) catch continue;
                        if (values.len > index0) {
                            const start_value = values[index0];
                            const end_value = if (index1 < values.len) values[index1] else start_value;

                            const interpolated_value = switch (sampler.interpolation) {
                                .linear => AnimationInterpolation.lerpVec3(start_value, end_value, factor),
                                .step => start_value,
                                .cubic_spline => start_value, // TODO: implement cubic spline
                            };

                            // Blend with existing translation
                            blended_transforms[node_index].translation = blended_transforms[node_index].translation.add(&interpolated_value.mulScalar(weight));
                        }
                    },
                    .rotation => {
                        const values = self.readAccessorAsQuatSlice(sampler.output) catch continue;
                        if (values.len > index0) {
                            const start_value = values[index0];
                            const end_value = if (index1 < values.len) values[index1] else start_value;

                            const interpolated_value = switch (sampler.interpolation) {
                                .linear => AnimationInterpolation.slerpQuat(start_value, end_value, factor),
                                .step => start_value,
                                .cubic_spline => start_value, // TODO: implement cubic spline
                            };

                            // Blend quaternions - weighted sum (will be normalized later)
                            const weighted_quat = Quat{
                                .data = [4]f32{
                                    interpolated_value.data[0] * weight,
                                    interpolated_value.data[1] * weight,
                                    interpolated_value.data[2] * weight,
                                    interpolated_value.data[3] * weight,
                                }
                            };

                            blended_transforms[node_index].rotation.data[0] += weighted_quat.data[0];
                            blended_transforms[node_index].rotation.data[1] += weighted_quat.data[1];
                            blended_transforms[node_index].rotation.data[2] += weighted_quat.data[2];
                            blended_transforms[node_index].rotation.data[3] += weighted_quat.data[3];
                        }
                    },
                    .scale => {
                        const values = self.readAccessorAsVec3Slice(sampler.output) catch continue;
                        if (values.len > index0) {
                            const start_value = values[index0];
                            const end_value = if (index1 < values.len) values[index1] else start_value;

                            const interpolated_value = switch (sampler.interpolation) {
                                .linear => AnimationInterpolation.lerpVec3(start_value, end_value, factor),
                                .step => start_value,
                                .cubic_spline => start_value, // TODO: implement cubic spline
                            };

                            // Blend with existing scale
                            blended_transforms[node_index].scale = blended_transforms[node_index].scale.add(&interpolated_value.mulScalar(weight));
                        }
                    },
                    .weights => {
                        // TODO: implement morph target weights
                    },
                }

                // Update total weight for this node
                total_weights[node_index] += weight;
            }
        }
    }
};
