const std = @import("std");
const math = @import("math");
const gltf_types = @import("gltf/gltf.zig");
const GltfAsset = @import("asset_loader.zig").GltfAsset;
const Transform = @import("transform.zig").Transform;

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const ArrayList = std.ArrayList;

const Vec3 = math.Vec3;
const vec3 = math.vec3;
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

pub const WeightedAnimation = struct {
    animation_index: u32,
    start_time: f32, // Animation start time in seconds
    end_time: f32, // Animation end time in seconds
    weight: f32,
    offset: f32, // Time offset for animation synchronization
    optional_start: f32 = 0.0, // Optional start time for one-shot animations

    pub fn init(
        animation_index: u32,
        weight: f32,
        start_time: f32,
        end_time: f32,
        offset: f32,
        optional_start: f32,
    ) WeightedAnimation {
        return .{
            .animation_index = animation_index,
            .start_time = start_time,
            .end_time = end_time,
            .weight = weight,
            .offset = offset,
            .optional_start = optional_start,
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

pub const Animation = struct {
    name: []const u8,
    duration: f32,
    node_data: []NodeAnimationData,
};

pub const Node = struct {
    name: ?[]const u8,
    children: ?[]const u32,
    mesh: ?u32,
    skin: ?u32,
    initial_transform: Transform,
    calculated_transform: ?Transform,
};

pub const Animator = struct {
    arena: *ArenaAllocator,

    // glTF animation data references
    gltf_asset: *const GltfAsset,
    skin_index: ?u32,
    joints: []Joint,

    // Cached root nodes (calculated once at init)
    root_nodes: []u32,

    // Preprocessed initial node data with transforms extracted from TRS or matrix
    nodes: []Node,

    // Pre-processed animations with names, durations, and node data
    animations: []Animation,

    // Animation state - support multiple concurrent animations
    active_animations: ArrayList(AnimationState),

    // Weighted animations for blending multiple animations together
    weight_animations: ArrayList(WeightedAnimation),

    // Final matrices for rendering
    joint_matrices: [MAX_JOINTS]Mat4,

    const Self = @This();

    pub fn init(arena: *ArenaAllocator, gltf_asset: *const GltfAsset, skin_index: ?u32) !*Self {
        const allocator = arena.allocator();
        const animator = try allocator.create(Animator);

        // Initialize joint data from skin
        var joints = try preprocessJoints(allocator, gltf_asset, skin_index);

        // Calculate root nodes once at initialization
        var root_nodes_list = try preprocessRootNodes(allocator, gltf_asset);

        // Pre-process animation channels
        const animations = try preprocessAnimationChannels(allocator, gltf_asset);

        // Pre-process initial nodes
        const initial_nodes = preprocessNodes(allocator, gltf_asset);

        var buf: [500]u8 = undefined;
        for (initial_nodes, 0..) |node, i| {
            std.debug.print(
                "Node {d}: '{s}' transform: {s}\n",
                .{ i, node.name orelse "unnamed", node.initial_transform.asString(&buf) },
            );
        }

        animator.* = Animator{
            .arena = arena,
            .gltf_asset = gltf_asset,
            .skin_index = skin_index,
            .joints = try joints.toOwnedSlice(),
            .active_animations = ArrayList(AnimationState).init(allocator),
            .weight_animations = ArrayList(WeightedAnimation).init(allocator),
            .root_nodes = try root_nodes_list.toOwnedSlice(),
            .nodes = initial_nodes,
            .animations = animations,
            .joint_matrices = [_]Mat4{Mat4.identity()} ** MAX_JOINTS,
        };

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
            try self.calculateWorldTransforms();
            try self.setShaderMatrices();
        }
    }

    /// Play all animations in the model simultaneously (for InterpolationTest)
    pub fn playAllAnimations(self: *Self) !void {
        if (self.animations.len == 0) return;

        self.active_animations.clearRetainingCapacity();

        for (0..self.animations.len) |i| {
            const animation_index: u32 = @intCast(i);
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

    pub fn updateAnimation(self: *Self, delta_time: f32) !void {
        for (self.active_animations.items) |*anim_state| {
            anim_state.update(delta_time);
        }
        if (self.active_animations.items.len > 0) {
            self.resetNodeTransformations();
            self.updateNodeTransformations();
            self.calculateWorldTransforms();
            self.setShaderMatrices();
        }
    }

    pub fn updateWeightedAnimations(self: *Self, weighted_animations: []const WeightedAnimation, frame_time: f32) !void {
        self.resetNodeTransformations();
        self.updateNodeTransformationsWeighted(weighted_animations, frame_time);
        self.calculateWorldTransforms();
        self.setShaderMatrices();
    }

    /// Reset all node transforms to their default values using preprocessed initial nodes
    fn resetNodeTransformations(self: *Self) void {
        for (self.nodes) |*node| {
            node.calculated_transform = null;
        }
    }

    /// Update node transformations from active animation states
    fn updateNodeTransformations(self: *Self) void {
        for (self.active_animations.items) |anim_state| {
            const node_anim_data = self.animations[anim_state.animation_index].node_data;

            for (node_anim_data) |anim_data| {
                const initial_transform = self.nodes[anim_data.node_id].initial_transform;
                const animated_transform = getAnimatedTransform(
                    initial_transform,
                    anim_data,
                    anim_state.current_time,
                );
                self.nodes[anim_data.node_id].calculated_transform = animated_transform;
            }
        }
    }

    fn updateNodeTransformationsWeighted(self: *Self, weighted_animations: []const WeightedAnimation, frame_time: f32) void {
        for (weighted_animations) |weighted| {
            if (weighted.weight <= 0.05) continue; // Skip animations with < 5% influence

            const time_range = weighted.end_time - weighted.start_time;

            var target_anim_time: f32 = weighted.start_time;

            if (weighted.optional_start > 0.0) {
                const time = (frame_time - weighted.optional_start) + weighted.offset;
                target_anim_time += @min(time, time_range);
            } else {
                target_anim_time += @mod((frame_time + weighted.offset), time_range);
            }

            if (target_anim_time < (weighted.start_time - 0.01)) {
                std.debug.panic(
                    "target_anim_ticks: {d}  less then start_time: {d}",
                    .{ target_anim_time, weighted.start_time - 0.01 },
                );
            }
            if (target_anim_time > (weighted.end_time + 0.01)) {
                std.debug.panic(
                    "target_anim_ticks: {d}  greater then end_time: {d}",
                    .{ target_anim_time, weighted.end_time + 0.01 },
                );
            }

            const node_anim_data = self.animations[weighted.animation_index].node_data;

            for (node_anim_data) |anim_data| {
                const node = &self.nodes[anim_data.node_id];

                const animated_transform = getAnimatedTransform(
                    node.initial_transform,
                    anim_data,
                    target_anim_time,
                );

                if (node.calculated_transform) |*calculated_transform| {
                    const blended_transform = calculated_transform.blendTransforms(animated_transform, weighted.weight);
                    node.calculated_transform = blended_transform;
                } else {
                    node.calculated_transform = animated_transform;
                }
            }
        }
    }

    /// Calculate world transforms for all nodes using Transform operations
    fn calculateWorldTransforms(self: *Self) void {
        if (self.gltf_asset.gltf.nodes == null) return;

        // Calculate world transforms by traversing the scene hierarchy
        for (self.root_nodes) |root_node_index| {
            self.calculateWorldTransformRecursive(root_node_index, Transform.init());
        }
    }

    /// Recursively calculate node transforms with proper parent-child relationships
    fn calculateWorldTransformRecursive(self: *Self, node_index: usize, parent_transform: Transform) void {
        const local_transform = self.nodes[node_index].calculated_transform orelse self.nodes[node_index].initial_transform;
        const wold_transform = parent_transform.composeTransforms(local_transform);

        self.nodes[node_index].calculated_transform = wold_transform;

        if (self.nodes[node_index].children) |children| {
            for (children) |child_index| {
                self.calculateWorldTransformRecursive(child_index, self.nodes[node_index].calculated_transform.?);
            }
        }
    }

    /// Set final matrices for shader rendering
    fn setShaderMatrices(self: *Self) void {
        // Update joint matrices for skinned meshes
        for (0..@min(self.joints.len, MAX_JOINTS)) |i| {
            const joint = self.joints[i];

            if (joint.node_index < self.nodes.len) {
                const node_matrix = self.nodes[joint.node_index].calculated_transform.?.toMatrix();
                self.joint_matrices[i] = node_matrix.mulMat4(&joint.inverse_bind_matrix);
            } else {
                self.joint_matrices[i] = Mat4.identity();
            }
        }

        // Fill remaining slots with identity matrices
        for (self.joints.len..MAX_JOINTS) |i| {
            self.joint_matrices[i] = Mat4.identity();
        }
    }
};

fn getAnimatedTransform(initial_transform: Transform, node_anim: NodeAnimationData, current_time: f32) Transform {
    var transform = initial_transform;

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
fn findKeyframeIndices(times: []const f32, current_time: f32) KeyframeInfo {
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
fn interpolateVec3(
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
fn interpolateQuat(
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

/// Pre-process all animation channels into Animation structs with pre-calculated durations
/// Groups all animation data affecting each node together for better cache locality
fn preprocessAnimationChannels(allocator: Allocator, gltf_asset: *const GltfAsset) ![]Animation {
    if (gltf_asset.gltf.animations) |gltf_animations| {
        var all_animations: []Animation = allocator.alloc(Animation, gltf_animations.len) catch {
            std.debug.panic("Failed to allocate memory for animations\n", .{});
        };

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

            std.debug.print(
                "Pre-processed animation {d} '{s}': {d:.2}s duration, {d} nodes with animation data\n",
                .{ anim_idx, animation_name, max_time, node_channels_list.len },
            );
        }

        return all_animations;
    }

    const all_animations: []Animation = allocator.alloc(Animation, 0) catch {
        std.debug.panic("Failed to allocate memory for animations\n", .{});
    };
    return all_animations;
}

/// Preprocess all glTF nodes into Node structs with transforms extracted from either TRS or matrix
fn preprocessNodes(allocator: Allocator, gltf_asset: *const GltfAsset) []Node {
    if (gltf_asset.gltf.nodes) |gltf_nodes| {
        var nodes = allocator.alloc(Node, gltf_nodes.len) catch {
            std.debug.panic("Failed to allocate memory for nodes\n", .{});
        };

        for (gltf_nodes, 0..) |gltf_node, i| {
            var transform: Transform = undefined;

            if (gltf_node.matrix) |matrix| {
                transform = Transform.fromMatrix(&matrix);
            } else {
                transform = Transform{
                    .translation = gltf_node.translation orelse Vec3.zero(),
                    .rotation = gltf_node.rotation orelse Quat.identity(),
                    .scale = gltf_node.scale orelse Vec3.one(),
                };
            }

            nodes[i] = Node{
                .name = gltf_node.name,
                .children = gltf_node.children,
                .mesh = gltf_node.mesh,
                .skin = gltf_node.skin,
                .initial_transform = transform,
                .calculated_transform = transform,
            };
        }

        std.debug.print("Preprocessed {d} nodes with transform data\n", .{nodes.len});
        return nodes;
    }

    const nodes: []Node = allocator.alloc(Node, 0) catch {
        std.debug.panic("Failed to allocate memory for nodes\n", .{});
    };
    return nodes;
}

/// Preprocess joint data from glTF skin information
fn preprocessJoints(allocator: Allocator, gltf_asset: *const GltfAsset, skin_index: ?u32) !ArrayList(Joint) {
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
            } else {
                // Fallback to identity matrices if no inverse bind matrices provided
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

    return joints;
}

/// Preprocess root nodes by identifying nodes that are not children of other nodes
fn preprocessRootNodes(allocator: Allocator, gltf_asset: *const GltfAsset) !ArrayList(u32) {
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

    return root_nodes_list;
}
