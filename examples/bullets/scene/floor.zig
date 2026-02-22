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
const RenderContext = core.RenderContext;
const uniforms = core.constants.Uniforms;

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
                .specular_texture = "assets/Textures/Floor/Floor M.png",
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
        lights.apply(self.shader);
    }

    pub fn draw(self: *Self, ctx: RenderContext) void {
        self.shader.setMat4(uniforms.Projection_View, &ctx.projection_view);
        self.shader.setMat4(uniforms.Mat_Model, &Mat4.Identity);
        self.shader.bindTextureAuto(uniforms.Texture_Diffuse, self.plane.texture_diffuse.gl_texture_id);
        self.shader.bindTextureAuto(uniforms.Texture_Normal, self.plane.texture_normal.gl_texture_id);
        self.shader.bindTextureAuto(uniforms.Texture_Spec, self.plane.texture_spec.gl_texture_id);
        self.plane.shape.draw(self.shader);
    }
};
