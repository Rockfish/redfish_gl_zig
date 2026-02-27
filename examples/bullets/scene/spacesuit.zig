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
const ResourceManager = core.ResourceManager;

const Shader = core.Shader;
const Shape = core.shapes.Shape;
const Texture = core.texture.Texture;
const uniforms = core.constants.Uniforms;
const RenderContext = core.RenderContext;
const Input = core.Input;
const AnimationRepeatMode = core.AnimationRepeatMode;
const FSM = core.AnimationStateMachine(Animation);

const path = "assets/models/Spacesuit/Spacesuit_converted.gltf";

const Animation = enum(u32) {
    death,
    gun_shoot,
    hit_recieve,
    hit_recieve_2,
    idle,
    idle_gun,
    idle_gun_pointing,
    idle_gun_shoot,
    idle_neutral,
    idle_sword,
    interact,
    kick_left,
    kick_right,
    punch_left,
    punch_right,
    roll,
    run,
    run_back,
    run_left,
    run_right,
    run_shoot,
    sword_slash,
    walk,
    wave,
};

fn buildStateConfigs() [FSM.count]FSM.Config {
    const C = FSM.Config;
    const Forever = AnimationRepeatMode.Forever;
    const Once = AnimationRepeatMode.Once;

    var configs: [FSM.count]C = undefined;

    // Locomotion (looping, interruptible)
    configs[@intFromEnum(Animation.idle)] = .{ .animation_id = 4, .repeat = Forever, .crossfade_in = 0.15, .interruptible = true, .return_state = null };
    configs[@intFromEnum(Animation.walk)] = .{ .animation_id = 22, .repeat = Forever, .crossfade_in = 0.15, .interruptible = true, .return_state = null };
    configs[@intFromEnum(Animation.run)] = .{ .animation_id = 16, .repeat = Forever, .crossfade_in = 0.15, .interruptible = true, .return_state = null };
    configs[@intFromEnum(Animation.run_back)] = .{ .animation_id = 17, .repeat = Forever, .crossfade_in = 0.15, .interruptible = true, .return_state = null };
    configs[@intFromEnum(Animation.run_left)] = .{ .animation_id = 18, .repeat = Forever, .crossfade_in = 0.15, .interruptible = true, .return_state = null };
    configs[@intFromEnum(Animation.run_right)] = .{ .animation_id = 19, .repeat = Forever, .crossfade_in = 0.15, .interruptible = true, .return_state = null };
    configs[@intFromEnum(Animation.run_shoot)] = .{ .animation_id = 20, .repeat = Forever, .crossfade_in = 0.15, .interruptible = true, .return_state = null };

    // Idle variants (looping, interruptible)
    configs[@intFromEnum(Animation.idle_gun)] = .{ .animation_id = 5, .repeat = Forever, .crossfade_in = 0.15, .interruptible = true, .return_state = null };
    configs[@intFromEnum(Animation.idle_gun_pointing)] = .{ .animation_id = 6, .repeat = Forever, .crossfade_in = 0.15, .interruptible = true, .return_state = null };
    configs[@intFromEnum(Animation.idle_gun_shoot)] = .{ .animation_id = 7, .repeat = Forever, .crossfade_in = 0.15, .interruptible = true, .return_state = null };
    configs[@intFromEnum(Animation.idle_neutral)] = .{ .animation_id = 8, .repeat = Forever, .crossfade_in = 0.15, .interruptible = true, .return_state = null };
    configs[@intFromEnum(Animation.idle_sword)] = .{ .animation_id = 9, .repeat = Forever, .crossfade_in = 0.15, .interruptible = true, .return_state = null };

    // One-shot actions (play once, return to idle, not interruptible)
    configs[@intFromEnum(Animation.punch_left)] = .{ .animation_id = 13, .repeat = Once, .crossfade_in = 0.10, .interruptible = false, .return_state = .idle };
    configs[@intFromEnum(Animation.punch_right)] = .{ .animation_id = 14, .repeat = Once, .crossfade_in = 0.10, .interruptible = false, .return_state = .idle };
    configs[@intFromEnum(Animation.kick_left)] = .{ .animation_id = 11, .repeat = Once, .crossfade_in = 0.10, .interruptible = false, .return_state = .idle };
    configs[@intFromEnum(Animation.kick_right)] = .{ .animation_id = 12, .repeat = Once, .crossfade_in = 0.10, .interruptible = false, .return_state = .idle };
    configs[@intFromEnum(Animation.sword_slash)] = .{ .animation_id = 21, .repeat = Once, .crossfade_in = 0.10, .interruptible = false, .return_state = .idle };
    configs[@intFromEnum(Animation.gun_shoot)] = .{ .animation_id = 1, .repeat = Once, .crossfade_in = 0.10, .interruptible = false, .return_state = .idle };
    configs[@intFromEnum(Animation.roll)] = .{ .animation_id = 15, .repeat = Once, .crossfade_in = 0.10, .interruptible = false, .return_state = .idle };
    configs[@intFromEnum(Animation.interact)] = .{ .animation_id = 10, .repeat = Once, .crossfade_in = 0.15, .interruptible = true, .return_state = .idle };
    configs[@intFromEnum(Animation.wave)] = .{ .animation_id = 23, .repeat = Once, .crossfade_in = 0.15, .interruptible = true, .return_state = .idle };

    // Reactions (play once, not interruptible)
    configs[@intFromEnum(Animation.hit_recieve)] = .{ .animation_id = 2, .repeat = Once, .crossfade_in = 0.10, .interruptible = false, .return_state = .idle };
    configs[@intFromEnum(Animation.hit_recieve_2)] = .{ .animation_id = 3, .repeat = Once, .crossfade_in = 0.10, .interruptible = false, .return_state = .idle };
    configs[@intFromEnum(Animation.death)] = .{ .animation_id = 0, .repeat = Once, .crossfade_in = 0.20, .interruptible = false, .return_state = null };

    return configs;
}

