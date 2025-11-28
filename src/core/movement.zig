const std = @import("std");
const math = @import("math");

pub const Vec3 = math.Vec3;
pub const vec3 = math.vec3;
pub const Quat = math.Quat;

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

pub const Movement = struct {
    position: Vec3,
    target: Vec3,
    up: Vec3,
    forward: Vec3,
    right: Vec3,
    world_up: Vec3 = world_up,
    translate_speed: f32 = 50.0,
    rotation_speed: f32 = 50.0,
    orbit_speed: f32 = 50.0,
    direction: MovementDirection = .forward,
    frame_count: u32 = 0,
    period: u32 = 100,

    const Self = @This();

    pub fn init(position: Vec3, target: Vec3) Movement {
        const forward = target.sub(&position).toNormalized();
        const right = forward.crossNormalized(&world_up);
        const up = right.crossNormalized(&forward);
        return Movement{
            .position = position,
            .target = target,
            .right = right,
            .up = up,
            .forward = forward,
        };
    }

    pub fn reset(self: *Self, position: Vec3, target: Vec3) void {
        self.position = position;
        self.target = target;
        self.forward = target.sub(&position).toNormalized();
        self.right = self.forward.crossNormalized(&self.world_up);
        self.up = self.right.crossNormalized(&self.forward);
        self.frame_count = 0;
    }

    pub fn translate(self: *Self, offset: Vec3) void {
        self.position = self.position.add(&offset);
    }

    pub fn updateForward(self: *Self) void {
        const to_target = self.target.sub(&self.position);
        if (to_target.lengthSquared() < POSITION_EPSILON) {
            // Avoid degeneracy/NaNs when position ~ target
            return;
        }
        self.forward = to_target.toNormalized();
    }

    pub fn getPosition(self: *const Self) Vec3 {
        return self.position;
    }

    pub fn getTarget(self: *const Self) Vec3 {
        return self.target;
    }

    /// Rotate position around target, preserving exact radius
    fn rotatePositionAroundTarget(self: *Self, rotation: Quat) void {
        const radius_vec = self.position.sub(&self.target);
        const target_radius = radius_vec.length();
        const rotated_position = rotation.rotateVec(&radius_vec);
        self.position = self.target.add(&rotated_position.toNormalized().mulScalar(target_radius));
    }

    /// Rotate target around position, preserving exact distance
    fn rotateTargetAroundPosition(self: *Self, rotation: Quat) void {
        const target_vec = self.target.sub(&self.position);
        const target_distance = target_vec.length();
        const rotated_target = rotation.rotateVec(&target_vec);
        self.target = self.position.add(&rotated_target.toNormalized().mulScalar(target_distance));
    }

    pub fn processMovement(
        self: *Self,
        direction: MovementDirection,
        delta_time: f32,
    ) void {
        self.frame_count += 1;
        // if (self.direction != direction) {
        //     std.debug.print("direction: {any}\n", .{direction});
        // }
        self.direction = direction;
        const translation_velocity = self.translate_speed * delta_time;
        const rot_angle = math.degreesToRadians(self.rotation_speed * delta_time);
        const orbit_angle = math.degreesToRadians(self.orbit_speed * delta_time);

        switch (direction) {
            .forward => {
                self.position = self.position.add(&self.forward.mulScalar(translation_velocity));
                self.updateForward();
            },
            .backward => {
                self.position = self.position.sub(&self.forward.mulScalar(translation_velocity));
                self.updateForward();
            },
            .left => {
                self.position = self.position.sub(&self.right.mulScalar(translation_velocity));
                self.updateForward();
            },
            .right => {
                self.position = self.position.add(&self.right.mulScalar(translation_velocity));
                self.updateForward();
            },
            .up => {
                self.position = self.position.add(&self.up.mulScalar(translation_velocity));
                self.updateForward();
            },
            .down => {
                self.position = self.position.sub(&self.up.mulScalar(translation_velocity));
                self.updateForward();
            },
            .rotate_right => {
                const rot = Quat.fromAxisAngle(&self.up, -rot_angle);
                self.rotateTargetAroundPosition(rot);
                self.right = rot.rotateVec(&self.right);
                self.updateForward();
            },
            .rotate_left => {
                const rot = Quat.fromAxisAngle(&self.up, rot_angle);
                self.rotateTargetAroundPosition(rot);
                self.right = rot.rotateVec(&self.right);
                self.updateForward();
            },
            .rotate_up => {
                const rot = Quat.fromAxisAngle(&self.right, rot_angle);
                self.rotateTargetAroundPosition(rot);
                self.up = rot.rotateVec(&self.up);
                self.updateForward();
            },
            .rotate_down => {
                const rot = Quat.fromAxisAngle(&self.right, -rot_angle);
                self.rotateTargetAroundPosition(rot);
                self.up = rot.rotateVec(&self.up);
                self.updateForward();
            },
            .roll_right => {
                const rot = Quat.fromAxisAngle(&self.forward, rot_angle);
                self.up = rot.rotateVec(&self.up);
                self.right = rot.rotateVec(&self.right);
            },
            .roll_left => {
                const rot = Quat.fromAxisAngle(&self.forward, -rot_angle);
                self.up = rot.rotateVec(&self.up);
                self.right = rot.rotateVec(&self.right);
            },
            .radius_in => {
                const to_target = self.target.sub(&self.position);
                const dist = to_target.length();
                if (dist > POSITION_EPSILON) {
                    const max_step = dist - POSITION_EPSILON;
                    const step = @min(translation_velocity, max_step);
                    if (step > 0.0) {
                        const dir = to_target.mulScalar(1.0 / dist);
                        self.position = self.position.add(&dir.mulScalar(step));
                    }
                }
                self.updateForward();
            },
            .radius_out => {
                const dir = self.target.sub(&self.position).toNormalized();
                self.position = self.position.sub(&dir.mulScalar(translation_velocity));
                self.updateForward();
            },
            .orbit_right => {
                const rot = Quat.fromAxisAngle(&self.up, -orbit_angle);
                self.rotatePositionAroundTarget(rot);
                self.updateForward();
                self.right = rot.rotateVec(&self.right);
                self.up = self.right.crossNormalized(&self.forward);
            },
            .orbit_left => {
                const rot = Quat.fromAxisAngle(&self.up, orbit_angle);
                self.rotatePositionAroundTarget(rot);
                self.updateForward();
                self.right = rot.rotateVec(&self.right);
                self.up = self.right.crossNormalized(&self.forward);
            },
            .orbit_up => {
                const rot = Quat.fromAxisAngle(&self.right, -orbit_angle);
                self.rotatePositionAroundTarget(rot);
                self.updateForward();
                self.up = rot.rotateVec(&self.up);
                self.right = self.forward.crossNormalized(&self.up);
            },
            .orbit_down => {
                const rot = Quat.fromAxisAngle(&self.right, orbit_angle);
                self.rotatePositionAroundTarget(rot);
                self.updateForward();
                self.up = rot.rotateVec(&self.up);
                self.right = self.forward.crossNormalized(&self.up);
            },
            .circle_right => {
                const rot = Quat.fromAxisAngle(&self.world_up, orbit_angle);
                self.rotatePositionAroundTarget(rot);
                self.updateForward();
                self.up = rot.rotateVec(&self.up);
                self.right = self.forward.crossNormalized(&self.up);
            },
            .circle_left => {
                const rot = Quat.fromAxisAngle(&self.world_up, -orbit_angle);
                self.rotatePositionAroundTarget(rot);
                self.updateForward();
                self.up = rot.rotateVec(&self.up);
                self.right = self.forward.crossNormalized(&self.up);
            },
            .circle_up => {
                // Choose rotation axis - use right vector, or fallback if at pole
                var rotation_axis = self.right;
                if (rotation_axis.lengthSquared() < AXIS_EPSILON) {
                    // At pole: use a stable horizontal axis
                    rotation_axis = vec3(1.0, 0.0, 0.0);
                }
                const rot = Quat.fromAxisAngle(&rotation_axis, -orbit_angle);
                self.rotatePositionAroundTarget(rot);
                self.updateForward();
                self.up = rot.rotateVec(&self.up);
                self.right = self.forward.crossNormalized(&self.up);
            },
            .circle_down => {
                // Choose rotation axis - use right vector, or fallback if at pole
                var rotation_axis = self.right;
                if (rotation_axis.lengthSquared() < AXIS_EPSILON) {
                    // At pole: use a stable horizontal axis
                    rotation_axis = vec3(1.0, 0.0, 0.0);
                }
                const rot = Quat.fromAxisAngle(&rotation_axis, orbit_angle);
                self.rotatePositionAroundTarget(rot);
                self.updateForward();
                self.up = rot.rotateVec(&self.up);
                self.right = self.forward.crossNormalized(&self.up);
            },
        }
    }

    pub fn processMouseMovement(self: *Self, xoffset_in: f32, yoffset_in: f32, constrain_pitch: bool) void {
        _ = self;
        _ = xoffset_in;
        _ = yoffset_in;
        _ = constrain_pitch;
    }

    pub fn printState(self: *Self) void {
        var position_buf: [100]u8 = undefined;
        var target_buf: [100]u8 = undefined;
        var forward_buf: [100]u8 = undefined;
        var up_buf: [100]u8 = undefined;
        var right_buf: [100]u8 = undefined;
        std.debug.print("Position: {s}\n", .{self.position.asString(&position_buf)});
        std.debug.print("Target: {s}\n", .{self.target.asString(&target_buf)});
        std.debug.print("Forward: {s}\n", .{self.forward.asString(&forward_buf)});
        std.debug.print("Up: {s}\n", .{self.up.asString(&up_buf)});
        std.debug.print("Right: {s}\n", .{self.right.asString(&right_buf)});
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
            const current_radius = movement.position.sub(&target).length();
            try std.testing.expectApproxEqAbs(current_radius, radius, epsilon);
            const translated_position = movement.position.sub(&target);
            const translated_position_norm = translated_position.toNormalized();
            const dot_with_up = translated_position_norm.dot(&movement.up);
            try std.testing.expectApproxEqAbs(dot_with_up, 0.0, epsilon);
        }
    }
    try std.testing.expectApproxEqAbs(movement.position.x, start_pos.x, epsilon);
    try std.testing.expectApproxEqAbs(movement.position.y, start_pos.y, epsilon);
    try std.testing.expectApproxEqAbs(movement.position.z, start_pos.z, epsilon);
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
    try std.testing.expectApproxEqAbs(movement.position.x, position.x, epsilon);
    try std.testing.expectApproxEqAbs(movement.position.y, position.y, epsilon);
    try std.testing.expectApproxEqAbs(movement.position.z, position.z, epsilon);
}

