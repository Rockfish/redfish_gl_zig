const std = @import("std");
const math = @import("math");

pub const Vec3 = math.Vec3;
pub const vec3 = math.vec3;
pub const Mat4 = math.Mat4;
pub const Quat = math.Quat;
pub const Transform = @import("transform.zig").Transform;

pub const MovementDirection = enum {
    forward,
    backward,
    left,
    right,
    up,
    down,
    rotate_right,
    rotate_left,
    rotate_up,
    rotate_down,
    roll_right,
    roll_left,
    radius_in,
    radius_out,
    orbit_up,
    orbit_down,
    orbit_left,
    orbit_right,
    circle_right,
    circle_left,
    circle_up, // always cross the pole
    circle_down,
};

const world_up = Vec3.init(0.0, 1.0, 0.0);
const half_pi = math.pi / 2.0;
const POSITION_EPSILON: f32 = 0.0001;
const AXIS_EPSILON: f32 = 1e-6;

/// Movement controller system with Transform-based orientation.
///
/// Movement wraps a Transform to provide high-level camera/object control.
/// It maintains a target point for "look at" behavior and provides various
/// movement modes:
/// - Translation: forward/backward, left/right, up/down
/// - Rotation: rotate target around position (first-person style)
/// - Roll: rotate around forward axis
/// - Orbit: rotate position around target (third-person style)
/// - Circle: orbit using world-up axis, allowing pole crossing
/// - Radius: adjust distance to target
///
/// Orientation is maintained by Transform's quaternion-based rotation,
/// eliminating the need for manual basis vector re-orthogonalization.
/// The `update_tick` counter increments on any state change for tracking
/// when updates occur.
pub const Movement = struct {
    transform: Transform,
    target: Vec3,
    world_up: Vec3 = world_up,
    translate_speed: f32 = 50.0,
    rotation_speed: f32 = 50.0,
    orbit_speed: f32 = 50.0,
    direction: MovementDirection = .forward,
    update_tick: u64 = 0,

    const Self = @This();

    pub fn init(position: Vec3, target: Vec3) Movement {
        var transform = Transform.fromTranslation(position);
        transform.lookAt(target, world_up);
        return Movement{
            .transform = transform,
            .target = target,
        };
    }

    pub fn reset(self: *Self, position: Vec3, target: Vec3) void {
        self.transform.translation = position;
        self.transform.lookAt(target, self.world_up);
        self.target = target;
        self.update_tick +%= 1;
    }

    pub fn translate(self: *Self, offset: Vec3) void {
        self.transform.translation = self.transform.translation.add(&offset);
        self.update_tick +%= 1;
    }

    pub fn getPosition(self: *const Self) Vec3 {
        return self.transform.translation;
    }

    pub fn getTarget(self: *const Self) Vec3 {
        return self.target;
    }

    pub fn getUpdateTick(self: *const Self) u64 {
        return self.update_tick;
    }

    pub fn getTransform(self: *const Self) *const Transform {
        return &self.transform;
    }

    /// Returns a transformation matrix representing the local coordinate frame.
    ///
    /// The returned matrix transforms from local space to world space, with:
    /// - Column 0: right vector (local X-axis)
    /// - Column 1: up vector (local Y-axis)
    /// - Column 2: -forward vector (local Z-axis, negated for OpenGL convention)
    /// - Column 3: position (translation/origin)
    ///
    /// This matrix can be used to orient objects (like bullets or projectiles)
    /// according to the current view direction and position.
    pub fn getTransformMatrix(self: *const Self) Mat4 {
        return self.transform.toMatrix();
    }

    /// Rotate position around target, preserving exact radius
    fn rotatePositionAroundTarget(self: *Self, rotation: Quat) void {
        const radius_vec = self.transform.translation.sub(&self.target);
        const target_radius = radius_vec.length();
        const rotated_position = rotation.rotateVec(&radius_vec);
        self.transform.translation = self.target.add(&rotated_position.toNormalized().mulScalar(target_radius));
        self.update_tick +%= 1;
    }

    /// Rotate target around position, preserving exact distance
    fn rotateTargetAroundPosition(self: *Self, rotation: Quat) void {
        const target_vec = self.target.sub(&self.transform.translation);
        const target_distance = target_vec.length();
        const rotated_target = rotation.rotateVec(&target_vec);
        self.target = self.transform.translation.add(&rotated_target.toNormalized().mulScalar(target_distance));
        self.update_tick +%= 1;
    }

    pub fn processMovement(
        self: *Self,
        direction: MovementDirection,
        delta_time: f32,
    ) void {
        self.update_tick +%= 1;
        // if (self.direction != direction) {
        //     std.debug.print("direction: {any}\n", .{direction});
        // }
        self.direction = direction;
        const translation_velocity = self.translate_speed * delta_time;
        const rot_angle = math.degreesToRadians(self.rotation_speed * delta_time);
        const orbit_angle = math.degreesToRadians(self.orbit_speed * delta_time);

        switch (direction) {
            .forward => {
                const fwd = self.transform.forward();
                self.transform.translation = self.transform.translation.add(&fwd.mulScalar(translation_velocity));
            },
            .backward => {
                const fwd = self.transform.forward();
                self.transform.translation = self.transform.translation.sub(&fwd.mulScalar(translation_velocity));
            },
            .left => {
                const right_vec = self.transform.right();
                self.transform.translation = self.transform.translation.sub(&right_vec.mulScalar(translation_velocity));
            },
            .right => {
                const right_vec = self.transform.right();
                self.transform.translation = self.transform.translation.add(&right_vec.mulScalar(translation_velocity));
            },
            .up => {
                const up_vec = self.transform.up();
                self.transform.translation = self.transform.translation.add(&up_vec.mulScalar(translation_velocity));
            },
            .down => {
                const up_vec = self.transform.up();
                self.transform.translation = self.transform.translation.sub(&up_vec.mulScalar(translation_velocity));
            },
            .rotate_right => {
                const up_vec = self.transform.up();
                const rot = Quat.fromAxisAngle(&up_vec, -rot_angle);
                self.transform.rotate(rot);
                self.rotateTargetAroundPosition(rot);
            },
            .rotate_left => {
                const up_vec = self.transform.up();
                const rot = Quat.fromAxisAngle(&up_vec, rot_angle);
                self.transform.rotate(rot);
                self.rotateTargetAroundPosition(rot);
            },
            .rotate_up => {
                const right_vec = self.transform.right();
                const rot = Quat.fromAxisAngle(&right_vec, rot_angle);
                self.transform.rotate(rot);
                self.rotateTargetAroundPosition(rot);
            },
            .rotate_down => {
                const right_vec = self.transform.right();
                const rot = Quat.fromAxisAngle(&right_vec, -rot_angle);
                self.transform.rotate(rot);
                self.rotateTargetAroundPosition(rot);
            },
            .roll_right => {
                const fwd = self.transform.forward();
                const rot = Quat.fromAxisAngle(&fwd, rot_angle);
                self.transform.rotate(rot);
            },
            .roll_left => {
                const fwd = self.transform.forward();
                const rot = Quat.fromAxisAngle(&fwd, -rot_angle);
                self.transform.rotate(rot);
            },
            .radius_in => {
                const to_target = self.target.sub(&self.transform.translation);
                const dist = to_target.length();
                if (dist > POSITION_EPSILON) {
                    const max_step = dist - POSITION_EPSILON;
                    const step = @min(translation_velocity, max_step);
                    if (step > 0.0) {
                        const dir = to_target.mulScalar(1.0 / dist);
                        self.transform.translation = self.transform.translation.add(&dir.mulScalar(step));
                    }
                }
            },
            .radius_out => {
                const dir = self.target.sub(&self.transform.translation).toNormalized();
                self.transform.translation = self.transform.translation.sub(&dir.mulScalar(translation_velocity));
            },
            .orbit_right => {
                const up_vec = self.transform.up();
                const rot = Quat.fromAxisAngle(&up_vec, orbit_angle);
                self.rotatePositionAroundTarget(rot);
                self.transform.rotate(rot);
            },
            .orbit_left => {
                const up_vec = self.transform.up();
                const rot = Quat.fromAxisAngle(&up_vec, -orbit_angle);
                self.rotatePositionAroundTarget(rot);
                self.transform.rotate(rot);
            },
            .orbit_up => {
                const right_vec = self.transform.right();
                const rot = Quat.fromAxisAngle(&right_vec, -orbit_angle);
                self.rotatePositionAroundTarget(rot);
                self.transform.rotate(rot);
            },
            .orbit_down => {
                const right_vec = self.transform.right();
                const rot = Quat.fromAxisAngle(&right_vec, orbit_angle);
                self.rotatePositionAroundTarget(rot);
                self.transform.rotate(rot);
            },
            .circle_right => {
                const rot = Quat.fromAxisAngle(&self.world_up, orbit_angle);
                self.rotatePositionAroundTarget(rot);
                self.transform.lookAt(self.target, self.world_up);
            },
            .circle_left => {
                const rot = Quat.fromAxisAngle(&self.world_up, -orbit_angle);
                self.rotatePositionAroundTarget(rot);
                self.transform.lookAt(self.target, self.world_up);
            },
            .circle_up => {
                // Choose rotation axis - use right vector, or fallback if at pole
                var rotation_axis = self.transform.right();
                if (rotation_axis.lengthSquared() < AXIS_EPSILON) {
                    // At pole: use a stable horizontal axis
                    rotation_axis = vec3(1.0, 0.0, 0.0);
                }
                const rot = Quat.fromAxisAngle(&rotation_axis, -orbit_angle);
                self.rotatePositionAroundTarget(rot);
                self.transform.lookAt(self.target, self.world_up);
            },
            .circle_down => {
                // Choose rotation axis - use right vector, or fallback if at pole
                var rotation_axis = self.transform.right();
                if (rotation_axis.lengthSquared() < AXIS_EPSILON) {
                    // At pole: use a stable horizontal axis
                    rotation_axis = vec3(1.0, 0.0, 0.0);
                }
                const rot = Quat.fromAxisAngle(&rotation_axis, orbit_angle);
                self.rotatePositionAroundTarget(rot);
                self.transform.lookAt(self.target, self.world_up);
            },
        }
    }

    pub fn processMouseMovement(self: *Self, xoffset_in: f32, yoffset_in: f32, constrain_pitch: bool) void {
        _ = xoffset_in;
        _ = yoffset_in;
        _ = constrain_pitch;
        self.update_tick +%= 1;
    }

    pub fn printState(self: *Self) void {
        var position_buf: [100]u8 = undefined;
        var target_buf: [100]u8 = undefined;
        var forward_buf: [100]u8 = undefined;
        var up_buf: [100]u8 = undefined;
        var right_buf: [100]u8 = undefined;
        const fwd = self.transform.forward();
        const up_vec = self.transform.up();
        const right_vec = self.transform.right();
        std.debug.print("Position: {s}\n", .{self.transform.translation.asString(&position_buf)});
        std.debug.print("Target: {s}\n", .{self.target.asString(&target_buf)});
        std.debug.print("Forward: {s}\n", .{fwd.asString(&forward_buf)});
        std.debug.print("Up: {s}\n", .{up_vec.asString(&up_buf)});
        std.debug.print("Right: {s}\n", .{right_vec.asString(&right_buf)});
    }

    /// Test helper function: converts angle to delta_time for movement testing
    /// Only used by test code - prefer processMovement() with real delta_time for production
    pub fn update(self: *Self, angle: f32, direction: MovementDirection) void {
        const angle_degrees = math.radiansToDegrees(angle);
        const delta_time = angle_degrees / self.orbit_speed;
        self.processMovement(direction, delta_time);
    }
};

