const std = @import("std");
const core = @import("core");
const math = @import("math");

const Lights = @import("lights.zig").Lights;

const Allocator = std.mem.Allocator;

const Vec3 = math.Vec3;
const vec3 = math.vec3;
const Mat4 = math.Mat4;

const Shader = core.Shader;
const Shape = core.shapes.Shape;
const Plane = core.shapes.Plane;

pub const Floor = struct {
    plane: Plane,
    shader: *Shader,

    const Self = @This();

    pub fn init(allocator: Allocator) !Self {
        var floor = try core.shapes.Plane.init(
            allocator,
            .{
                .plane_size = 100.0,
                .tile_size = 1.0,
                .diffuse_texture = "assets/Textures/Floor/Floor D.png",
                .normal_texture = "assets/Textures/Floor/Floor N.png",
                .spectal_texture = "assets/Textures/Floor/Floor M.png",
            },
        );
        floor.shape.is_transparent = true;
        floor.shape.is_depth_write = false;
        floor.shape.is_visible = false;

        const texture_shader = try Shader.init(
            allocator,
            "examples/bullets/shaders/basic_texture.vert",
            "examples/bullets/shaders/basic_texture.frag",
        );

        texture_shader.setFloat("colorAlpha", 0.8);
        texture_shader.setBool("hasTexture", true);

        std.debug.print("Floor shader: {X}\n", .{@intFromPtr(texture_shader)});

        return .{
            .plane = floor,
            .shader = texture_shader,
        };
    }

    pub fn update_lights(self: *Self, lights: Lights) void {
        self.shader.setVec3("ambientColor", lights.ambient_color);
        self.shader.setVec3("lightColor", lights.light_color);
        self.shader.setVec3("lightDirection", lights.light_direction);
    }

    pub fn draw(self: *Self, projection: *const Mat4, view: *const Mat4) void {
        // self.shader.setMat4("matProjection", projection);
        // self.shader.setMat4("matView", view);
        self.plane.draw(self.shader, projection, view);
    }
};
