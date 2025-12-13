const std = @import("std");
const math = @import("math");

const Allocator = std.mem.Allocator;

const Movement = @import("movement.zig").Movement;

const Vec3 = math.Vec3;
const Mat4 = math.Mat4;

const MIN_FOV: f32 = 10.0;
const MAX_FOV: f32 = 120.0;

pub const x_direction = math.vec3(-1.0, 0.0, 0.0);
pub const y_direction = math.vec3(0.0, 1.0, 0.0);
pub const z_direction = math.vec3(0.0, 0.0, -1.0);

pub const ProjectionType = enum {
    Perspective,
    Orthographic,
};

pub const ViewType = enum {
    LookTo,
    LookAt,
};

pub const Camera = struct {
    allocator: Allocator,
    movement: Movement,
    fov: f32 = 75.0,
    near: f32 = 0.01,
    far: f32 = 2000.0,
    aspect: f32 = 1.0,
    ortho_scale: f32 = 40.0,
    view_type: ViewType = ViewType.LookAt,
    projection_type: ProjectionType = ProjectionType.Perspective,
    translation_speed: f32 = 100.0,
    rotation_speed: f32 = 100.0,
    orbit_speed: f32 = 200.0,
    cached_movement_tick: u64 = 0,
    cached_view_type: ViewType = ViewType.LookAt,
    projection_tick: u64 = 0,
    cached_view: Mat4 = undefined,
    cached_projection: Mat4 = undefined,
    cached_projection_view: Mat4 = undefined,
    view_cache_valid: bool = false,
    projection_cache_valid: bool = false,

    const Self = @This();

    const Config = struct {
        /// Camera position
        position: Vec3,
        /// target for LookAt and orbiting
        target: Vec3,
        view_type: ViewType = ViewType.LookAt,
        scr_width: f32,
        scr_height: f32,
    };

    pub fn deinit(self: *const Self) void {
        self.allocator.destroy(self);
    }

    // Camera could cache projection and view and use a dirty flag for recalculation
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
            .view_type = ViewType.LookAt,
        };
        return camera;
    }

    // Get projection matrix with explicit type (for backward compatibility)
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

    // Get projection matrix using camera's current projection_type
    pub fn getProjection(self: *Self) Mat4 {
        if (!self.projection_cache_valid) {
            self.cached_projection = self.getProjectionWithType(self.projection_type);
            self.projection_cache_valid = true;
        }
        return self.cached_projection;
    }

    pub fn getView(self: *Self) Mat4 {
        const current_tick = self.movement.getUpdateTick();
        if (!self.view_cache_valid or current_tick != self.cached_movement_tick or self.view_type != self.cached_view_type) {
            self.cached_view = switch (self.view_type) {
                .LookTo => self.getLookToView(),
                .LookAt => self.getLookAtView(),
            };
            self.cached_movement_tick = current_tick;
            self.cached_view_type = self.view_type;
            self.view_cache_valid = true;
        }
        return self.cached_view;
    }

    pub fn getProjectionView(self: *Self) Mat4 {
        return self.getProjection().mulMat4(&self.getView());
    }

    pub fn getLookToView(self: *Self) Mat4 {
        const fwd = self.movement.transform.forward();
        const up_vec = self.movement.transform.up();
        // std.debug.print("LookTo position: {any}  forward: {any}\n", .{self.movement.transform.translation, fwd});
        return Mat4.lookToRhGl(&self.movement.transform.translation, &fwd, &up_vec);
    }

    pub fn getLookAtView(self: *Self) Mat4 {
        const up_vec = self.movement.transform.up();
        // std.debug.print("LookAt position: {any}  target: {any}\n", .{self.movement.transform.translation, self.movement.target});
        return Mat4.lookAtRhGl(&self.movement.transform.translation, &self.movement.target, &up_vec);
    }

    pub fn getFov(self: *const Self) f32 {
        return self.fov;
    }

    pub fn getAspect(self: *const Self) f32 {
        return self.aspect;
    }

    pub fn setLookAt(self: *Self) void {
        self.view_type = .LookAt;
    }

    pub fn setLookTo(self: *Self) void {
        self.view_type = .LookTo;
    }

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
        if (self.fov < MIN_FOV) {
            self.fov = MIN_FOV;
        }
        if (self.fov > MAX_FOV) {
            self.fov = MAX_FOV;
        }
        self.projection_cache_valid = false;
    }

    pub fn reset(self: *Self, position: Vec3, target: Vec3) void {
        self.movement.reset(position, target);
    }

    pub fn asString(self: *const Camera, buf: []u8) []u8 {
        var position: [100]u8 = undefined;
        var target: [100]u8 = undefined;
        var forward: [100]u8 = undefined;
        var right: [100]u8 = undefined;
        var up: [100]u8 = undefined;
        const fwd = self.movement.transform.forward();
        const right_vec = self.movement.transform.right();
        const up_vec = self.movement.transform.up();
        return std.fmt.bufPrint(
            buf,
            "Camera:\n   view_type: {any}\n   direction: {any}\n   velocity: {d}\n   position: {s}\n   target: {s}\n   forward: {s}  angle: {d}\n   right: {s}\n   up: {s}\n",
            .{
                self.view_type,
                self.movement.direction,
                self.translation_speed,
                self.movement.transform.translation.asString(&position),
                self.movement.target.asString(&target),
                fwd.asString(&forward),
                math.radiansToDegrees(Vec3.angle(&z_direction, &math.vec3(fwd.x, 0.0, fwd.z))),
                right_vec.asString(&right),
                up_vec.asString(&up),
            },
        ) catch |err| std.debug.panic("{any}", .{err});
    }
};
