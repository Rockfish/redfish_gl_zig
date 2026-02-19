const std = @import("std");
const core = @import("core");
const math = @import("math");

const Lights = @import("lights.zig").Lights;

const Vec2 = math.Vec2;
const vec2 = math.vec2;
const Vec3 = math.Vec3;
const vec3 = math.vec3;
const Vec4 = math.Vec4;
const Mat4 = math.Mat4;
const Quat = math.Quat;
const quat = math.quat;

const Allocator = std.mem.Allocator;

const Shader = core.Shader;
const Shape = core.shapes.Shape;
const Texture = core.texture.Texture;
const uniforms = core.constants.Uniforms;
const Input = core.Input;
const AnimationRepeatMode = core.AnimationRepeatMode;
const FSM = core.AnimationStateMachine(Animation);

const path_soldier = "assets/toon_shooter_kit/Characters/glTF/Character_Soldier.gltf";
const path_enemy = "assets/toon_shooter_kit/Characters/glTF/Character_Enemy.gltf";
const path_hazmat = "assets/toon_shooter_kit/Characters/glTF/Character_Hazmat.gltf";

const Animation = enum(u32) {
    death,
    duck,
    hit_react,
    idle,
    idle_shoot,
    jump,
    jump_idle,
    jump_land,
    no,
    punch,
    run,
    run_gun,
    run_shoot,
    walk,
    walk_shoot,
    wave,
    yes,
};

const Weapon = enum {
    AK,
    GrenadeLauncher,
    Knife_1,
    Knife_2,
    Pistol,
    Revolver,
    Revolver_Small,
    RocketLauncher,
    ShortCannon,
    Shotgun,
    Shovel,
    SMG,
    Sniper,
    Sniper_2,
};

pub const ToonSoldier = struct {
    model: *core.Model,
    shader: *core.Shader,
    position: Vec3 = vec3(0.0, 0.0, 3.0),
    direction: Vec2 = vec2(0.0, 0.0),
    scale: Vec3 = vec3(1.0, 1.0, 1.0),
    transform: core.Transform = core.Transform.identity(),
    rotation_speed: f32 = 2.0,
    walk_speed: f32 = 0.04,
    run_speed: f32 = 0.10,
    fsm: FSM,
    current_weapon: Weapon = .ShortCannon,

    const Self = @This();

    pub fn init(allocator: Allocator) !*ToonSoldier {
        const shader = try core.Shader.init(
            allocator,
            "games/level_01/shaders/animated_pbr.vert",
            "games/level_01/shaders/animated_pbr.frag",
        );

        var gltf_asset = try core.asset_loader.GltfAsset.init(allocator, "spacesuit", path_enemy);
        try gltf_asset.load();

        const model = try gltf_asset.buildModel();

        const configs = buildStateConfigs();
        var fsm = FSM.init(configs, .idle, model.animator.animations);
        fsm.debug = true;

        const soldier = try allocator.create(ToonSoldier);
        soldier.* = .{
            .model = model,
            .shader = shader,
            .fsm = fsm,
        };

        soldier.transform.translation = soldier.position;
        soldier.transform.scale = soldier.scale;
        soldier.equipWeapon(soldier.current_weapon);

        return soldier;
    }

    pub fn equipWeapon(self: *Self, weapon: Weapon) void {
        // Hide all weapons
        inline for (std.meta.fields(Weapon)) |field| {
            self.model.setNodeVisibility(field.name, false);
        }
        // Show the selected weapon
        self.model.setNodeVisibility(@tagName(weapon), true);
        self.current_weapon = weapon;
    }

    pub fn update(self: *Self, input: *Input) !void {
        try self.fsm.update(self.model, input.total_time, input.delta_time);
    }

    pub fn updateLights(self: *Self, lights: Lights) void {
        self.shader.setVec3(uniforms.Ambient_Color, lights.ambient_color);
        self.shader.setVec3(uniforms.Light_Color, lights.light_color);
        self.shader.setVec3(uniforms.Light_Direction, lights.light_direction);
    }

    pub fn draw(self: *Self, projection: *const Mat4, view: *const Mat4) void {
        const model_mat = self.transform.toMatrix();

        self.shader.setMat4(uniforms.Mat_Projection, projection);
        self.shader.setMat4(uniforms.Mat_View, view);
        self.shader.setMat4(uniforms.Mat_Model, &model_mat);
        self.model.draw(self.shader);
    }

    pub fn processInput(self: *Self, input: *core.Input) !void {
        const dt = input.delta_time;

        // One-shot actions (highest priority, checked with key_processed for single-fire)
        self.processOneShotKeys(input);

        // Rotation (A/D)
        if (input.key_presses.contains(.a)) {
            self.transform.rotateAxis(vec3(0.0, 1.0, 0.0), self.rotation_speed * dt);
        }
        if (input.key_presses.contains(.d)) {
            self.transform.rotateAxis(vec3(0.0, 1.0, 0.0), -self.rotation_speed * dt);
        }

        // Locomotion
        if (input.key_presses.contains(.w)) {
            const is_running = input.key_shift;
            const speed = if (is_running) self.run_speed else self.walk_speed;
            const fwd = self.transform.forward();
            self.transform.translation = self.transform.translation.sub(fwd.mulScalar(speed));

            if (is_running) {
                _ = self.fsm.requestState(.run_shoot);
            } else {
                _ = self.fsm.requestState(.walk);
            }
        } else if (input.key_presses.contains(.s)) {
            const fwd = self.transform.forward();
            self.transform.translation = self.transform.translation.add(fwd.mulScalar(self.walk_speed));
            _ = self.fsm.requestState(.walk);
        } else {
            _ = self.fsm.requestState(.idle);
        }
    }

    fn processOneShotKeys(self: *Self, input: *core.Input) void {
        const one_shot_keys = .{
            .{ .key = .space, .anim = Animation.jump },
            .{ .key = .one, .anim = Animation.punch },
            .{ .key = .two, .anim = Animation.duck },
            .{ .key = .three, .anim = Animation.wave },
            .{ .key = .four, .anim = Animation.yes },
            .{ .key = .five, .anim = Animation.no },
            .{ .key = .six, .anim = Animation.walk_shoot },
            .{ .key = .seven, .anim = Animation.run_shoot },
        };

        inline for (one_shot_keys) |entry| {
            if (input.key_presses.contains(entry.key) and !input.key_processed.contains(entry.key)) {
                _ = self.fsm.requestState(entry.anim);
            }
        }
    }
};

