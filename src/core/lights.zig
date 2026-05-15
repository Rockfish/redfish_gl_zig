const std = @import("std");
const math = @import("math");

const Vec3 = math.Vec3;
const vec3 = math.vec3;
const Shader = @import("shader.zig").Shader;

pub const MAX_POINT_LIGHTS: usize = 4;

pub const DirectionLight = struct {
    dir: Vec3,
    color: Vec3,
};

pub const PointLight = struct {
    world_pos: Vec3 = vec3(0.0, 0.0, 0.0),
    color: Vec3 = vec3(1.0, 1.0, 1.0),
    constant: f32 = 1.0,
    linear: f32 = 0.5,
    quadratic: f32 = 3.0,
    enabled: bool = false,
};

pub const SceneLights = struct {
    ambient: Vec3,
    use_light: bool,
    direction_light: DirectionLight,
    point_lights: [MAX_POINT_LIGHTS]PointLight,
    num_point_lights: i32,

    const Self = @This();

    pub fn init() Self {
        return .{
            .ambient = vec3(0.2, 0.2, 0.2),
            .use_light = true,
            .direction_light = .{
                .dir = vec3(-1.0, -1.0, -1.0),
                .color = vec3(1.0, 1.0, 1.0),
            },
            .point_lights = [_]PointLight{.{}} ** MAX_POINT_LIGHTS,
            .num_point_lights = 0,
        };
    }

    pub fn towerDefenseDefaults() Self {
        return .{
            .ambient = vec3(0.3, 0.3, 0.3),
            .use_light = true,
            .direction_light = .{
                .dir = vec3(-1.5, -2.0, -1.0),
                .color = vec3(0.95, 0.88, 0.72),
            },
            .point_lights = [_]PointLight{.{}} ** MAX_POINT_LIGHTS,
            .num_point_lights = 0,
        };
    }

    pub fn setPointLight(self: *Self, index: usize, light: PointLight) void {
        if (index >= MAX_POINT_LIGHTS) return;
        self.point_lights[index] = light;
        // Recalculate num_point_lights from highest enabled index + 1
        self.num_point_lights = 0;
        for (0..MAX_POINT_LIGHTS) |i| {
            if (self.point_lights[i].enabled) {
                self.num_point_lights = @intCast(i + 1);
            }
        }
    }

    pub fn apply(self: *const Self, shader: *const Shader) void {
        shader.setBool("useLight", self.use_light);
        shader.setVec3("ambient", self.ambient);
        shader.setVec3("directionLight.dir", self.direction_light.dir);
        shader.setVec3("directionLight.color", self.direction_light.color);
        shader.setInt("numPointLights", self.num_point_lights);

        var buf: [64]u8 = undefined;
        for (0..@as(usize, @intCast(self.num_point_lights))) |i| {
            const idx: u8 = @intCast(i);

            const world_pos_name = std.fmt.bufPrintZ(&buf, "pointLights[{d}].worldPos", .{idx}) catch continue;
            shader.setVec3(world_pos_name, self.point_lights[i].world_pos);

            const color_name = std.fmt.bufPrintZ(&buf, "pointLights[{d}].color", .{idx}) catch continue;
            shader.setVec3(color_name, self.point_lights[i].color);

            const constant_name = std.fmt.bufPrintZ(&buf, "pointLights[{d}].constant", .{idx}) catch continue;
            shader.setFloat(constant_name, self.point_lights[i].constant);

            const linear_name = std.fmt.bufPrintZ(&buf, "pointLights[{d}].linear", .{idx}) catch continue;
            shader.setFloat(linear_name, self.point_lights[i].linear);

            const quadratic_name = std.fmt.bufPrintZ(&buf, "pointLights[{d}].quadratic", .{idx}) catch continue;
            shader.setFloat(quadratic_name, self.point_lights[i].quadratic);
        }
    }
};
