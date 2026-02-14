const std = @import("std");
const math = @import("math");

const Allocator = std.mem.Allocator;
const Movement = @import("movement.zig").Movement;
const MovementDirection = @import("movement.zig").MovementDirection;

const Vec3 = math.Vec3;
const Mat4 = math.Mat4;

const MIN_FOV: f32 = 10.0;
const MAX_FOV: f32 = 120.0;

pub const ProjectionType = enum {
    Perspective,
    Orthographic,
};

/// Camera built on a Movement object for position and orientation.
/// Adds projection settings (FOV, aspect, near/far) and view/projection caching.
/// Movement speeds are set directly on the movement object — no duplication.
pub const Camera = struct {
    allocator: Allocator,
    movement: Movement,

    // Projection settings
    fov: f32,
    near: f32,
    far: f32,
    aspect: f32,
    ortho_scale: f32,
    projection_type: ProjectionType,

    // Caching
    cached_movement_tick: u64,
    cached_view: Mat4,
    cached_projection: Mat4,
    view_cache_valid: bool,
    projection_cache_valid: bool,

    const Self = @This();

    const Config = struct {
        position: Vec3,
        target: Vec3 = Vec3.init(0.0, 0.0, 0.0),
        scr_width: f32,
        scr_height: f32,
    };

    pub fn deinit(self: *const Self) void {
        self.allocator.destroy(self);
    }

    pub fn init(allocator: Allocator, config: Config) !*Camera {
        var movement = Movement.init(config.position, config.target);
        movement.translate_speed = 100.0;
        movement.rotation_speed = 100.0;
        movement.orbit_speed = 200.0;

        const camera = try allocator.create(Camera);
        camera.* = Camera{
            .allocator = allocator,
            .movement = movement,
            .fov = 75.0,
            .aspect = config.scr_width / config.scr_height,
            .near = 0.01,
            .far = 2000.0,
            .ortho_scale = 40.0,
            .projection_type = .Perspective,
            .cached_movement_tick = 0,
            .cached_view = undefined,
            .cached_projection = undefined,
            .view_cache_valid = false,
            .projection_cache_valid = false,
        };

        return camera;
    }

    // Projection matrix methods
    pub fn getProjectionWithType(self: *Camera, projection_type: ProjectionType) Mat4 {
        switch (projection_type) {
            .Perspective => {
                return Mat4.perspectiveRhGl(
                    math.degreesToRadians(self.fov),
                    self.aspect,
                    self.near,
                    self.far,
                );
            },
            .Orthographic => {
                const ortho_width = self.aspect * self.ortho_scale;
                const ortho_height = self.ortho_scale;
                return Mat4.orthographicRhGl(
                    -ortho_width,
                    ortho_width,
                    -ortho_height,
                    ortho_height,
                    self.near,
                    self.far,
                );
            },
        }
    }

    pub fn getProjection(self: *Self) Mat4 {
        if (!self.projection_cache_valid) {
            self.cached_projection = self.getProjectionWithType(self.projection_type);
            self.projection_cache_valid = true;
        }
        return self.cached_projection;
    }

    pub fn getView(self: *Self) Mat4 {
        const current_tick = self.movement.getUpdateTick();
        if (!self.view_cache_valid or current_tick != self.cached_movement_tick) {
            const transform = self.movement.getTransform();
            self.cached_view = Mat4.lookToRhGl(self.movement.getPosition(), transform.forward(), transform.up());
            self.cached_movement_tick = current_tick;
            self.view_cache_valid = true;
        }
        return self.cached_view;
    }

    pub fn getProjectionView(self: *Self) Mat4 {
        return self.getProjection().mulMat4(&self.getView());
    }

    pub fn setTarget(self: *Self, position: Vec3) void {
        self.movement.setTarget(position);
    }

    pub fn getTarget(self: *const Self) Vec3 {
        return self.movement.getTarget();
    }

    // Movement processing — delegates directly to movement
    pub fn processMovement(self: *Self, direction: MovementDirection, delta_time: f32) void {
        self.movement.processMovement(direction, delta_time);
    }

    // Convenience methods that pass pre-computed angles via applyMovement
    pub fn orbitTarget(self: *Self, yaw_delta: f32, pitch_delta: f32) void {
        if (yaw_delta != 0.0) {
            const direction: MovementDirection = if (yaw_delta > 0) .orbit_right else .orbit_left;
            self.movement.applyMovement(direction, 0, 0, @abs(yaw_delta));
        }
        if (pitch_delta != 0.0) {
            const direction: MovementDirection = if (pitch_delta > 0) .orbit_up else .orbit_down;
            self.movement.applyMovement(direction, 0, 0, @abs(pitch_delta));
        }
    }

    pub fn lookAround(self: *Self, yaw_delta: f32, pitch_delta: f32) void {
        if (yaw_delta != 0.0) {
            const direction: MovementDirection = if (yaw_delta > 0) .rotate_right else .rotate_left;
            self.movement.applyMovement(direction, 0, @abs(yaw_delta), 0);
        }
        if (pitch_delta != 0.0) {
            const direction: MovementDirection = if (pitch_delta > 0) .rotate_up else .rotate_down;
            self.movement.applyMovement(direction, 0, @abs(pitch_delta), 0);
        }
    }

    pub fn frameTarget(self: *Self, target: Vec3, distance: f32) void {
        const direction = target.sub(&self.movement.getPosition()).toNormalized();
        const new_position = target.sub(&direction.mulScalar(distance));
        self.movement.reset(new_position, target);
    }

    // Projection settings
    pub fn setPerspective(self: *Self) void {
        self.projection_type = .Perspective;
        self.projection_cache_valid = false;
    }

    pub fn setOrthographic(self: *Self) void {
        self.projection_type = .Orthographic;
        self.projection_cache_valid = false;
    }

    pub fn setAspect(self: *Self, aspect_ratio: f32) void {
        self.aspect = aspect_ratio;
        self.projection_cache_valid = false;
    }

    pub fn setScreenDimensions(self: *Self, width: f32, height: f32) void {
        self.aspect = width / height;
        self.projection_cache_valid = false;
    }

    pub fn adjustFov(self: *Self, zoom_amount: f32) void {
        self.fov -= zoom_amount;
        self.fov = std.math.clamp(self.fov, MIN_FOV, MAX_FOV);
        self.projection_cache_valid = false;
    }

    // Getters
    pub fn getFov(self: *const Self) f32 {
        return self.fov;
    }

    pub fn getAspect(self: *const Self) f32 {
        return self.aspect;
    }

    pub fn getPosition(self: *const Self) Vec3 {
        return self.movement.getPosition();
    }

    pub fn getForward(self: *const Self) Vec3 {
        return self.movement.getTransform().forward();
    }

    pub fn getUp(self: *const Self) Vec3 {
        return self.movement.getTransform().up();
    }

    pub fn getRight(self: *const Self) Vec3 {
        return self.movement.getTransform().right();
    }

    // Reset
    pub fn reset(self: *Self, position: Vec3, target: Vec3) void {
        self.movement.reset(position, target);
    }

    // Debug output
    pub fn asString(self: *const Camera, buf: []u8) []u8 {
        var position: [100]u8 = undefined;
        var target: [100]u8 = undefined;
        var forward: [100]u8 = undefined;

        const pos = self.movement.getPosition();
        const tgt = self.movement.getTarget();
        const fwd = self.movement.getTransform().forward();

        return std.fmt.bufPrint(
            buf,
            "Camera:\n   position: {s}\n   target: {s}\n   forward: {s}\n   fov: {d}°\n",
            .{
                pos.asString(&position),
                tgt.asString(&target),
                fwd.asString(&forward),
                self.fov,
            },
        ) catch |err| std.debug.panic("{any}", .{err});
    }
};

test "camera orbital behavior maintains tracking" {
    const allocator = std.testing.allocator;

    const camera = try Camera.init(allocator, .{
        .position = Vec3.init(10.0, 0.0, 0.0),
        .target = Vec3.init(0.0, 0.0, 0.0),
        .scr_width = 800,
        .scr_height = 600,
    });
    defer camera.deinit();

    const initial_target = camera.getTarget();

    // Orbit around target
    camera.processMovement(.orbit_right, 0.1);

    // Target should remain unchanged
    const final_target = camera.getTarget();
    const epsilon = 0.0001;
    try std.testing.expectApproxEqAbs(initial_target.x, final_target.x, epsilon);
    try std.testing.expectApproxEqAbs(initial_target.y, final_target.y, epsilon);
    try std.testing.expectApproxEqAbs(initial_target.z, final_target.z, epsilon);
}
