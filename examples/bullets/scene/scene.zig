const std = @import("std");
const core = @import("core");
const math = @import("math");

const cameras = @import("cameras.zig");
const grids = @import("grid.zig");
const AxisLines = @import("axis_lines.zig").AxisLines;
const Cube = @import("cube.zig").Cube;
const Floor = @import("floor.zig").Floor;
const Lights = @import("lights.zig").Lights;
//const BulletSystem = @import("../projectiles/bullet.zig").BulletSystem;
const BulletSystem = @import("../projectiles/bullet_quats.zig").BulletSystem;

const Vec3 = math.Vec3;
const vec3 = math.vec3;
const Vec4 = math.Vec4;
const Mat4 = math.Mat4;
const Quat = math.Quat;
const quat = math.quat;

const ArenaAllocator = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;

// const Skybox = core.shapes.Skybox;
const Camera = core.CameraGimbal;
const Shader = core.Shader;
const Texture = core.texture.Texture;
const Shape = core.shapes.Shape;
const Lines = core.shapes.Lines;
const Plane = core.shapes.Plane;

const SkyBoxColors = @import("skyboxes.zig").SkyBoxColors;

const Transform = core.Transform;

pub const basic_lights = Lights{
    .ambient_color = vec3(1.0, 0.6, 0.6),
    .light_color = vec3(0.35, 0.4, 0.5),
    .light_direction = vec3(3.0, 3.0, 3.0),
};

pub const Scene = struct {
    cameraOne: *Camera,
    cube: Cube,
    skybox_colors: SkyBoxColors,
    floor: Floor,
    axis_lines: AxisLines,
    bullet_system: BulletSystem,

    const Self = @This();

    pub fn init(arena: *ArenaAllocator, scr_width: f32, scr_height: f32) !Self {
        const allocator = arena.allocator();

        var scene: Scene = .{
            .cameraOne = try cameras.createCameraOne(allocator, scr_width, scr_height),
            .cube = try Cube.init(allocator),
            .skybox_colors = try SkyBoxColors.init(allocator),
            .floor = try Floor.init(allocator),
            .axis_lines = try AxisLines.init(allocator),
            .bullet_system = try BulletSystem.init(allocator),
        };

        scene.floor.update_lights(basic_lights);
        scene.cube.update_lights(basic_lights);

        return scene;
    }

    pub fn getCamera(self: *Self) *Camera {
        return self.cameraOne;
    }

    pub fn drawCube(self: *Self, projection: *const Mat4, view: *const Mat4) void {
        self.cube.draw(projection, view);
    }

    pub fn drawAxis(self: *Self, projection: *const Mat4, view: *const Mat4) void {
        self.axis_lines.draw(projection, view);
    }

    pub fn drawFloor(self: *Self, projection: *const Mat4, view: *const Mat4) void {
        self.floor.draw(projection, view);
    }

    pub fn drawSkybox(self: *Self, projection: *const Mat4, view: *const Mat4) void {
        self.skybox_colors.draw(projection, view);
    }

    pub fn drawBullets(self: *Self, projection: *const Mat4, view: *const Mat4) void {
        self.bullet_system.draw(projection, view);
    }
};
