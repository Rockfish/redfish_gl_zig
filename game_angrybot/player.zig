const std = @import("std");
const core = @import("core");
const math = @import("math");
const world = @import("world.zig");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.AutoArrayHashMap;

const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const vec2 = math.vec2;
const vec3 = math.vec3;
const Mat4 = math.Mat4;

const State = world.State;
const Model = core.Model;
const GltfAsset = core.asset_loader.GltfAsset;
const TextureConfig = core.texture.TextureConfig;
const Shader = core.Shader;
const animation = core.animation;
const Animator = core.Animator;
const AnimationClip = core.AnimationClip;
const AnimationRepeatMode = core.AnimationRepeatMode;
const WeightedAnimation = core.WeightedAnimation;

pub const AnimationName = enum {
    idle,
    right,
    forward,
    back,
    left,
    dead,
};

pub const PlayerAnimations = struct {
    idle: AnimationClip,
    right: AnimationClip,
    forward: AnimationClip,
    back: AnimationClip,
    left: AnimationClip,
    dead: AnimationClip,

    const Self = @This();

    pub fn new() Self {
        // Convert ASSIMP frame-based timing to glTF time-based (assuming 24 FPS)
        const fps = 24.0;
        return .{
            .idle = AnimationClip.init(0, 55.0 / fps, 130.0 / fps, AnimationRepeatMode.Forever),
            .right = AnimationClip.init(0, 184.0 / fps, 204.0 / fps, AnimationRepeatMode.Forever),
            .forward = AnimationClip.init(0, 134.0 / fps, 154.0 / fps, AnimationRepeatMode.Forever),
            .back = AnimationClip.init(0, 159.0 / fps, 179.0 / fps, AnimationRepeatMode.Forever),
            .left = AnimationClip.init(0, 209.0 / fps, 229.0 / fps, AnimationRepeatMode.Forever),
            .dead = AnimationClip.init(0, 234.0 / fps, 293.0 / fps, AnimationRepeatMode.Once),
        };
    }

    pub fn get(self: *Self, name: AnimationName) AnimationClip {
        return switch (name) {
            .idle => self.idle,
            .right => self.right,
            .forward => self.forward,
            .back => self.back,
            .left => self.left,
            .dead => self.dead,
        };
    }
};

pub const AnimationWeights = struct {
    // Previous animation weights
    last_anim_time: f32,
    prev_idle_weight: f32,
    prev_right_weight: f32,
    prev_forward_weight: f32,
    prev_back_weight: f32,
    prev_left_weight: f32,

    const Self = @This();

    fn default() Self {
        return .{
            .last_anim_time = 0.0,
            .prev_idle_weight = 0.0,
            .prev_right_weight = 0.0,
            .prev_forward_weight = 0.0,
            .prev_back_weight = 0.0,
            .prev_left_weight = 0.0,
        };
    }
};