test "backward translation updates forward" {
    const position = Vec3.init(0.0, 0.0, 10.0);
    const target = Vec3.init(0.0, 0.0, 0.0);
    var movement = Movement.init(position, target);

    const dt: f32 = 0.1; // arbitrary
    movement.processMovement(.backward, dt);

    // forward should always equal normalized (target - position)
    const expected_forward = movement.target.sub(&movement.position).toNormalized();
    const eps = 0.0001;
    try std.testing.expectApproxEqAbs(movement.forward.x, expected_forward.x, eps);
    try std.testing.expectApproxEqAbs(movement.forward.y, expected_forward.y, eps);
    try std.testing.expectApproxEqAbs(movement.forward.z, expected_forward.z, eps);
}

test "radius in clamps near target" {
    const target = Vec3.init(0.0, 0.0, 0.0);
    var movement = Movement.init(Vec3.init(2.0, 0.0, 0.0), target);

    // Choose dt large enough to overshoot without clamping
    const dt: f32 = 10.0;
    movement.processMovement(.radius_in, dt);

    const dist = movement.position.sub(&target).length();
    // Expect we stop close to POSITION_EPSILON distance
    const tol: f32 = 1e-4;
    try std.testing.expect(dist <= POSITION_EPSILON + tol);
    try std.testing.expect(dist >= 0.0);

    // forward stays well-defined (no NaNs)
    const fwd = movement.forward;
    try std.testing.expect(!std.math.isNan(fwd.x) and !std.math.isNan(fwd.y) and !std.math.isNan(fwd.z));
}

