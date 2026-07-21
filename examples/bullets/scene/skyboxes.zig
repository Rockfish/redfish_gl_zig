const std = @import("std");
const core = @import("core");
const math = @import("math");

const Allocator = std.mem.Allocator;
const ResourceManager = core.ResourceManager;

const Vec3 = math.Vec3;
const vec3 = math.vec3;
const Mat4 = math.Mat4;

const Shader = core.Shader;
const Shape = core.shapes.Shape;
const uniforms = core.constants.Uniforms;
const RenderContext = core.RenderContext;

pub const SkyBoxDirections = struct {
    skybox: core.shapes.Skybox,
    shader: *core.Shader,
    is_visible: bool = true,

    const Self = @This();

    pub fn init(rm: *ResourceManager) !Self {
        const skybox = core.shapes.Skybox.init(rm.context.io, rm.context.alloc, .{
            .right = "assets/textures/skybox_forward_negZ/right.png",
            .left = "assets/textures/skybox_forward_negZ/left.png",
            .top = "assets/textures/skybox_forward_negZ/top.png",
            .bottom = "assets/textures/skybox_forward_negZ/bottom.png",
            .forward = "assets/textures/skybox_forward_negZ/forward.png",
            .back = "assets/textures/skybox_forward_negZ/back.png",
        });

        const skybox_shader = try rm.createShader(
            "examples/bullets/shaders/skybox.vert",
            "examples/bullets/shaders/skybox.frag",
        );
        skybox_shader.setInt("skybox", 0); // Bind to texture unit 0

        return .{
            .skybox = skybox,
            .shader = skybox_shader,
        };
    }

    pub fn draw(self: *Self, ctx: RenderContext) void {
        if (!self.is_visible) return;
        self.shader.setMat4(uniforms.Mat_Projection, &ctx.projection);
        self.shader.setMat4(uniforms.Mat_View, &ctx.view.removeTranslation());
        self.skybox.draw();
    }
};
