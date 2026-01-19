const std = @import("std");
const glfw = @import("zglfw");
const gl = @import("zopengl").bindings;
const core = @import("core");
const math = @import("math");

const Vec3 = math.Vec3;
const Mat4 = math.Mat4;

const Window = glfw.Window;

const Input = core.Input;
const Camera = core.CameraGimbal;
const Movement = core.Movement;

const Scene = @import("scene/scene.zig").Scene;

// // Bullet system constants
// pub const Spread_Amount: usize = 5; // bullet spread for testing patterns
// pub const Bullet_Scale: f32 = 2.0;
// pub const Bullet_Lifetime: f32 = 8.0;
// pub const Bullet_Speed: f32 = 5.0;
// pub const Rotation_Per_Bullet: f32 = 10.0; // in degrees

pub const MotionType = enum {
    /// Direct movement along camera's local axes (Left, Right, Up, Down)
    translate,
    /// Rotation around target point (OrbitLeft, OrbitRight, OrbitUp, OrbitDown)
    orbit,
    /// Movement around target maintaining height (CircleLeft, CircleRight)
    circle,
    /// In-place rotation (RotateLeft, RotateRight, RotateUp, RotateDown)
    rotate,
    /// Move look view
    look,
};

pub const MotionObject = enum {
    base,
    gimbal,
};

pub const State = struct {
    viewport_width: f32,
    viewport_height: f32,
    scaled_width: f32,
    scaled_height: f32,
    window_scale: [2]f32,
    delta_time: f32,
    total_time: f32,
    input: Input,
    scene: Scene,
    // light_position: Vec3,
    spin: bool = false,
    world_point: ?Vec3,
    motion_type: MotionType = .circle,
    motion_object: MotionObject = .base,
    camera_reposition_requested: bool = false,
    output_position_requested: bool = false,
    screenshot_requested: bool = false,
    run_animation: bool = true,
    reset: bool = false,
    use_camera_view: bool = true,
    const Self = @This();
};
