const std = @import("std");
const math = @import("math");

const Allocator = std.mem.Allocator;
const Movement = @import("movement.zig").Movement;
const MovementDirection = @import("movement.zig").MovementDirection;
const LookMode = @import("movement.zig").LookMode;

const Vec3 = math.Vec3;
const Mat4 = math.Mat4;

const MIN_FOV: f32 = 10.0;
const MAX_FOV: f32 = 120.0;

pub const ProjectionType = enum {
    Perspective,
    Orthographic,
};

/// Enhanced camera with look direction control
///
/// Key improvements:
/// - Independent look direction that can be controlled separately from movement
/// - Rotation commands no longer interfere with target tracking
/// - Clear separation between position, orientation, and look direction
/// - Simple target management for orbit operations
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

    // Movement settings
    translation_speed: f32,
    rotation_speed: f32,
    orbit_speed: f32,

    // Default look mode for camera
    look_mode: LookMode,

    // Caching
    cached_movement_tick: u64,
    projection_tick: u64,
    cached_view: Mat4,
    cached_projection: Mat4,
    view_cache_valid: bool,
    projection_cache_valid: bool,

    const Self = @This();

    const Config = struct {
        position: Vec3,
        target: Vec3 = Vec3.init(0.0, 0.0, 0.0),
        look_mode: LookMode = .transform,
        scr_width: f32,
        scr_height: f32,
    };

    pub fn deinit(self: *const Self) void {
        self.allocator.destroy(self);
    }

    pub fn init(allocator: Allocator, config: Config) !*Camera {
        const camera = try allocator.create(Camera);
        camera.* = Camera{
            .allocator = allocator,
            .movement = Movement.init(config.position, config.target),
            .fov = 75.0,
            .aspect = config.scr_width / config.scr_height,
            .near = 0.01,
            .far = 2000.0,
            .ortho_scale = 40.0,
            .projection_type = .Perspective,
            .translation_speed = 100.0,
            .rotation_speed = 100.0,
            .orbit_speed = 200.0,
            .look_mode = config.look_mode,
            .cached_movement_tick = 0,
            .projection_tick = 0,
            .cached_view = undefined,
            .cached_projection = undefined,
            .view_cache_valid = false,
            .projection_cache_valid = false,
        };

        // Sync movement speeds
        camera.movement.translate_speed = camera.translation_speed;
        camera.movement.rotation_speed = camera.rotation_speed;
        camera.movement.orbit_speed = camera.orbit_speed;

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
            // const look_dir = self.movement.getWorldLookDirection(self.default_look_mode);
            // const look_dir = self.movement.getWorldLookDirection(.look);
            // const up_vec = self.movement.getTransform().up();
            // self.cached_view = Mat4.lookToRhGl(&self.movement.getPosition(), &look_dir, &up_vec);
            self.cached_view = self.getViewWithLookMode(self.look_mode);
            self.cached_movement_tick = current_tick;
            self.view_cache_valid = true;
        }
        return self.cached_view;
    }

    /// Get view matrix using specific look mode
    pub fn getViewWithLookMode(self: *Self, look_mode: LookMode) Mat4 {
        _ = look_mode;
        //const look_dir = self.movement.getWorldLookDirection(look_mode);
        const look_dir = self.movement.getTransform().forward();
        const up_vec = self.movement.getTransform().up();
        return Mat4.lookToRhGl(self.movement.getPosition(), look_dir, up_vec);
    }

    pub fn getProjectionView(self: *Self) Mat4 {
        return self.getProjection().mulMat4(&self.getView());
    }

    // Camera behavior control
    pub fn setDefaultLookMode(self: *Self, look_mode: LookMode) void {
        self.look_mode = look_mode;
        self.view_cache_valid = false;
    }

    pub fn getDefaultLookMode(self: *const Self) LookMode {
        return self.look_mode;
    }

    pub fn setTarget(self: *Self, position: Vec3) void {
        self.movement.setTarget(position);
    }

    pub fn getTarget(self: *const Self) Vec3 {
        return self.movement.getTarget();
    }

    pub fn setLookTarget(self: *Self, position: Vec3) void {
        self.movement.setLookTarget(position);
    }

    // Movement processing
    pub fn processMovement(self: *Self, direction: MovementDirection, delta_time: f32) void {
        // Sync speeds before processing
        self.movement.translate_speed = self.translation_speed;
        self.movement.rotation_speed = self.rotation_speed;
        self.movement.orbit_speed = self.orbit_speed;

        self.movement.processMovement(direction, delta_time);
    }

    // Convenience methods for common camera operations
    pub fn orbitTarget(self: *Self, yaw_delta: f32, pitch_delta: f32) void {
        if (yaw_delta != 0.0) {
            const dt = @abs(yaw_delta) / math.degreesToRadians(self.orbit_speed);
            const direction: MovementDirection = if (yaw_delta > 0) .orbit_right else .orbit_left;
            self.movement.processMovement(direction, dt);
        }

        if (pitch_delta != 0.0) {
            const dt = @abs(pitch_delta) / math.degreesToRadians(self.orbit_speed);
            const direction: MovementDirection = if (pitch_delta > 0) .orbit_up else .orbit_down;
            self.movement.processMovement(direction, dt);
        }
    }

    pub fn lookAround(self: *Self, yaw_delta: f32, pitch_delta: f32) void {
        if (yaw_delta != 0.0) {
            const dt = @abs(yaw_delta) / math.degreesToRadians(self.rotation_speed);
            const direction: MovementDirection = if (yaw_delta > 0) .rotate_right else .rotate_left;
            self.movement.processMovement(direction, dt);
        }

        if (pitch_delta != 0.0) {
            const dt = @abs(pitch_delta) / math.degreesToRadians(self.rotation_speed);
            const direction: MovementDirection = if (pitch_delta > 0) .rotate_up else .rotate_down;
            self.movement.processMovement(direction, dt);
        }
    }

    pub fn lookAroundIndependent(self: *Self, yaw_delta: f32, pitch_delta: f32) void {
        if (yaw_delta != 0.0) {
            const dt = @abs(yaw_delta) / math.degreesToRadians(self.rotation_speed);
            const direction: MovementDirection = if (yaw_delta > 0) .look_right else .look_left;
            self.movement.processMovement(direction, dt);
        }

        if (pitch_delta != 0.0) {
            const dt = @abs(pitch_delta) / math.degreesToRadians(self.rotation_speed);
            const direction: MovementDirection = if (pitch_delta > 0) .look_up else .look_down;
            self.movement.processMovement(direction, dt);
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
        var look: [100]u8 = undefined;

        const pos = self.movement.getPosition();
        const tgt = self.movement.getTarget();
        const fwd = self.movement.getTransform().forward();
        const look_dir = self.movement.getWorldLookDirection(.look);

        return std.fmt.bufPrint(
            buf,
            "Camera:\n   look_mode: {any}\n   position: {s}\n   target: {s}\n   transform_forward: {s}\n   look_direction: {s}\n   fov: {d}°\n",
            .{
                self.look_mode,
                pos.asString(&position),
                tgt.asString(&target),
                fwd.asString(&forward),
                look_dir.asString(&look),
                self.fov,
            },
        ) catch |err| std.debug.panic("{any}", .{err});
    }
};

