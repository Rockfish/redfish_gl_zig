const std = @import("std");
const math = @import("math");

pub const Vec3 = math.Vec3;
pub const Quat = math.Quat;

pub const MovementDirection = enum {
    // Translation relative to the current axes.
    Forward,
    Backward,
    Left,
    Right,
    Up,
    Down,
    // Rotation about the movement’s own axes.
    RotateRight,
    RotateLeft,
    RotateUp,
    RotateDown,
    RollRight,
    RollLeft,
    // Movements that depend on a target.
    RadiusIn,
    RadiusOut,
    OrbitUp,
    OrbitDown,
    OrbitLeft,
    OrbitRight,
    CircleRight,
    CircleLeft,
};

const world_up = Vec3.init(0.0, 1.0, -0.0);

/// - `moveSpeed` is in world-units per second.
/// - `rotationSpeed` is in degrees per second for in-place rotations.
/// - `orbitSpeed` is in degrees per second for orbit movements.
pub const Movement = struct {
    /// World position.
    position: Vec3,
    /// The target point used for orbit and radial movements.
    target: Vec3,
    /// Orientation as a quaternion.
    orientation: Quat,
    /// Cached axes derived from the current rotation.
    world_up: Vec3 = world_up,
    up: Vec3 = undefined,
    forward: Vec3 = undefined,
    right: Vec3 = undefined,
    translate_speed: f32 = 50.0,
    rotation_speed: f32 = 50.0,
    orbit_speed: f32 = 50.0,
    direction: MovementDirection = .Forward,

    const Self = @This();

    /// Initialize with a starting position and target.
    /// Orientation is calculated from position and target to face target
    pub fn init(position: Vec3, target: Vec3) Movement {
        const orientation = Quat.lookAtOrientation(position, target, world_up);
        var m = Movement{
            .position = position,
            .target = target,
            .orientation = orientation,
        };
        m.updateAxes();
        return m;
    }

    pub fn reset(self: *Self, position: Vec3, rotation: Quat, target: Vec3) void {
        self.position = position;
        self.orientation = rotation;
        self.target = target;
        self.updateAxes();
    }

    /// Recalculate the forward/up/right axes from the current rotation.
    pub fn updateAxes(self: *Movement) void {
        // Assume Quat.toAxes() returns an array of three Vec4 values:
        // axes[0]: right, axes[1]: up, axes[2]: forward.
        // Use a helper method (xyz()) to convert a Vec4 to Vec3.
        const axes = self.orientation.toAxes();
        self.forward = axes[2].xyz();
        self.right = axes[0].xyz();
        self.up = axes[1].xyz();
    }

    /// Translate the position by an offset.
    pub fn translate(self: *Movement, offset: Vec3) void {
        self.position = self.position.add(&offset);
    }

    /// Rotate the movement by a quaternion delta.
    pub fn rotate(self: *Movement, delta: Quat) void {
        // Multiply delta on the left. (Check your convention!)
        self.orientation = Quat.mulQuat(&delta, &self.orientation);
        self.orientation.normalize();
        self.updateAxes();
    }

    /// Process a movement command that covers translation, rotation,
    /// and target-based (orbit and radial) movements.
    pub fn processMovement(
        self: *Movement,
        direction: MovementDirection,
        delta_time: f32,
    ) void {
        self.direction = direction;
        const translationVelocity = self.translate_speed * delta_time;
        // For in-place rotations:
        const rotAngle = math.degreesToRadians(self.rotation_speed * delta_time);
        // For orbit rotations:
        const orbitAngle = math.degreesToRadians(self.orbit_speed * delta_time);

        switch (direction) {
            // Translation along the current axes.
            .Forward => {
                self.position = self.position.add(&self.forward.mulScalar(translationVelocity));
            },
            .Backward => {
                self.position = self.position.sub(&self.forward.mulScalar(translationVelocity));
            },
            .Left => {
                self.position = self.position.sub(&self.right.mulScalar(translationVelocity));
            },
            .Right => {
                self.position = self.position.add(&self.right.mulScalar(translationVelocity));
            },
            .Up => {
                self.position = self.position.add(&self.up.mulScalar(translationVelocity));
            },
            .Down => {
                self.position = self.position.sub(&self.up.mulScalar(translationVelocity));
            },
            // In-place rotations.
            .RotateRight => {
                const rot = Quat.fromAxisAngle(&self.up, -rotAngle);
                self.rotate(rot);
            },
            .RotateLeft => {
                const rot = Quat.fromAxisAngle(&self.up, rotAngle);
                self.rotate(rot);
            },
            .RotateUp => {
                const rot = Quat.fromAxisAngle(&self.right, rotAngle);
                self.rotate(rot);
            },
            .RotateDown => {
                const rot = Quat.fromAxisAngle(&self.right, -rotAngle);
                self.rotate(rot);
            },
            .RollRight => {
                const rot = Quat.fromAxisAngle(&self.forward, rotAngle);
                self.rotate(rot);
            },
            .RollLeft => {
                const rot = Quat.fromAxisAngle(&self.forward, -rotAngle);
                self.rotate(rot);
            },
            // Target-based movements.
            // Radial movement: move in/out along the vector from the position to the target.
            .RadiusIn => {
                const dir = self.target.sub(&self.position).normalizeTo();
                self.position = self.position.add(&dir.mulScalar(translationVelocity));
            },
            .RadiusOut => {
                const dir = self.target.sub(&self.position).normalizeTo();
                self.position = self.position.sub(&dir.mulScalar(translationVelocity));
            },
            // Orbit movements: rotate the position around the target.
            .OrbitRight => {
                const rot = Quat.fromAxisAngle(&self.up, orbitAngle);
                const offset = self.position.sub(&self.target);
                const rotated_offset = rot.rotateVec(&offset);
                self.position = self.target.add(&rotated_offset);
                self.updateAxes();
            },
            .OrbitLeft => {
                const rot = Quat.fromAxisAngle(&self.up, -orbitAngle);
                const offset = self.position.sub(&self.target);
                const rotated_offset = rot.rotateVec(&offset);
                self.position = self.target.add(&rotated_offset);
                self.updateAxes();
            },
            .OrbitUp => {
                const rot = Quat.fromAxisAngle(&self.right, -orbitAngle);
                const offset = self.position.sub(&self.target);
                const rotated_offset = rot.rotateVec(&offset);
                self.position = self.target.add(&rotated_offset);
                self.updateAxes();
            },
            .OrbitDown => {
                const rot = Quat.fromAxisAngle(&self.right, orbitAngle);
                const offset = self.position.sub(&self.target);
                const rotated_offset = rot.rotateVec(&offset);
                self.position = self.target.add(&rotated_offset);
                self.updateAxes();
            },
            .CircleRight => {
                const original_position = self.position;
                // 1) quaternion rotating around world Y by -angle
                const rot = Quat.fromAxisAngle(&self.world_up, -orbitAngle);
                // const rot = Quat.fromAxisAngle(&self.up, -orbitAngle);

                // 2) full offset from target
                const offset = self.position.sub(&self.target);

                // 3) flatten to XZ plane
                const flat = Vec3.init(offset.x, 0.0, offset.z);

                // 4) rotate the flat vector
                const rotated = rot.rotateVec(&flat);

                // 5) rebuild position: keep original Y
                self.position = self.target.add(&Vec3.init(rotated.x, offset.y, rotated.z));

                self.updateAxes();

                std.debug.print(
                    "CircleRight:\n  world_up: {any}\n  up: {any}\n  angle: {d}\n  >rot: {any}\n  offset: {any}\n  rotated: {any}\n  original: {any}\n  updated: {any}\n", 
                    .{world_up, self.up, orbitAngle, rot, offset, rotated, original_position, self.position,},
                );
            },
            .CircleLeft => {
                const original_position = self.position;
                // same as above but positive angle
                const rot = Quat.fromAxisAngle(&world_up, orbitAngle);
                const offset = self.position.sub(&self.target);
                const flat = Vec3.init(offset.x, 0.0, offset.z);
                const rotated = rot.rotateVec(&flat);
                self.position = self.target.add(&Vec3.init(rotated.x, offset.y, rotated.z));
                self.updateAxes();
                std.debug.print("CircleLeft: original: {any}  updated: {any}\n", .{original_position, self.position});
            },
        }
    }

    pub fn processMouseMovement(self: *Self, xoffset_in: f32, yoffset_in: f32, constrain_pitch: bool) void {
        _ = self;
        _ = xoffset_in;
        _ = yoffset_in;
        _ = constrain_pitch;
        // const xoffset: f32 = xoffset_in * self.mouse_sensitivity;
        // const yoffset: f32 = yoffset_in * self.mouse_sensitivity;
        //
        // self.yaw += xoffset;
        // self.pitch += yoffset;
        //
        // // make sure that when pitch is out of bounds, screen doesn't get flipped
        // if (constrain_pitch) {
        //     if (self.pitch > 89.0) {
        //         self.pitch = 89.0;
        //     }
        //     if (self.pitch < -89.0) {
        //         self.pitch = -89.0;
        //     }
        // }
        //
        // // update Front, Right and Up Vectors using the updated Euler angles
        // self.updateCameraVectors();
        //
        // // debug!("camera: {:#?}", self);
    }
};