test "orbit right full circle return" {
    const target = Vec3.init(0.0, 0.0, 0.0);
    const radius: f32 = 10.0;
    const position = Vec3.init(radius, 0.0, 0.0); // Simple horizontal start
    var movement = Movement.init(position, target);
    const start_pos = position.clone();
    const steps = 72;
    const step_angle = math.degreesToRadians(5.0);
    const epsilon = 0.001;
    for (0..steps) |i| {
        movement.update(step_angle, .orbit_right);
        if (i % 18 == 0) {
            std.debug.print("\nStep {d}:\n", .{i});
            movement.printState();
            const current_radius = movement.transform.translation.sub(&target).length();
            try std.testing.expectApproxEqAbs(current_radius, radius, epsilon);
            const translated_position = movement.transform.translation.sub(&target);
            const translated_position_norm = translated_position.toNormalized();
            const up_vec = movement.transform.up();
            const dot_with_up = translated_position_norm.dot(&up_vec);
            try std.testing.expectApproxEqAbs(dot_with_up, 0.0, epsilon);
        }
    }
    try std.testing.expectApproxEqAbs(movement.transform.translation.x, start_pos.x, epsilon);
    try std.testing.expectApproxEqAbs(movement.transform.translation.y, start_pos.y, epsilon);
    try std.testing.expectApproxEqAbs(movement.transform.translation.z, start_pos.z, epsilon);
}