fn buildStateConfigs() [FSM.count]FSM.Config {
    const C = FSM.Config;
    const Forever = AnimationRepeatMode.Forever;
    const Once = AnimationRepeatMode.Once;

    var configs: [FSM.count]C = undefined;

    // Locomotion (looping, interruptible)
    configs[@intFromEnum(Animation.idle)] = .{ .animation_id = 3, .repeat = Forever, .crossfade_in = 0.15, .interruptible = true, .return_state = null };
    configs[@intFromEnum(Animation.walk)] = .{ .animation_id = 13, .repeat = Forever, .crossfade_in = 0.15, .interruptible = true, .return_state = null };
    configs[@intFromEnum(Animation.run)] = .{ .animation_id = 10, .repeat = Forever, .crossfade_in = 0.15, .interruptible = true, .return_state = null };
    configs[@intFromEnum(Animation.run_gun)] = .{ .animation_id = 11, .repeat = Forever, .crossfade_in = 0.15, .interruptible = true, .return_state = null };
    configs[@intFromEnum(Animation.run_shoot)] = .{ .animation_id = 12, .repeat = Forever, .crossfade_in = 0.15, .interruptible = true, .return_state = null };
    configs[@intFromEnum(Animation.walk_shoot)] = .{ .animation_id = 14, .repeat = Forever, .crossfade_in = 0.15, .interruptible = true, .return_state = null };

    // Idle variants (looping, interruptible)
    configs[@intFromEnum(Animation.idle_shoot)] = .{ .animation_id = 4, .repeat = Forever, .crossfade_in = 0.15, .interruptible = true, .return_state = null };
    configs[@intFromEnum(Animation.jump_idle)] = .{ .animation_id = 6, .repeat = Forever, .crossfade_in = 0.15, .interruptible = true, .return_state = null };

    // One-shot actions (play once, return to idle, not interruptible)
    configs[@intFromEnum(Animation.punch)] = .{ .animation_id = 9, .repeat = Once, .crossfade_in = 0.10, .interruptible = false, .return_state = .idle };
    configs[@intFromEnum(Animation.jump)] = .{ .animation_id = 5, .repeat = Once, .crossfade_in = 0.10, .interruptible = false, .return_state = .idle };
    configs[@intFromEnum(Animation.jump_land)] = .{ .animation_id = 7, .repeat = Once, .crossfade_in = 0.10, .interruptible = false, .return_state = .idle };
    configs[@intFromEnum(Animation.duck)] = .{ .animation_id = 1, .repeat = Once, .crossfade_in = 0.10, .interruptible = false, .return_state = .idle };
    configs[@intFromEnum(Animation.wave)] = .{ .animation_id = 15, .repeat = Once, .crossfade_in = 0.15, .interruptible = true, .return_state = .idle };
    configs[@intFromEnum(Animation.yes)] = .{ .animation_id = 16, .repeat = Once, .crossfade_in = 0.15, .interruptible = true, .return_state = .idle };
    configs[@intFromEnum(Animation.no)] = .{ .animation_id = 8, .repeat = Once, .crossfade_in = 0.15, .interruptible = true, .return_state = .idle };

    // Reactions (play once, not interruptible)
    configs[@intFromEnum(Animation.hit_react)] = .{ .animation_id = 2, .repeat = Once, .crossfade_in = 0.10, .interruptible = false, .return_state = .idle };
    configs[@intFromEnum(Animation.death)] = .{ .animation_id = 0, .repeat = Once, .crossfade_in = 0.20, .interruptible = false, .return_state = null };

    return configs;
}