// Usage examples demonstrating the new capabilities
test "camera orbital behavior maintains tracking" {
    const allocator = std.testing.allocator;

    const camera = try Camera.init(allocator, .{
        .position = Vec3.init(10.0, 0.0, 0.0),
        .target = Vec3.init(0.0, 0.0, 0.0),
        .look_mode = .transform,
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

test "camera independent look while orbiting scenario" {
    const allocator = std.testing.allocator;

    const camera = try Camera.init(allocator, .{
        .position = Vec3.init(10.0, 0.0, 0.0),
        .target = Vec3.init(0.0, 0.0, 0.0),
        .look_mode = .look,
        .scr_width = 800,
        .scr_height = 600,
    });
    defer camera.deinit();

    // Start orbiting
    camera.processMovement(.orbit_right, 0.1);
    const orbital_position = camera.getPosition();

    // Look around independently
    const initial_look = camera.movement.getWorldLookDirection(.look);
    camera.processMovement(.look_left, 0.1);
    const final_look = camera.movement.getWorldLookDirection(.look);

    // Position should be unchanged, only look direction changed
    const final_position = camera.getPosition();
    const epsilon = 0.001;
    try std.testing.expectApproxEqAbs(orbital_position.x, final_position.x, epsilon);
    try std.testing.expectApproxEqAbs(orbital_position.y, final_position.y, epsilon);
    try std.testing.expectApproxEqAbs(orbital_position.z, final_position.z, epsilon);

    // Look direction should have changed
    const look_dot = initial_look.dot(&final_look);
    try std.testing.expect(look_dot < 0.99);
}

test "camera look modes work correctly" {
    const allocator = std.testing.allocator;

    const camera = try Camera.init(allocator, .{
        .position = Vec3.init(10.0, 0.0, 0.0),
        .target = Vec3.init(0.0, 0.0, 0.0),
        .look_mode = .transform,
        .scr_width = 800,
        .scr_height = 600,
    });
    defer camera.deinit();

    // Transform mode should use transform's forward
    const transform_view = camera.getViewWithLookMode(.transform);
    _ = transform_view;
    const transform_forward = camera.movement.getTransform().forward();

    // Look mode should use look direction
    const look_view = camera.getViewWithLookMode(.look);
    _ = look_view;
    const look_forward = camera.movement.getWorldLookDirection(.look);

    // Initially they should be the same (look direction starts as local forward)
    const epsilon = 0.01;
    try std.testing.expectApproxEqAbs(transform_forward.x, look_forward.x, epsilon);
    try std.testing.expectApproxEqAbs(transform_forward.y, look_forward.y, epsilon);
    try std.testing.expectApproxEqAbs(transform_forward.z, look_forward.z, epsilon);
}