test "rotate right motion" {
    const position = Vec3.init(10.0, 0.0, 0.0);
    const target = Vec3.init(0.0, 0.0, 0.0);
    var movement = Movement.init(position, target);
    const start_target = target.clone();
    const steps = 12;
    const step_angle = math.degreesToRadians(30.0);
    const epsilon = 0.001;
    for (0..steps) |_| {
        movement.update(step_angle, .rotate_right);
    }
    // After 360 degrees, target should return to start
    try std.testing.expectApproxEqAbs(movement.target.x, start_target.x, epsilon);
    try std.testing.expectApproxEqAbs(movement.target.y, start_target.y, epsilon);
    try std.testing.expectApproxEqAbs(movement.target.z, start_target.z, epsilon);
    // Position should remain unchanged
    try std.testing.expectApproxEqAbs(movement.transform.translation.x, position.x, epsilon);
    try std.testing.expectApproxEqAbs(movement.transform.translation.y, position.y, epsilon);
    try std.testing.expectApproxEqAbs(movement.transform.translation.z, position.z, epsilon);
}

test "backward translation updates forward" {
    const position = Vec3.init(0.0, 0.0, 10.0);
    const target = Vec3.init(0.0, 0.0, 0.0);
    var movement = Movement.init(position, target);

    const dt: f32 = 0.1; // arbitrary
    movement.processMovement(.backward, dt);

    // forward should always equal normalized (target - position)
    const expected_forward = movement.target.sub(&movement.transform.translation).toNormalized();
    const actual_forward = movement.transform.forward();
    const eps = 0.0001;
    try std.testing.expectApproxEqAbs(actual_forward.x, expected_forward.x, eps);
    try std.testing.expectApproxEqAbs(actual_forward.y, expected_forward.y, eps);
    try std.testing.expectApproxEqAbs(actual_forward.z, expected_forward.z, eps);
}

