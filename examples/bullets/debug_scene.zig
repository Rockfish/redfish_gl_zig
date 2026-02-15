const std = @import("std");
const core = @import("core");
const math = @import("math");

const Scene = @import("scene.zig").Scene;
const SceneCamera = @import("scene_camera.zig").SceneCamera;

const FreeCamera = @import("scene/free_camera.zig").FreeCamera;
const grids = @import("scene/grid.zig");
const AxisLines = @import("scene/axis_lines.zig").AxisLines;
const Cube = @import("scene/cube.zig").Cube;
const Floor = @import("scene/floor.zig").Floor;
const Lights = @import("scene/lights.zig").Lights;
const SkyBoxDirections = @import("scene/skyboxes.zig").SkyBoxDirections;

const BulletSystem = @import("projectiles/bullet_system.zig").BulletSystem;
const Turret = @import("projectiles/turret.zig").Turret;

const Vec3 = math.Vec3;
const vec3 = math.vec3;
const Vec4 = math.Vec4;
const Mat4 = math.Mat4;
const Quat = math.Quat;
const quat = math.quat;

const ArenaAllocator = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;

const Shader = core.Shader;
const Texture = core.texture.Texture;
const Shape = core.shapes.Shape;
const Lines = core.shapes.Lines;
const Plane = core.shapes.Plane;

const Transform = core.Transform;

pub const basic_lights = Lights{
    .ambient_color = vec3(1.0, 0.6, 0.6),
    .light_color = vec3(0.35, 0.4, 0.5),
    .light_direction = vec3(3.0, 3.0, 3.0),
};

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
    turret,
    camera,
};

