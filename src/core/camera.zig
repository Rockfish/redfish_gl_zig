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

    // Get projection matrix using camera's current projection_type
    pub fn getProjectionMatrix(self: *Camera) Mat4 {
        return self.getProjectionMatrixWithType(self.projection_type);
    }

    // Get projection matrix with explicit type (for backward compatibility)
    pub fn getProjectionMatrixWithType(self: *Camera, projection_type: ProjectionType) Mat4 {
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

    pub fn getViewMatrix(self: *Self) Mat4 {
        return switch (self.view_type) {
            .LookTo => self.getLookToView(),
            .LookAt => self.getLookAtView(),
        };
    }

    pub fn getLookToView(self: *Self) Mat4 {
        // std.debug.print("LookTo position: {any}  forward: {any}\n", .{self.movement.position, self.movement.forward});
        return Mat4.lookToRhGl(&self.movement.position, &self.movement.forward, &self.movement.up);
    }

    pub fn getLookAtView(self: *Self) Mat4 {
        // std.debug.print("LookAt position: {any}  target: {any}\n", .{self.movement.position, self.movement.target});
        return Mat4.lookAtRhGl(&self.movement.position, &self.movement.target, &self.movement.up);
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
    }

    pub fn setOrthographic(self: *Self) void {
        self.projection_type = .Orthographic;
    }

    pub fn setAspect(self: *Self, aspect_ratio: f32) void {
        self.aspect = aspect_ratio;
    }

    pub fn setScreenDimensions(self: *Self, width: f32, height: f32) void {
        self.aspect = width / height;
    }

    pub fn adjustFov(self: *Self, zoom_amount: f32) void {
        self.fov -= zoom_amount;
        if (self.fov < MIN_FOV) {
            self.fov = MIN_FOV;
        }
        if (self.fov > MAX_FOV) {
            self.fov = MAX_FOV;
        }
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
        return std.fmt.bufPrint(
            buf,
            "Camera:\n   view_type: {any}\n   direction: {any}\n   velocity: {d}\n   position: {s}\n   target: {s}\n   forward: {s}  angle: {d}\n   right: {s}\n   up: {s}\n",
            .{
                self.view_type,
                self.movement.direction,
                self.translation_speed,
                self.movement.position.asString(&position),
                self.movement.target.asString(&target),
                self.movement.forward.asString(&forward),
                math.radiansToDegrees(Vec3.angle(&z_direction, &math.vec3(self.movement.forward.x, 0.0, self.movement.forward.z))),
                self.movement.right.asString(&right),
                self.movement.up.asString(&up),
            },
        ) catch |err| std.debug.panic("{any}", .{err});
    }
};
