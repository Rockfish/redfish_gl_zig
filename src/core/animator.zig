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
pub const DEFAULT_ANIMATION_DURATION: f32 = 1.0;

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

    pub fn init(
        animation_index: u32,
        start_time: f32,
        end_time: f32,
        repeat_mode: AnimationRepeatMode,
    ) AnimationClip {
        return .{
            .animation_index = animation_index,
            .start_time = start_time,
            .end_time = end_time,
            .repeat_mode = repeat_mode,
        };
    }
};

/// glTF-specific animation state that tracks time in seconds
pub const AnimationState = struct {
    animation_index: u32,
    current_time: f32,
    start_time: f32,
    end_time: f32,
    repeat_mode: AnimationRepeatMode,
    repeat_completions: u32,

    pub fn init(
        animation_index: u32,
        start_time: f32,
        end_time: f32,
        repeat_mode: AnimationRepeatMode,
    ) AnimationState {
        return .{
            .animation_index = animation_index,
            .current_time = start_time,
            .start_time = start_time,
            .end_time = end_time,
            .repeat_mode = repeat_mode,
            .repeat_completions = 0,
        };
    }

    pub fn update(self: *AnimationState, delta_time: f32) void {
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
    start_time: f32, // Animation start time in seconds
    end_time: f32, // Animation end time in seconds
    offset: f32, // Time offset for animation synchronization
    start_real_time: f32, // Real-world start time for non-looped animations

    pub fn init(
        weight: f32,
        start_time: f32,
        end_time: f32,
        offset: f32,
        start_real_time: f32,
    ) WeightedAnimation {
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

/// Keyframe interpolation result containing indices and interpolation factor
pub const KeyframeInfo = struct {
    start_index: usize,
    end_index: usize,
    factor: f32,
};

/// Pre-processed animation channel data for translation
pub const NodeTranslationData = struct {
    interpolation: gltf_types.Interpolation,
    keyframe_times: []const f32,
    positions: []const Vec3,
};

/// Pre-processed animation channel data for rotation
pub const NodeRotationData = struct {
    interpolation: gltf_types.Interpolation,
    keyframe_times: []const f32,
    rotations: []const Quat,
};

/// Pre-processed animation channel data for scale
pub const NodeScaleData = struct {
    interpolation: gltf_types.Interpolation,
    keyframe_times: []const f32,
    scales: []const Vec3,
};

/// Pre-processed animation channel data for morph target weights
pub const NodeWeightData = struct {
    interpolation: gltf_types.Interpolation,
    keyframe_times: []const f32,
    weights: []const f32,
};

/// Pre-processed animation channels for a single node
/// Groups all animation data affecting one node together for optimal cache locality
pub const NodeAnimationData = struct {
    node_id: u32,
    translation: ?NodeTranslationData,
    rotation: ?NodeRotationData,
    scale: ?NodeScaleData,
    weights: ?NodeWeightData,
};

/// Complete animation data including name, duration, and associated node animations
pub const Animation = struct {
    name: []const u8,
    duration: f32,
    node_data: []NodeAnimationData,
};

pub const Animator = struct {
    arena: *ArenaAllocator,

    // glTF animation data references
    gltf_asset: *const GltfAsset,
    skin_index: ?u32,
    joints: []Joint,

    // Animation state - support multiple concurrent animations
    active_animations: ArrayList(AnimationState),

    // Node transform cache (indexed by node index)
    node_transforms: []Transform,

    // Cached root nodes (calculated once at init)
    root_nodes: []u32,

    // Pre-processed animations with names, durations, and node data
    animations: []Animation,

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

                    std.debug.print(
                        "Loaded {d} inverse bind matrices for skin {d}\n",
                        .{ inverse_bind_matrices.len, skin_idx },
                    );
                } else {
                    // Fallback to identity matrices if no inverse bind matrices provided
                    inverse_bind_matrices = try allocator.alloc(Mat4, skin.joints.len);
                    for (0..skin.joints.len) |i| {
                        inverse_bind_matrices[i] = Mat4.identity();
                    }
                    std.debug.print(
                        "No inverse bind matrices found for skin {d}, using identity matrices\n",
                        .{skin_idx},
                    );
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

        // Calculate root nodes once at initialization
        var root_nodes_list = ArrayList(u32).init(allocator);
        if (gltf_asset.gltf.nodes) |nodes| {
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

            // Collect root nodes
            for (0..nodes.len) |i| {
                if (!is_child[i]) {
                    try root_nodes_list.append(@intCast(i));
                }
            }
        }

        // Pre-process animation channels
        const animations = try preprocessAnimationChannels(allocator, gltf_asset);

        animator.* = Animator{
            .arena = arena,
            .gltf_asset = gltf_asset,
            .skin_index = skin_index,
            .joints = try joints.toOwnedSlice(),
            .active_animations = ArrayList(AnimationState).init(allocator),
            .node_transforms = try allocator.alloc(Transform, node_count),
            .root_nodes = try root_nodes_list.toOwnedSlice(),
            .animations = animations,
            .joint_matrices = [_]Mat4{Mat4.identity()} ** MAX_JOINTS,
        };

        // Initialize node transforms to identity
        for (0..animator.node_transforms.len) |i| {
            animator.node_transforms[i] = Transform.init();
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
        if (clip.animation_index >= self.animations.len) {
            std.debug.print("Invalid animation index: {d}\n", .{clip.animation_index});
            return;
        }

        self.active_animations.clearRetainingCapacity();

        const anim_state = AnimationState.init(
            clip.animation_index,
            clip.start_time,
            clip.end_time,
            clip.repeat_mode,
        );
        try self.active_animations.append(anim_state);

        std.debug.print("Playing glTF animation {d}\n", .{clip.animation_index});
    }

    /// Play animation by index
    pub fn playAnimationById(self: *Self, animation_index: u32) !void {
        if (animation_index >= self.animations.len) {
            std.debug.print("Invalid animation index: {d}\n", .{animation_index});
            return;
        }

        const animation = self.animations[animation_index];

        std.debug.print(
            "Animation {d} '{s}' duration: {d:.2}s, nodes: {d}\n",
            .{ animation_index, animation.name, animation.duration, animation.node_data.len },
        );

        // Clear all animations, play just this one (backward compatibility)
        self.active_animations.clearRetainingCapacity();
        const anim_state = AnimationState.init(
            animation_index,
            0.0,
            animation.duration,
            .Forever,
        );
        try self.active_animations.append(anim_state);
    }

    /// Play animation at specific time
    pub fn playTick(self: *Self, time: f32) !void {
        // Update time for ALL active animations
        for (self.active_animations.items) |*anim_state| {
            anim_state.current_time = time;
        }
        if (self.active_animations.items.len > 0) {
            try self.updateNodeTransformations();
            try self.calculateNodeTransforms();
            try self.setShaderMatrices();
        }
    }

    /// Play all animations in the model simultaneously (for InterpolationTest)
    pub fn playAllAnimations(self: *Self) !void {
        if (self.animations.len == 0) return;

        self.active_animations.clearRetainingCapacity();

        for (0..self.animations.len) |i| {
            const animation_index = @as(u32, @intCast(i));
            const animation = self.animations[animation_index];
            const anim_state = AnimationState.init(
                animation_index,
                0.0,
                animation.duration,
                .Forever,
            );
            try self.active_animations.append(anim_state);
        }

        std.debug.print("Playing {d} animations simultaneously\n", .{self.animations.len});
    }

    /// Play specific animations by indices
    pub fn playAnimations(self: *Self, animation_indices: []const u32) !void {
        self.active_animations.clearRetainingCapacity();

        for (animation_indices) |animation_index| {
            if (animation_index >= self.animations.len) continue;
            const animation = self.animations[animation_index];
            const anim_state = AnimationState.init(
                animation_index,
                0.0,
                animation.duration,
                .Forever,
            );
            try self.active_animations.append(anim_state);
        }
    }

    /// Update animation with delta time - maintains same interface
    pub fn updateAnimation(self: *Self, delta_time: f32) !void {
        for (self.active_animations.items) |*anim_state| {
            anim_state.update(delta_time);
        }
        if (self.active_animations.items.len > 0) {
            self.resetNodeTransformations();
            self.updateNodeTransformations();
            self.calculateNodeTransforms();
            self.setShaderMatrices();
        }
    }

    /// Reset all node transforms to their default values
    fn resetNodeTransformations(self: *Self) void {
        if (self.gltf_asset.gltf.nodes) |nodes| {
            for (nodes, 0..) |node, i| {
                self.node_transforms[i] = Transform{
                    .translation = node.translation orelse vec3(0.0, 0.0, 0.0),
                    .rotation = node.rotation orelse quat(0.0, 0.0, 0.0, 1.0),
                    .scale = node.scale orelse vec3(1.0, 1.0, 1.0),
                };
            }
        }
    }

    /// Update node transformations from active animation states
    fn updateNodeTransformations(self: *Self) void {
        for (self.active_animations.items) |anim_state| {
            if (anim_state.animation_index >= self.animations.len) continue;

            const animation_data = self.animations[anim_state.animation_index].node_data;

            for (animation_data) |node_anim| {
                const node_index = node_anim.node_id;
                self.node_transforms[node_index] = evaluateNodeTransform(
                    self.node_transforms[node_index],
                    node_anim,
                    anim_state.current_time,
                );
            }
        }
    }

    /// Calculate world transforms for all nodes using Transform operations
    fn calculateNodeTransforms(self: *Self) void {
        if (self.gltf_asset.gltf.nodes == null) return;

        // Calculate world transforms by traversing the scene hierarchy
        for (self.root_nodes) |root_node_index| {
            self.calculateNodeTransformRecursive(root_node_index, Transform.init());
        }
    }

    /// Recursively calculate node transforms with proper parent-child relationships
    fn calculateNodeTransformRecursive(self: *Self, node_index: usize, parent_transform: Transform) void {
        if (node_index >= self.node_transforms.len) return;

        const nodes = self.gltf_asset.gltf.nodes.?;
        const node = nodes[node_index];

        // Calculate this node's world transform
        const local_transform = self.node_transforms[node_index];
        self.node_transforms[node_index] = parent_transform.mulTransform(local_transform);

        // Process children
        if (node.children) |children| {
            for (children) |child_index| {
                self.calculateNodeTransformRecursive(child_index, self.node_transforms[node_index]);
            }
        }
    }

    /// Set final matrices for shader rendering
    fn setShaderMatrices(self: *Self) void {
        // Debug first time
        const debug_joints = false;
        if (debug_joints and self.joints.len > 0) {
            std.debug.print("Processing {d} joints for shader matrices\n", .{self.joints.len});
        }

        // Update joint matrices for skinned meshes
        for (0..@min(self.joints.len, MAX_JOINTS)) |i| {
            const joint = self.joints[i];
            if (joint.node_index < self.node_transforms.len) {
                // Convert transform to matrix only when needed for joint calculation
                const node_matrix = self.node_transforms[joint.node_index].toMatrix();
                self.joint_matrices[i] = node_matrix.mulMat4(&joint.inverse_bind_matrix);

                if (debug_joints and i < 3) {
                    std.debug.print(
                        "Joint {d}: node_index={d}, node_matrix=identity?={}, inverse_bind=identity?={}\n",
                        .{
                            i,
                            joint.node_index,
                            node_matrix.isIdentity(),
                            joint.inverse_bind_matrix.isIdentity(),
                        },
                    );
                }
            } else {
                self.joint_matrices[i] = Mat4.identity();
                if (debug_joints and i < 3) {
                    std.debug.print(
                        "Joint {d}: node_index={d} out of range, using identity\n",
                        .{ i, joint.node_index },
                    );
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
        if (self.animations.len == 0) return;
        const ENABLE_BLEND_DEBUG = std.debug.runtime_safety and false; // Enable for debugging

        if (ENABLE_BLEND_DEBUG) {
            std.debug.print(
                "playWeightAnimations: frame_time={d:.3}, {d} animations\n",
                .{ frame_time, weighted_animations.len },
            );
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

            if (ENABLE_BLEND_DEBUG) {
                std.debug.print(
                    "  Processing animation weight={d:.3}, start_time={d:.2}, end_time={d:.2}\n",
                    .{ weighted.weight, weighted.start_time, weighted.end_time },
                );
            }

            // ASSIMP Compatibility: Calculate animation time using two distinct timing modes
            const time_range = weighted.end_time - weighted.start_time;
            var target_anim_time: f32 = 0.0;

            if (weighted.start_real_time > 0.0) {
                // One-shot animations (e.g., death, attack): play once from start_real_time
                // Progress linearly until completion, then stay at end
                const elapsed_since_start = frame_time - weighted.start_real_time;
                target_anim_time = @min(elapsed_since_start + weighted.offset, time_range);
            } else {
                // Looping animations (e.g., idle, walk, run): repeat indefinitely
                // Use modulo to wrap time within animation range for continuous loops
                target_anim_time = @mod((frame_time + weighted.offset), time_range);
            }

            target_anim_time += weighted.start_time;

            // Clamp to valid range
            target_anim_time = @max(weighted.start_time, @min(weighted.end_time, target_anim_time));

            if (ENABLE_BLEND_DEBUG) {
                std.debug.print("    Calculated time: {d:.3}\n", .{target_anim_time});
            }

            // Since we only have one animation in glTF models, use animation index 0
            // The time-based subdivision is handled by the weighted animation parameters
            const animation_index: u32 = 0;
            if (animation_index >= self.animations.len) continue;

            // Apply this animation with the given weight
            try self.blendAnimationAtTime(
                animation_index,
                target_anim_time,
                weighted.weight,
                blended_transforms,
                total_weights,
            );
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
        try self.calculateNodeTransforms();
        try self.setShaderMatrices();
    }

    /// Blend a single animation at a specific time with a given weight
    fn blendAnimationAtTime(
        self: *Self,
        animation_index: u32,
        current_time: f32,
        blend_weight: f32,
        accumulator_transforms: []Transform,
        weight_totals: []f32,
    ) !void {
        if (animation_index >= self.animations.len) return;

        const animation_data = self.animations[animation_index].node_data;

        // Apply each node's animation channels with blending
        for (animation_data) |node_anim| {
            if (node_anim.node_id >= self.node_transforms.len) continue;

            const node_index = node_anim.node_id;

            // Blend translation animation
            if (node_anim.translation) |translation_data| {
                const keyframe_info = findKeyframeIndices(translation_data.keyframe_times, current_time);

                const interpolated_value = interpolateVec3(
                    translation_data.positions,
                    keyframe_info.start_index,
                    keyframe_info.end_index,
                    keyframe_info.factor,
                    translation_data.interpolation,
                );

                // Blend with existing translation
                accumulator_transforms[node_index].translation = accumulator_transforms[node_index].translation.add(&interpolated_value.mulScalar(blend_weight));
            }

            // Blend rotation animation
            if (node_anim.rotation) |rotation_data| {
                const keyframe_info = findKeyframeIndices(rotation_data.keyframe_times, current_time);

                const interpolated_value = interpolateQuat(
                    rotation_data.rotations,
                    keyframe_info.start_index,
                    keyframe_info.end_index,
                    keyframe_info.factor,
                    rotation_data.interpolation,
                );

                // Blend quaternions - weighted sum (will be normalized later)
                const weighted_quat = Quat{ .data = [4]f32{
                    interpolated_value.data[0] * blend_weight,
                    interpolated_value.data[1] * blend_weight,
                    interpolated_value.data[2] * blend_weight,
                    interpolated_value.data[3] * blend_weight,
                } };

                accumulator_transforms[node_index].rotation.data[0] += weighted_quat.data[0];
                accumulator_transforms[node_index].rotation.data[1] += weighted_quat.data[1];
                accumulator_transforms[node_index].rotation.data[2] += weighted_quat.data[2];
                accumulator_transforms[node_index].rotation.data[3] += weighted_quat.data[3];
            }

            // Blend scale animation
            if (node_anim.scale) |scale_data| {
                const keyframe_info = findKeyframeIndices(scale_data.keyframe_times, current_time);

                const interpolated_value = interpolateVec3(
                    scale_data.scales,
                    keyframe_info.start_index,
                    keyframe_info.end_index,
                    keyframe_info.factor,
                    scale_data.interpolation,
                );

                // Blend with existing scale
                accumulator_transforms[node_index].scale = accumulator_transforms[node_index].scale.add(&interpolated_value.mulScalar(blend_weight));
            }

            // Blend weight animation (morph targets)
            if (node_anim.weights) |weight_data| {
                const keyframe_info = findKeyframeIndices(weight_data.keyframe_times, current_time);

                // Weight animation handling would go here
                // Currently not implemented in Transform struct
                // _ = weight_data;
                _ = keyframe_info;
            }

            // Update total weight for this node
            weight_totals[node_index] += blend_weight;
        }
    }
};

/// Evaluate animated transform for a single node at a specific time
fn evaluateNodeTransform(
    base_transform: Transform,
    node_anim: NodeAnimationData,
    current_time: f32,
) Transform {
    var transform = base_transform.clone();

    if (getAnimatedTranslation(node_anim.translation, current_time)) |value| {
        transform.translation = value;
    }

    if (getAnimatedRotation(node_anim.rotation, current_time)) |value| {
        transform.rotation = value;
    }

    if (getAnimatedScale(node_anim.scale, current_time)) |value| {
        transform.scale = value;
    }

    // Weight animation (morph targets) - not yet implemented

    return transform;
}

/// Get the last keyframe time from a keyframe times array
fn getLastKeyframeTime(keyframe_times: []const f32) f32 {
    return if (keyframe_times.len > 0) keyframe_times[keyframe_times.len - 1] else 0.0;
}

fn getAnimatedTranslation(translation_data: ?NodeTranslationData, current_time: f32) ?Vec3 {
    const data = translation_data orelse return null;

    const keyframe_info = findKeyframeIndices(data.keyframe_times, current_time);
    return interpolateVec3(
        data.positions,
        keyframe_info.start_index,
        keyframe_info.end_index,
        keyframe_info.factor,
        data.interpolation,
    );
}

fn getAnimatedRotation(rotation_data: ?NodeRotationData, current_time: f32) ?Quat {
    const data = rotation_data orelse return null;

    const keyframe_info = findKeyframeIndices(data.keyframe_times, current_time);
    return interpolateQuat(
        data.rotations,
        keyframe_info.start_index,
        keyframe_info.end_index,
        keyframe_info.factor,
        data.interpolation,
    );
}

fn getAnimatedScale(scale_data: ?NodeScaleData, current_time: f32) ?Vec3 {
    const data = scale_data orelse return null;

    const keyframe_info = findKeyframeIndices(data.keyframe_times, current_time);
    return interpolateVec3(
        data.scales,
        keyframe_info.start_index,
        keyframe_info.end_index,
        keyframe_info.factor,
        data.interpolation,
    );
}

/// Find interpolation factor and surrounding keyframe indices
pub fn findKeyframeIndices(times: []const f32, current_time: f32) KeyframeInfo {
    if (times.len == 0) return .{ .start_index = 0, .end_index = 0, .factor = 0.0 };
    if (times.len == 1) return .{ .start_index = 0, .end_index = 0, .factor = 0.0 };

    // Find the keyframes that surround the current time
    for (0..times.len - 1) |i| {
        if (current_time >= times[i] and current_time <= times[i + 1]) {
            const duration = times[i + 1] - times[i];
            const factor = if (duration > 0.0) (current_time - times[i]) / duration else 0.0;
            return .{ .start_index = i, .end_index = i + 1, .factor = factor };
        }
    }

    // If we're past the end, use the last keyframe
    if (current_time >= times[times.len - 1]) {
        return .{ .start_index = times.len - 1, .end_index = times.len - 1, .factor = 0.0 };
    }

    // If we're before the start, use the first keyframe
    return .{ .start_index = 0, .end_index = 0, .factor = 0.0 };
}

/// Interpolate Vec3 values based on interpolation mode
pub fn interpolateVec3(
    values: []const Vec3,
    start_index: usize,
    end_index: usize,
    factor: f32,
    interpolation: gltf_types.Interpolation,
) Vec3 {
    if (values.len == 0 or start_index >= values.len) return vec3(0.0, 0.0, 0.0);

    const start_value = values[start_index];
    const end_value = if (end_index < values.len) values[end_index] else start_value;

    return switch (interpolation) {
        .linear => Vec3.lerp(&start_value, &end_value, factor),
        .step => start_value,
        .cubic_spline => start_value, // TODO: implement cubic spline
    };
}

/// Interpolate Quat values based on interpolation mode
pub fn interpolateQuat(
    values: []const Quat,
    start_index: usize,
    end_index: usize,
    factor: f32,
    interpolation: gltf_types.Interpolation,
) Quat {
    if (values.len == 0 or start_index >= values.len) return quat(0.0, 0.0, 0.0, 1.0);

    const start_value = values[start_index];
    const end_value = if (end_index < values.len) values[end_index] else start_value;

    return switch (interpolation) {
        .linear => start_value.slerp(&end_value, factor),
        .step => start_value,
        .cubic_spline => start_value, // TODO: implement cubic spline
    };
}

/// Pre-process all animation channels into Animation structs with pre-calculated durations
/// Groups all animation data affecting each node together for better cache locality
fn preprocessAnimationChannels(allocator: Allocator, gltf_asset: *const GltfAsset) ![]Animation {
    const gltf_animations = gltf_asset.gltf.animations orelse return try allocator.alloc(Animation, 0);

    var all_animations = try allocator.alloc(Animation, gltf_animations.len);

    for (gltf_animations, 0..) |gltf_animation, anim_idx| {
        // Use a HashMap to group channels by node_id
        var node_channel_map = std.HashMap(
            u32,
            NodeAnimationData,
            std.hash_map.AutoContext(u32),
            std.hash_map.default_max_load_percentage,
        ).init(allocator);
        defer node_channel_map.deinit();

        // Process each channel in this animation
        for (gltf_animation.channels) |channel| {
            const node_id = channel.target.node orelse continue;
            const sampler = gltf_animation.samplers[channel.sampler];

            // Read input and output data once
            const input_times = readAccessorAsF32Slice(gltf_asset, sampler.input);

            // Get or create NodeAnimationData for this node
            var node_channels = node_channel_map.get(node_id) orelse NodeAnimationData{
                .node_id = node_id,
                .translation = null,
                .rotation = null,
                .scale = null,
                .weights = null,
            };

            // Add the appropriate channel data
            switch (channel.target.path) {
                .translation => {
                    const output_values = readAccessorAsVec3Slice(gltf_asset, sampler.output);
                    node_channels.translation = NodeTranslationData{
                        .interpolation = sampler.interpolation,
                        .keyframe_times = input_times,
                        .positions = output_values,
                    };
                },
                .rotation => {
                    const output_values = readAccessorAsQuatSlice(gltf_asset, sampler.output);
                    node_channels.rotation = NodeRotationData{
                        .interpolation = sampler.interpolation,
                        .keyframe_times = input_times,
                        .rotations = output_values,
                    };
                },
                .scale => {
                    const output_values = readAccessorAsVec3Slice(gltf_asset, sampler.output);
                    node_channels.scale = NodeScaleData{
                        .interpolation = sampler.interpolation,
                        .keyframe_times = input_times,
                        .scales = output_values,
                    };
                },
                .weights => {
                    const output_values = readAccessorAsF32Slice(gltf_asset, sampler.output);
                    node_channels.weights = NodeWeightData{
                        .interpolation = sampler.interpolation,
                        .keyframe_times = input_times,
                        .weights = output_values,
                    };
                },
            }

            // Update the map
            try node_channel_map.put(node_id, node_channels);
        }

        // Convert HashMap to array
        const node_channels_list = try allocator.alloc(NodeAnimationData, node_channel_map.count());
        var iterator = node_channel_map.iterator();
        var i: usize = 0;
        while (iterator.next()) |entry| {
            node_channels_list[i] = entry.value_ptr.*;
            i += 1;
        }

        // Calculate animation duration from all channels
        var max_time: f32 = 0.0;
        for (node_channels_list) |node_anim| {
            if (node_anim.translation) |translation_data| {
                max_time = @max(max_time, getLastKeyframeTime(translation_data.keyframe_times));
            }
            if (node_anim.rotation) |rotation_data| {
                max_time = @max(max_time, getLastKeyframeTime(rotation_data.keyframe_times));
            }
            if (node_anim.scale) |scale_data| {
                max_time = @max(max_time, getLastKeyframeTime(scale_data.keyframe_times));
            }
            if (node_anim.weights) |weight_data| {
                max_time = @max(max_time, getLastKeyframeTime(weight_data.keyframe_times));
            }
        }

        // Use default duration if no time data found
        if (max_time == 0.0) {
            max_time = DEFAULT_ANIMATION_DURATION;
        }

        // Create Animation struct with name, duration, and node data
        const animation_name = if (gltf_animation.name) |name| name else try std.fmt.allocPrint(allocator, "Animation_{d}", .{anim_idx});

        all_animations[anim_idx] = Animation{
            .name = animation_name,
            .duration = max_time,
            .node_data = node_channels_list,
        };

        std.debug.print("Pre-processed animation {d} '{s}': {d:.2}s duration, {d} nodes with animation data\n", .{ anim_idx, animation_name, max_time, node_channels_list.len });
    }

    return all_animations;
}

/// Helper function to read accessor data as f32 slice (standalone version for preprocessing)
fn readAccessorAsF32Slice(gltf_asset: *const GltfAsset, accessor_index: u32) []const f32 {
    const accessor = gltf_asset.gltf.accessors.?[accessor_index];
    const buffer_view = gltf_asset.gltf.buffer_views.?[accessor.buffer_view.?];
    const buffer_data = gltf_asset.buffer_data.items[buffer_view.buffer];

    const start = accessor.byte_offset + buffer_view.byte_offset;
    const data_size = @sizeOf(f32) * accessor.count;
    const end = start + data_size;

    const data = buffer_data[start..end];
    return @as([*]const f32, @ptrCast(@alignCast(data)))[0..accessor.count];
}

/// Helper function to read accessor data as Vec3 slice (standalone version for preprocessing)
fn readAccessorAsVec3Slice(gltf_asset: *const GltfAsset, accessor_index: u32) []const Vec3 {
    const accessor = gltf_asset.gltf.accessors.?[accessor_index];
    const buffer_view = gltf_asset.gltf.buffer_views.?[accessor.buffer_view.?];
    const buffer_data = gltf_asset.buffer_data.items[buffer_view.buffer];

    const start = accessor.byte_offset + buffer_view.byte_offset;
    const data_size = @sizeOf(Vec3) * accessor.count;
    const end = start + data_size;

    const data = buffer_data[start..end];
    return @as([*]const Vec3, @ptrCast(@alignCast(data)))[0..accessor.count];
}

/// Helper function to read accessor data as Quat slice (standalone version for preprocessing)
fn readAccessorAsQuatSlice(gltf_asset: *const GltfAsset, accessor_index: u32) []const Quat {
    const accessor = gltf_asset.gltf.accessors.?[accessor_index];
    const buffer_view = gltf_asset.gltf.buffer_views.?[accessor.buffer_view.?];
    const buffer_data = gltf_asset.buffer_data.items[buffer_view.buffer];

    const start = accessor.byte_offset + buffer_view.byte_offset;
    const data_size = @sizeOf(Quat) * accessor.count;
    const end = start + data_size;

    const data = buffer_data[start..end];
    return @as([*]const Quat, @ptrCast(@alignCast(data)))[0..accessor.count];
}
