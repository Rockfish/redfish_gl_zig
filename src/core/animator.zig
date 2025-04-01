const std = @import("std");
const math = @import("math");
const assimp = @import("assimp.zig");
const ModelBone = @import("model_animation.zig").ModelBone;
const ModelNode = @import("model_animation.zig").ModelNode;
const NodeKeyframes = @import("model_node_keyframes.zig").NodeKeyframes;
const ModelAnimation = @import("model_animation.zig").ModelAnimation;
const Transform = @import("transform.zig").Transform;
const utils = @import("utils/main.zig");
const String = @import("string.zig").String;
const panic = @import("std").debug.panic;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;
const Assimp = assimp.Assimp;

const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const vec2 = math.vec2;
const vec3 = math.vec3;
const vec4 = math.vec4;
const Mat4 = math.Mat4;

pub const MAX_BONES: usize = 100;
pub const MAX_NODES: usize = 100;

// pub const AnimationRepeat = union {
//     Once: void,
//     Count: u32,
//     Forever: void,
// };

pub const AnimationRepeatMode = enum {
    Once,
    Count,
    Forever,
};

pub const AnimationClip = struct {
    id: u32 = 0,
    start_tick: f32,
    end_tick: f32,
    repeat_mode: AnimationRepeatMode,

    pub fn init(start_tick: f32, end_tick: f32, repeat: AnimationRepeatMode) AnimationClip {
        return .{
            .start_tick = start_tick,
            .end_tick = end_tick,
            .repeat_mode = repeat,
        };
    }
};

// An animation that is being faded out as part of a transition (from Bevy)
pub const AnimationTransition = struct {
    allocator: Allocator,
    // The current weight. Starts at 1.0 and goes to 0.0 during the fade-out.
    current_weight: f32,
    // How much to decrease `current_weight` per second
    weight_decline_per_sec: f32,
    // The animation that is being faded out
    animation_state: *AnimationState,

    pub fn deinit(self: *AnimationTransition) void {
        self.allocator.destroy(self.animation_state);
        self.allocator.destroy(self);
    }
};

pub const WeightedAnimation = struct {
    weight: f32,
    start_tick: f32,
    end_tick: f32,
    offset: f32,
    optional_start: f32,

    pub fn init(weight: f32, start_tick: f32, end_tick: f32, offset: f32, optional_start: f32) WeightedAnimation {
        return .{
            .weight = weight,
            .start_tick = start_tick,
            .end_tick = end_tick,
            .offset = offset,
            .optional_start = optional_start, // used for non-looped animations
        };
    }
};

pub const AnimationState = struct {
    animation: *ModelAnimation,
    animation_id: usize,
    start_tick: f32,
    end_tick: f32,
    current_tick: f32,
    ticks_per_second: f32,
    repeat_mode: AnimationRepeatMode,
    repeat_completions: u32,

    pub fn update(self: *AnimationState, delta_time: f32) void {
        if (self.current_tick < 0.0) {
            self.current_tick = self.start_tick;
        }

        self.current_tick += self.ticks_per_second * delta_time;

        if (self.current_tick > self.end_tick) {
            switch (self.repeat_mode) {
                .Once => {
                    self.current_tick = self.end_tick;
                },
                .Count => |_| {},
                .Forever => {
                    self.current_tick = self.start_tick;
                },
            }
        }
    }
};

pub const NodeTransform = struct {
    transform: Transform,
    meshes: *ArrayList(u32),

    pub fn new(transform: Transform, meshes: *ArrayList(u32)) NodeTransform {
        return .{
            .transform = transform,
            .meshes = meshes,
        };
    }
};