test "radius in clamps near target" {
    const target = Vec3.init(0.0, 0.0, 0.0);
    var movement = Movement.init(Vec3.init(2.0, 0.0, 0.0), target);

    // Choose dt large enough to overshoot without clamping
    const dt: f32 = 10.0;
    movement.processMovement(.radius_in, dt);

    const dist = movement.transform.translation.sub(&target).length();
    // Expect we stop close to POSITION_EPSILON distance
    const tol: f32 = 1e-4;
    try std.testing.expect(dist <= POSITION_EPSILON + tol);
    try std.testing.expect(dist >= 0.0);

    // forward stays well-defined (no NaNs)
    const fwd = movement.transform.forward();
    try std.testing.expect(!std.math.isNan(fwd.x) and !std.math.isNan(fwd.y) and !std.math.isNan(fwd.z));
}

test "circle up/down works near pole" {
    const radius: f32 = 5.0;
    const target = Vec3.init(0.0, 0.0, 0.0);
    // Position directly below target so forward points exactly up
    var movement = Movement.init(Vec3.init(0.0, -radius, 0.0), target);

    const start_pos_up = movement.transform.translation.clone();
    const step_angle = math.degreesToRadians(15.0);
    movement.update(step_angle, .circle_up);

    // Should have moved and stayed on the same radius
    const new_radius_up = movement.transform.translation.sub(&target).length();
    const eps = 1e-3;
    try std.testing.expect(new_radius_up > 0.0);
    try std.testing.expect(new_radius_up <= radius + eps and new_radius_up >= radius - eps);
    try std.testing.expect(!(movement.transform.translation.x == start_pos_up.x and movement.transform.translation.y == start_pos_up.y and movement.transform.translation.z == start_pos_up.z));
    try std.testing.expect(!std.math.isNan(movement.transform.translation.x) and !std.math.isNan(movement.transform.translation.y) and !std.math.isNan(movement.transform.translation.z));

    // Now try circle down from top pole
    movement.reset(Vec3.init(0.0, radius, 0.0), target);
    const start_pos_down = movement.transform.translation.clone();
    movement.update(step_angle, .circle_down);
    const new_radius_down = movement.transform.translation.sub(&target).length();
    try std.testing.expect(new_radius_down > 0.0);
    try std.testing.expect(new_radius_down <= radius + eps and new_radius_down >= radius - eps);
    try std.testing.expect(!(movement.transform.translation.x == start_pos_down.x and movement.transform.translation.y == start_pos_down.y and movement.transform.translation.z == start_pos_down.z));
    try std.testing.expect(!std.math.isNan(movement.transform.translation.x) and !std.math.isNan(movement.transform.translation.y) and !std.math.isNan(movement.transform.translation.z));
}