pub const SceneDebug = struct {
    scene_camera: *SceneCamera,
    cube: Cube,
    skybox: SkyBoxDirections,
    floor: Floor,
    axis_lines: AxisLines,
    turret: *Turret,
    input_tick: u64 = 0,
    motion_type: MotionType = .circle,
    motion_object: MotionObject = .turret,
    reset: bool = false,
    run_animation: bool = true,

    const Self = @This();

    pub fn init(allocator: Allocator, input: *core.Input) !*Scene {

        const camera = try FreeCamera.init(
            allocator,
            input.framebuffer_width,
            input.framebuffer_height,
        );

        var scene = try allocator.create(SceneDebug);
        scene.* = .{
            .scene_camera = camera,
            .cube = try Cube.init(allocator),
            .skybox = try SkyBoxDirections.init(allocator),
            .floor = try Floor.init(allocator),
            .axis_lines = try AxisLines.init(allocator),
            .turret = try Turret.init(allocator),
        };

        scene.floor.update_lights(basic_lights);
        scene.cube.update_lights(basic_lights);

        scene.floor.plane.shape.is_visible = true;
        scene.skybox.is_visible = false;

        return try Scene.init(allocator, "Debug", scene, input);
    }

    pub fn getSceneCamera(self: *Self) *SceneCamera {
        return self.scene_camera;
    }

    pub fn update(self: *Self, input: *core.Input) !void {
        try self.scene_camera.update(input);
        try self.processInput(input);

        if (self.run_animation == true) {
            try self.turret.update(input);
        }
    }

    pub fn draw(self: *Self) void {
        var camera = self.getSceneCamera().getCamera();
        const projection = camera.getProjection();
        const view = camera.getView();

        self.cube.draw(&projection, &view);
        self.axis_lines.draw(&projection, &view);
        self.skybox.draw(&projection, &view);

        self.turret.draw(&projection, &view);

        self.floor.draw(&projection, &view);
    }

    fn processInput(self: *Self, input: *core.Input) !void {
        // const dt = input.delta_time;

        switch (self.motion_object) {
            .turret => try self.turret.processInput(input),
            .camera => try self.scene_camera.processInput(input),
            else => {},
        }

        var iterator = input.key_presses.iterator();
        while (iterator.next()) |k| {
            // if (self.motion_object != .turret) {
                // const movement_object = if (self.motion_object == .base) &self.getCamera().base_movement else &self.getCamera().gimbal_movement;
                //
                // switch (self.motion_type) {
                //     .translate => switch (k) {
                //         .w => movement_object.processMovement(.forward, dt),
                //         .s => movement_object.processMovement(.backward, dt),
                //         .a, .left => movement_object.processMovement(.left, dt),
                //         .d, .right => movement_object.processMovement(.right, dt),
                //         .up => movement_object.processMovement(.up, dt),
                //         .down => movement_object.processMovement(.down, dt),
                //         else => {},
                //     },
                //     .orbit => switch (k) {
                //         .w, .up => movement_object.processMovement(.orbit_up, dt),
                //         .s, .down => movement_object.processMovement(.orbit_down, dt),
                //         .a, .left => movement_object.processMovement(.orbit_left, dt),
                //         .d, .right => movement_object.processMovement(.orbit_right, dt),
                //         else => {},
                //     },
                //     .circle => switch (k) {
                //         .w, .up => movement_object.processMovement(.circle_up, dt),
                //         .s, .down => movement_object.processMovement(.circle_down, dt),
                //         .a, .left => movement_object.processMovement(.circle_left, dt),
                //         .d, .right => movement_object.processMovement(.circle_right, dt),
                //         else => {},
                //     },
                //     .rotate, .look => switch (k) {
                //         .w, .up => movement_object.processMovement(.rotate_up, dt),
                //         .s, .down => movement_object.processMovement(.rotate_down, dt),
                //         .a, .left => movement_object.processMovement(.rotate_left, dt),
                //         .d, .right => movement_object.processMovement(.rotate_right, dt),
                //         else => {},
                //     },
                // }
            // }

            // One-shot keys: fire once per press
            if (input.key_processed.contains(k)) {
                continue;
            }
            input.key_processed.insert(k);

            switch (k) {
                .b => {
                    self.skybox.is_visible = !self.skybox.is_visible;
                },
                .c => {
                    self.motion_object = .camera;
                },
                .f => {
                    self.floor.plane.shape.is_visible = !self.floor.plane.shape.is_visible;
                },
                .r => try self.turret.fire(),
                .t => {
                    self.motion_object = .turret;
                },
                .one => {
                    self.getSceneCamera().getCamera().setPerspective();
                    std.debug.print("Projection: Perspective\n", .{});
                },
                .two => {
                    self.getSceneCamera().getCamera().setOrthographic();
                    std.debug.print("Projection: Orthographic\n", .{});
                },
                .three => {
                    self.motion_type = .orbit;
                    self.printMotionViewState();
                },
                .four => {
                    self.motion_type = .rotate;
                    self.printMotionViewState();
                },
                .five => {
                    self.motion_type = .look;
                    self.printMotionViewState();
                },
                .six => {
                    self.motion_object = if (self.motion_object == .base) .gimbal else .base;
                    self.printMotionViewState();
                },
                .seven => {
                    // const camera = self.getCamera();
                    // camera.view_mode = if (camera.view_mode == .base) .gimbal else .base;
                    // camera.view_cache_valid = false;
                    // self.printMotionViewState();
                },
                .eight => {
                },
                .nine => {
                },
                .zero => {
                    self.motion_object = .turret;
                },
                .F12 => {
                    std.debug.print("Screenshot requested (F12)\n", .{});
                },
                .space => {
                    self.run_animation = !self.run_animation;
                },
                else => {},
            }
        }
    }

    pub fn printMotionViewState(self: *Self) void {
        std.debug.print("-----\n", .{});
        // std.debug.print("Look mode: {any}\n", .{self.getCamera().view_mode});
        std.debug.print("Motion type: {any}\n", .{self.motion_type});
        std.debug.print("Motion object: {any}\n", .{self.motion_object});
        std.debug.print("-----\n", .{});
    }
};
