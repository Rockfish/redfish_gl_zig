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
const Texture = core.texture.Texture;
const uniforms = core.constants.Uniforms;

pub const Cube = struct {
    shape: *Shape,
    shader: *Shader,
    texture: *Texture,
    transform: core.Transform = core.Transform.identity(),

    const Self = @This();

    pub fn init(allocator: Allocator) !Self {
        const cube = try core.shapes.createCube(allocator, .{
            .width = 1.0,
            .height = 1.0,
            .depth = 1.0,
            .num_tiles_x = 1.0,
            .num_tiles_y = 1.0,
            .num_tiles_z = 1.0,
            .texture_mapping = .Cubemap2x3,
        });

        const cubemap_texture = try core.texture.Texture.initFromFile(
            allocator,
            "assets/Textures/cubemap_template_2x3.png",
            .{
                .flip_v = false,
                .gamma_correction = false,
                .filter = .Linear,
                .wrap = .Clamp,
            },
        );

        const texture_shader = try Shader.init(
            allocator,
            "examples/bullets/shaders/basic_texture.vert",
            "examples/bullets/shaders/basic_texture.frag",
        );

        texture_shader.setBool(uniforms.Has_Texture, true);
        texture_shader.bindTextureAuto(uniforms.Texture_Diffuse, cubemap_texture.gl_texture_id);

        std.debug.print("Cube shader: {X}\n", .{@intFromPtr(texture_shader)});

        return .{
            .shape = cube,
            .shader = texture_shader,
            .texture = cubemap_texture,
        };
    }

    pub fn update_lights(self: *Self, lights: Lights) void {
        self.shader.setVec3(uniforms.Ambient_Color, lights.ambient_color);
        self.shader.setVec3(uniforms.Light_Color, lights.light_color);
        self.shader.setVec3(uniforms.Light_Direction, lights.light_direction);
    }

    pub fn draw(self: *Self, projection: *const Mat4, view: *const Mat4) void {
        self.shader.setMat4(uniforms.Mat_Projection, projection);
        self.shader.setMat4(uniforms.Mat_View, view);
        self.shader.setMat4(uniforms.Mat_Model, &self.transform.toMatrix());
        self.shape.draw(self.shader);
    }
};