pub const Spacesuit = struct {
    model: *core.Model,
    shader: *core.Shader,
    position: Vec3 = vec3(5.0, 0.0, 5.0),
    direction: Vec2 = vec2(0.0, 0.0),
    scale: Vec3 = vec3(0.02, 0.02, 0.02),
    transform: core.Transform = core.Transform.identity(),
    rotation_speed: f32 = 2.0,
    walk_speed: f32 = 0.04,
    run_speed: f32 = 0.10,
    fsm: FSM,

    const Self = @This();

    pub fn init(rm: *ResourceManager) !*Spacesuit {
        const allocator = rm.allocator;

        const shader = try rm.createShader(
            "games/level_01/shaders/animated_pbr.vert",
            "games/level_01/shaders/animated_pbr.frag",
        );

        const model = try rm.loadModel("spacesuit", path);

        const configs = buildStateConfigs();
        var fsm = FSM.init(configs, .idle, model.animator.animations);
        fsm.debug = true;

        const spacesuit = try allocator.create(Spacesuit);
        spacesuit.* = .{
            .model = model,
            .shader = shader,
            .fsm = fsm,
        };

        spacesuit.transform.translation = spacesuit.position;
        spacesuit.transform.scale = spacesuit.scale;

        return spacesuit;
    }

    pub fn update(self: *Self, input: *Input) !void {
        try self.fsm.update(self.model, input.total_time, input.delta_time);
    }

    pub fn updateLights(self: *Self, lights: Lights) void {
        lights.apply(self.shader);
    }

    pub fn draw(self: *Self, ctx: RenderContext) void {
        const model_mat = self.transform.toMatrix();

        self.shader.setMat4(uniforms.Projection_View, &ctx.projection_view);
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
                _ = self.fsm.requestState(.run);
            } else {
                _ = self.fsm.requestState(.walk);
            }
        } else if (input.key_presses.contains(.s)) {
            const fwd = self.transform.forward();
            self.transform.translation = self.transform.translation.add(fwd.mulScalar(self.walk_speed));
            _ = self.fsm.requestState(.run_back);
        } else {
            _ = self.fsm.requestState(.idle);
        }
    }

    fn processOneShotKeys(self: *Self, input: *core.Input) void {
        const one_shot_keys = .{
            .{ .key = .space, .anim = Animation.roll },
            .{ .key = .one, .anim = Animation.punch_left },
            .{ .key = .two, .anim = Animation.punch_right },
            .{ .key = .three, .anim = Animation.kick_left },
            .{ .key = .four, .anim = Animation.kick_right },
            .{ .key = .five, .anim = Animation.sword_slash },
            .{ .key = .six, .anim = Animation.gun_shoot },
        };

        inline for (one_shot_keys) |entry| {
            if (input.key_presses.contains(entry.key) and !input.key_processed.contains(entry.key)) {
                _ = self.fsm.requestState(entry.anim);
            }
        }
    }
};