test "circle up/down works near pole" {
    const radius: f32 = 5.0;
    const target = Vec3.init(0.0, 0.0, 0.0);
    // Position directly below target so forward points exactly up
    var movement = Movement.init(Vec3.init(0.0, -radius, 0.0), target);

    const start_pos_up = movement.position.clone();
    const step_angle = math.degreesToRadians(15.0);
    movement.update(step_angle, .circle_up);

    // Should have moved and stayed on the same radius
    const new_radius_up = movement.position.sub(&target).length();
    const eps = 1e-3;
    try std.testing.expect(new_radius_up > 0.0);
    try std.testing.expect(new_radius_up <= radius + eps and new_radius_up >= radius - eps);
    try std.testing.expect(!(movement.position.x == start_pos_up.x and movement.position.y == start_pos_up.y and movement.position.z == start_pos_up.z));
    try std.testing.expect(!std.math.isNan(movement.position.x) and !std.math.isNan(movement.position.y) and !std.math.isNan(movement.position.z));

    // Now try circle down from top pole
    movement.reset(Vec3.init(0.0, radius, 0.0), target);
    const start_pos_down = movement.position.clone();
    movement.update(step_angle, .circle_down);
    const new_radius_down = movement.position.sub(&target).length();
    try std.testing.expect(new_radius_down > 0.0);
    try std.testing.expect(new_radius_down <= radius + eps and new_radius_down >= radius - eps);
    try std.testing.expect(!(movement.position.x == start_pos_down.x and movement.position.y == start_pos_down.y and movement.position.z == start_pos_down.z));
    try std.testing.expect(!std.math.isNan(movement.position.x) and !std.math.isNan(movement.position.y) and !std.math.isNan(movement.position.z));
}