pub const Player = struct {
    allocator: Allocator,
    model: *Model,
    gltf_asset: *GltfAsset, // Keep reference for cleanup
    position: Vec3,
    direction: Vec2,
    speed: f32,
    aim_theta: f32,
    last_fire_time: f32,
    is_trying_to_fire: bool,
    is_alive: bool,
    death_time: f32,
    animation_name: AnimationName,
    animations: PlayerAnimations,
    anim_weights: AnimationWeights,
    anim_hash: HashMap(AnimationName, AnimationClip),

    const Self = @This();

    pub fn deinit(self: *Self) void {
        self.model.deinit();
        self.anim_hash.deinit();
        self.gltf_asset.cleanUp();
        self.allocator.destroy(self.gltf_asset);
        self.allocator.destroy(self);
    }

    pub fn init(allocator: Allocator) !*Self {
        // Modern glTF path instead of .fbx
        const model_path = "angrybots_assets/Models/Player/Player.gltf";

        // Use GltfAsset instead of ModelBuilder
        var gltf_asset = try GltfAsset.init(allocator, "Player", model_path);
        try gltf_asset.load();

        // Define texture configuration (same settings as ASSIMP version)
        const texture_config = TextureConfig{
            .filter = .Linear,
            .flip_v = true,
            .gamma_correction = false,
            .wrap = .Clamp,
        };

        // Modern glTF texture assignment using string uniform names
        try gltf_asset.addTexture("Player", "texture_diffuse", "Textures/Player_D.tga", texture_config);
        try gltf_asset.addTexture("Player", "texture_specular", "Textures/Player_M.tga", texture_config);
        try gltf_asset.addTexture("Player", "texture_emissive", "Textures/Player_E.tga", texture_config);
        try gltf_asset.addTexture("Player", "texture_normal", "Textures/Player_NRM.tga", texture_config);
        try gltf_asset.addTexture("Gun", "texture_diffuse", "Textures/Gun_D.tga", texture_config);
        try gltf_asset.addTexture("Gun", "texture_specular", "Textures/Gun_M.tga", texture_config);
        try gltf_asset.addTexture("Gun", "texture_emissive", "Textures/Gun_E.tga", texture_config);
        try gltf_asset.addTexture("Gun", "texture_normal", "Textures/Gun_NRM.tga", texture_config);

        std.debug.print("Player: glTF asset loaded and configured\n", .{});
        const model = try gltf_asset.buildModel();
        std.debug.print("Player: model built successfully\n", .{});

        // Convert frame-based animation data to time-based for glTF
        const fps = 24.0;
        var anim_hash = HashMap(AnimationName, AnimationClip).init(allocator);
        try anim_hash.put(.idle, AnimationClip.init(0, 55.0 / fps, 130.0 / fps, AnimationRepeatMode.Forever));
        try anim_hash.put(.forward, AnimationClip.init(0, 134.0 / fps, 154.0 / fps, AnimationRepeatMode.Forever));
        try anim_hash.put(.back, AnimationClip.init(0, 159.0 / fps, 179.0 / fps, AnimationRepeatMode.Forever));
        try anim_hash.put(.right, AnimationClip.init(0, 184.0 / fps, 204.0 / fps, AnimationRepeatMode.Forever));
        try anim_hash.put(.left, AnimationClip.init(0, 209.0 / fps, 229.0 / fps, AnimationRepeatMode.Forever));
        try anim_hash.put(.dead, AnimationClip.init(0, 234.0 / fps, 293.0 / fps, AnimationRepeatMode.Once));

        const player = try allocator.create(Player);
        player.* = Player{
            .allocator = allocator,
            .model = model,
            .gltf_asset = gltf_asset,
            .last_fire_time = 0.0,
            .is_trying_to_fire = false,
            .is_alive = true,
            .aim_theta = 0.0,
            .position = vec3(0.0, 0.0, 0.0),
            .direction = vec2(0.0, 0.0),
            .death_time = -1.0,
            .animation_name = .idle,
            .speed = world.PLAYER_SPEED,
            .animations = PlayerAnimations.new(),
            .anim_weights = AnimationWeights.default(),
            .anim_hash = anim_hash,
        };

        // Start with idle animation
        try player.model.animator.playClip(player.animations.idle);
        return player;
    }

    pub fn setAnimation(self: *Self, animation_name: AnimationName, seconds: u32) void {
        _ = seconds; // Not used in current implementation
        if (self.animation_name != animation_name) {
            self.animation_name = animation_name;
            // Could implement animation switching if needed
        }
    }

    pub fn die(self: *Self, time: f32) void {
        self.is_alive = false;
        if (self.death_time < 0.0) {
            self.death_time = time;
        }
    }

    pub fn render(self: *Self, shader: *const Shader) void {
        self.model.render(shader);
    }

    pub fn update(self: *Self, state: *State, aim_theta: f32) !void {
        const weight_animations = self.updateAnimationWeights(self.direction, aim_theta, state.frame_time);
        // Use the new glTF animation blending system
        try self.model.playWeightAnimations(&weight_animations, state.frame_time);
    }

    pub fn getMuzzlePosition(self: *Self, player_transform: *const Mat4) Mat4 {
        _ = self; // Suppress unused parameter warning
        // Simple muzzle offset - adjust these values as needed for gun positioning
        const muzzle_offset = vec3(0.0, 0.8, 1.2); // Forward and up from player center
        const muzzle_translation = Mat4.fromTranslation(&muzzle_offset);
        return player_transform.mulMat4(&muzzle_translation);
    }

    fn updateAnimationWeights(self: *Self, move_vec: Vec2, aim_theta: f32, frame_time: f32) [6]WeightedAnimation {
        const is_moving = move_vec.lengthSquared() > 0.1;
        const move_theta = math.atan(move_vec.x / move_vec.y) + if (move_vec.y < @as(f32, 0.0)) math.pi else @as(f32, 0.0);
        const theta_delta = move_theta - aim_theta;
        const anim_move = vec2(math.sin(theta_delta), math.cos(theta_delta));

        const anim_delta_time = frame_time - self.anim_weights.last_anim_time;
        self.anim_weights.last_anim_time = frame_time;

        const is_dead = self.death_time >= 0.0;

        self.anim_weights.prev_idle_weight = max(0.0, self.anim_weights.prev_idle_weight - anim_delta_time / world.ANIM_TRANSITION_TIME);
        self.anim_weights.prev_right_weight = max(0.0, self.anim_weights.prev_right_weight - anim_delta_time / world.ANIM_TRANSITION_TIME);
        self.anim_weights.prev_forward_weight = max(0.0, self.anim_weights.prev_forward_weight - anim_delta_time / world.ANIM_TRANSITION_TIME);
        self.anim_weights.prev_back_weight = max(0.0, self.anim_weights.prev_back_weight - anim_delta_time / world.ANIM_TRANSITION_TIME);
        self.anim_weights.prev_left_weight = max(0.0, self.anim_weights.prev_left_weight - anim_delta_time / world.ANIM_TRANSITION_TIME);

        var dead_weight: f32 = if (is_dead) @as(f32, 1.0) else @as(f32, 0.0);
        var idle_weight = self.anim_weights.prev_idle_weight + if (is_moving or is_dead) @as(f32, 0.0) else @as(f32, 1.0);
        var right_weight = self.anim_weights.prev_right_weight + if (is_moving) clamp0(-anim_move.x) else @as(f32, 0.0);
        var forward_weight = self.anim_weights.prev_forward_weight + if (is_moving) clamp0(anim_move.y) else @as(f32, 0.0);
        var back_weight = self.anim_weights.prev_back_weight + if (is_moving) clamp0(-anim_move.y) else @as(f32, 0.0);
        var left_weight = self.anim_weights.prev_left_weight + if (is_moving) clamp0(anim_move.x) else @as(f32, 0.0);

        const weight_sum = dead_weight + idle_weight + forward_weight + back_weight + right_weight + left_weight;
        dead_weight /= weight_sum;
        idle_weight /= weight_sum;
        forward_weight /= weight_sum;
        back_weight /= weight_sum;
        right_weight /= weight_sum;
        left_weight /= weight_sum;

        self.anim_weights.prev_idle_weight = max(self.anim_weights.prev_idle_weight, idle_weight);
        self.anim_weights.prev_right_weight = max(self.anim_weights.prev_right_weight, right_weight);
        self.anim_weights.prev_forward_weight = max(self.anim_weights.prev_forward_weight, forward_weight);
        self.anim_weights.prev_back_weight = max(self.anim_weights.prev_back_weight, back_weight);
        self.anim_weights.prev_left_weight = max(self.anim_weights.prev_left_weight, left_weight);

        // Convert frame-based timing to time-based for glTF
        const fps = 24.0;
        return .{
            WeightedAnimation.init(idle_weight, 55.0 / fps, 130.0 / fps, 0.0, 0.0),
            WeightedAnimation.init(forward_weight, 134.0 / fps, 154.0 / fps, 0.0, 0.0),
            WeightedAnimation.init(back_weight, 159.0 / fps, 179.0 / fps, 10.0 / fps, 0.0),
            WeightedAnimation.init(right_weight, 184.0 / fps, 204.0 / fps, 10.0 / fps, 0.0),
            WeightedAnimation.init(left_weight, 209.0 / fps, 229.0 / fps, 0.0, 0.0),
            WeightedAnimation.init(dead_weight, 234.0 / fps, 293.0 / fps, 0.0, self.death_time),
        };
    }
};

fn clamp0(value: f32) f32 {
    if (value < 0.0001) {
        return 0.0;
    }
    return value;
}

fn max(a: f32, b: f32) f32 {
    if (a > b) {
        return a;
    } else {
        return b;
    }
}