pub const Animator = struct {
    allocator: Allocator,

    root_node: *ModelNode,
    global_inverse_transform: Transform,

    animations: *ArrayList(*ModelAnimation),
    animation_state: ?*AnimationState,

    transitions: *ArrayList(?*AnimationTransition),

    bone_map: *StringHashMap(*ModelBone),
    node_transform_map: *StringHashMap(*NodeTransform),

    final_bone_matrices: [MAX_BONES]Mat4,
    final_node_matrices: [MAX_NODES]Mat4,

    const Self = @This();

    pub fn deinit(self: *Self) void {
        var iterator = self.bone_map.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.*.deinit();
        }
        self.bone_map.deinit();
        self.allocator.destroy(self.bone_map);

        self.root_node.deinit();

        for (self.animations.items) |animation| {
            animation.deinit();
        }
        self.animations.deinit();
        self.allocator.destroy(self.animations);

        //self.model_animation.deinit();

        if (self.animation_state) |animation_state| {
            self.allocator.destroy(animation_state);
        }

        for (self.transitions.items) |transition| {
            if (transition) |t| {
                t.deinit();
            }
        }
        self.transitions.deinit();
        self.allocator.destroy(self.transitions);

        var nodeIterator = self.node_transform_map.valueIterator();
        while (nodeIterator.next()) |nodeTransform| {
            self.allocator.destroy(nodeTransform.*);
        }
        self.node_transform_map.deinit();
        self.allocator.destroy(self.node_transform_map);

        self.allocator.destroy(self);
    }

    pub fn init(
        allocator: Allocator,
        root_transform: Mat4,
        root_node: *ModelNode,
        animations: *ArrayList(*ModelAnimation),
        model_bone_map: *StringHashMap(*ModelBone),
    ) !*Self {
        var animation_state: ?*AnimationState = null;
        if (animations.items.len > 0) {
            animation_state = try allocator.create(AnimationState);
            animation_state.?.* = .{
                .animation_id = 0,
                .animation = animations.items[0],
                .start_tick = 0.0,
                .end_tick = animations.items[0].duration,
                .ticks_per_second = animations.items[0].ticks_per_second,
                .current_tick = -1.0,
                .repeat_mode = .Forever,
                .repeat_completions = 0,
            };
        }

        const animator = try allocator.create(Animator);
        animator.* = Animator{
            .allocator = allocator,
            .root_node = root_node,
            .bone_map = model_bone_map,
            .animations = animations,
            .animation_state = animation_state,
            .transitions = try allocator.create(ArrayList(?*AnimationTransition)),
            .node_transform_map = try allocator.create(StringHashMap(*NodeTransform)),
            .global_inverse_transform = Transform.fromMatrix(&Mat4.getInverse(&root_transform)),
            .final_bone_matrices = [_]Mat4{Mat4.identity()} ** MAX_BONES,
            .final_node_matrices = [_]Mat4{Mat4.identity()} ** MAX_NODES,
        };

        animator.transitions.* = ArrayList(?*AnimationTransition).init(allocator);
        animator.node_transform_map.* = StringHashMap(*NodeTransform).init(allocator);

        return animator;
    }

    pub fn playClip(self: *Self, clip: AnimationClip) !void {
        if (self.animation_state) |animation_state| {
            self.allocator.destroy(animation_state);
        }

        if (clip.id < 0 or clip.id > self.animations.items.len) {
            std.debug.panic("Invalid clip id: {d}  num animations: {d}", .{clip.id, self.animations.items.len});
        }

        std.debug.print("playClip name: {s}\n", .{self.animations.items[clip.id].name.str});

        self.animation_state = try self.allocator.create(AnimationState);
        self.animation_state.?.* = .{
            .animation_id = clip.id,
            .animation = self.animations.items[clip.id],
            .ticks_per_second = self.animations.items[clip.id].ticks_per_second,
            .start_tick = 0.0, // clip.start_tick,
            //.end_tick = clip.end_tick,
            .end_tick = self.animations.items[clip.id].duration,
            .repeat_mode = clip.repeat_mode,
            .current_tick = -1.0,
            .repeat_completions = 0,
        };
    }

    pub fn playAnimationById(self: *Self, id: usize) !void {
        if (id < 0 or id >= self.animations.items.len) {
            std.log.warn("Invalid clip id: {d}  num animations: {d}", .{id, self.animations.items.len});
            return;
        }

        if (self.animation_state) |animation_state| {
            self.allocator.destroy(animation_state);
        }

        std.debug.print("playClip name: {s}\n", .{self.animations.items[id].name.str});

        self.animation_state = try self.allocator.create(AnimationState);
        self.animation_state.?.* = .{
            .animation_id = id,
            .animation = self.animations.items[id],
            .ticks_per_second = self.animations.items[id].ticks_per_second,
            .start_tick = 0.0, // clip.start_tick,
            //.end_tick = clip.end_tick,
            .end_tick = self.animations.items[id].duration,
            .repeat_mode = .Forever,
            .current_tick = -1.0,
            .repeat_completions = 0,
        };
    }

    pub fn playClipWithTransition(self: *Self, clip: AnimationClip, transition_duration: f32) !void {
        const previous_animation_state = self.animation_state.?;

        self.animation_state = try self.allocator.create(AnimationState);
        self.animation_state.?.* = .{
            .animation_id = clip.id,
            .animation = self.animations.items[clip.id],
            .ticks_per_second = self.animations.items[clip.id].ticks_per_second,
            .start_tick = clip.start_tick,
            .end_tick = clip.end_tick,
            .current_tick = -1.0,
            .repeat_mode = clip.repeat_mode,
            .repeat_completions = 0,
        };

        const transition = try self.allocator.create(AnimationTransition);
        transition.* = AnimationTransition{
            .allocator = self.allocator,
            .current_weight = 1.0,
            .weight_decline_per_sec = 1.0 / transition_duration,
            .animation_state = previous_animation_state,
        };

        try self.transitions.append(transition);
    }

    pub fn playWeightAnimations(self: *Self, weighted_animation: []const WeightedAnimation, frame_time: f32) !void {
        self.clearNodeTransformMap();

        if (self.animation_state) |animation_state| {
            for (weighted_animation) |weighted| {
                if (weighted.weight == 0.0) {
                    continue;
                }

                const tick_range = weighted.end_tick - weighted.start_tick;

                var target_anim_ticks: f32 = 0.0;

                if (weighted.optional_start > 0.0) {
                    const tick = (frame_time - weighted.optional_start) * animation_state.ticks_per_second + weighted.offset;
                    target_anim_ticks = @min(tick, tick_range);
                } else {
                    target_anim_ticks = @mod((frame_time * animation_state.ticks_per_second + weighted.offset), tick_range);
                }

                target_anim_ticks += weighted.start_tick;

                if ((target_anim_ticks < (weighted.start_tick - 0.01)) or (target_anim_ticks > (weighted.end_tick + 0.01))) {
                    panic("target_anim_ticks out of range: {any}", .{target_anim_ticks});
                }

                try self.calculateTransformMaps(
                    self.root_node,
                    animation_state.animation.node_keyframes,
                    self.node_transform_map,
                    self.global_inverse_transform,
                    target_anim_ticks,
                    weighted.weight,
                );
            }
        }
        try self.updateShaderMatrices();
    }

    pub fn playTick(self: *Self, tick: f32) !void {
        if (self.animation_state) |animation_state| {
            if (tick < animation_state.start_tick) {
                std.debug.print(
                    "tick less than start_tick. Setting to start_tick. start_tick: {d} tick: {d}\n",
                    .{ animation_state.start_tick, tick },
                );
                self.animation_state.?.current_tick = self.animation_state.?.start_tick;
            } else if (tick < animation_state.start_tick or tick > animation_state.end_tick) {
                std.debug.print(
                    "tick greater than end_tick. Setting to end_tick. end_tick: {d} tick: {d}\n",
                    .{ animation_state.end_tick, tick },
                );
                animation_state.current_tick = animation_state.end_tick;
            } else {
                animation_state.current_tick = tick;
            }
        }
        try self.updateNodeTransformations(0.0);
        try self.updateShaderMatrices();
    }

    pub fn updateAnimation(self: *Self, delta_time: f32) !void {
        if (self.animation_state) |animation_state| {
            animation_state.update(delta_time);
        }
        try self.updateTransitions(delta_time);
        try self.updateNodeTransformations(delta_time);
        try self.updateShaderMatrices();
    }

    const HasCurrentWeightFilter = struct {
        pub fn predicate(self: *const HasCurrentWeightFilter, animation: *AnimationTransition) bool {
            _ = self;
            return animation.current_weight > 0.0;
        }
    };

    fn updateTransitions(self: *Self, delta_time: f32) !void {
        for (self.transitions.items) |transition| {
            transition.?.current_weight -= transition.?.weight_decline_per_sec * delta_time;
        }
        const filter = HasCurrentWeightFilter{};
        try utils.retain(*AnimationTransition, HasCurrentWeightFilter, self.transitions, filter);
    }

    fn updateNodeTransformations(self: *Self, delta_time: f32) !void {
        self.clearNodeTransformMap();

        if (self.animation_state) |animation_state| {
            // First for current animation at weight 1.0
            try self.calculateTransformMaps(
                self.root_node,
                animation_state.animation.node_keyframes,
                self.node_transform_map,
                self.global_inverse_transform,
                self.animation_state.?.current_tick,
                1.0,
            );

            for (self.transitions.items) |transition| {
                transition.?.animation_state.update(delta_time);
                // std.debug.print("transition = {any}\n", .{transition});
                try self.calculateTransformMaps(
                    self.root_node,
                    animation_state.animation.node_keyframes,
                    self.node_transform_map,
                    self.global_inverse_transform,
                    transition.?.animation_state.current_tick,
                    transition.?.current_weight,
                );
            }
        }
    }

    pub fn calculateTransformMaps(
        self: *Self,
        node_data: *ModelNode,
        node_animations: *ArrayList(*NodeKeyframes),
        node_map: *StringHashMap(*NodeTransform),
        parent_transform: Transform,
        current_tick: f32,
        weight: f32,
    ) !void {
        const global_transformation = try self.calculateTransform(
            node_data,
            node_animations,
            node_map,
            parent_transform,
            current_tick,
            weight,
        );
        // std.debug.print("calculate_transform_maps  node_data.name = {s}  parent_transform = {any}  global_transform = {any}\n", .{node_data.name.str, parent_transform, global_transformation});

        for (node_data.children.items) |child_node| {
            try self.calculateTransformMaps(
                child_node,
                node_animations,
                node_map,
                global_transformation,
                current_tick,
                weight,
            );
        }
    }

    fn calculateTransform(
        self: *Self,
        node_data: *ModelNode,
        node_animations: *ArrayList(*NodeKeyframes),
        node_map: *StringHashMap(*NodeTransform),
        parent_transform: Transform,
        current_tick: f32,
        weight: f32,
    ) !Transform {
        var global_transform: Transform = undefined;

        const node_keyframes = getNodeKeyframes(node_animations, node_data.node_name);

        if (node_keyframes) |keyframes| {
            const node_transform = keyframes.getAnimationTransform(current_tick);
            // if (node_transform.scale.x < 0.9 or node_transform.scale.y < 0.9 or node_transform.scale.z < 0.9) {
            //     std.log.debug("node_transform: tick: {d} {any}", .{current_tick, node_transform});
            // }
            global_transform = parent_transform.mulTransform(node_transform);
        } else {
            global_transform = parent_transform.mulTransform(node_data.transform);
        }

        const node_entry = try node_map.getOrPut(node_data.node_name.str);

        if (node_entry.found_existing) {
            //std.debug.print("old transform: {any}\n", .{result.value_ptr.*.transform});
            node_entry.value_ptr.*.transform = node_entry.value_ptr.*.transform.mulTransformWeighted(global_transform, weight);
            //std.debug.print("new transform: {any}\n\n", .{result.value_ptr.*.transform});
        } else {
            const node_transform_ptr = try self.allocator.create(NodeTransform);
            node_transform_ptr.* = NodeTransform.new(global_transform, node_data.meshes);
            node_entry.value_ptr.* = node_transform_ptr;
            //std.debug.print("first transform: {any}\n\n", .{node_transform_ptr});
        }

        return global_transform;
    }

    fn updateShaderMatrices(self: *Self) !void {
        var iterator = self.node_transform_map.iterator();
        while (iterator.next()) |entry| {
            const node_name = entry.key_ptr.*;
            const node_transform = entry.value_ptr.*;

            if (self.bone_map.get(node_name)) |bone| {
                const transform = node_transform.transform.mulTransform(bone.offset_transform);
                self.final_bone_matrices[bone.bone_index] = transform.getMatrix();
            }

            for (node_transform.meshes.items) |mesh_index| {
                self.final_node_matrices[mesh_index] = node_transform.transform.getMatrix();
            }
        }
    }

    fn clearNodeTransformMap(self: *Self) void {
        var iterator = self.node_transform_map.valueIterator();
        while (iterator.next()) |node_transform| {
            node_transform.*.transform.clear();
        }
    }
};

fn getNodeKeyframes(node_keyframes: *ArrayList(*NodeKeyframes), node_name: *String) ?*NodeKeyframes {
    for (node_keyframes.items) |keyframe| {
        if (keyframe.node_name.equals(node_name)) {
            return keyframe;
        }
    }
    return null;
}
