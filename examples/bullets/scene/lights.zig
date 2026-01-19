const std = @import("std");
const core = @import("core");
const math = @import("math");

const Vec3 = math.Vec3;
const vec3 = math.vec3;

pub const Lights = struct {
    ambient_color: Vec3,
    light_color: Vec3,
    light_direction: Vec3,
};

pub const basic_lights = Lights{
    .ambient_color = vec3(1.0, 0.6, 0.6),
    .light_color = vec3(0.35, 0.4, 0.5),
    .light_direction = vec3(3.0, 3.0, 3.0),
};
