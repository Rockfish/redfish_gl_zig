const std = @import("std");
const glfw = @import("zglfw");
const zopengl = @import("zopengl");
const core = @import("core");
const math = @import("math");
// const state_mod = @import("state.zig");
// const simple_bullets = @import("simple_bullets.zig");
// const BulletSystem = @import("bullet.zig").BulletSystem;

const gl = zopengl.bindings;
const Shader = core.Shader;
const Shape = core.shapes.Shape;

const Vec3 = math.Vec3;
const vec3 = math.vec3;
const Mat4 = math.Mat4;
const Quat = math.Quat;
const quat = math.quat;

const Transform = core.Transform;
const uniforms = core.constants.Uniforms;

pub const Grid = struct {
    x_plus: Shape,
    x_minus: Shape,
    y_plus: Shape,
    y_minus: Shape,
    z_plus: Shape,
    z_minus: Shape,
    x_plus_mat: Mat4,
    x_minus_mat: Mat4,
    y_plus_mat: Mat4,
    y_minus_mat: Mat4,
    z_plus_mat: Mat4,
    z_minus_mat: Mat4,
    texture_id: u32,

    const Self = @This();

    pub fn init(texture_id: u32) Grid {
        const x_plus = try core.shapes.createCube(.{
            .width = 100.0,
            .height = 0.1,
            .depth = 0.1,
            .num_tiles_x = 1.0,
            .num_tiles_y = 1.0,
            .num_tiles_z = 1.0,
            .texture_mapping = .Cubemap2x3,
        });
        const x_minus = try core.shapes.createCube(.{
            .width = 100.0,
            .height = 0.1,
            .depth = 0.1,
            .num_tiles_x = 1.0,
            .num_tiles_y = 1.0,
            .num_tiles_z = 1.0,
            .texture_mapping = .Cubemap2x3,
        });
        const y_plus = try core.shapes.createCube(.{
            .width = 0.1,
            .height = 100.0,
            .depth = 0.1,
            .num_tiles_x = 1.0,
            .num_tiles_y = 1.0,
            .num_tiles_z = 1.0,
            .texture_mapping = .Cubemap2x3,
        });
        const y_minus = try core.shapes.createCube(.{
            .width = 0.1,
            .height = 100.0,
            .depth = 0.1,
            .num_tiles_x = 1.0,
            .num_tiles_y = 1.0,
            .num_tiles_z = 1.0,
            .texture_mapping = .Cubemap2x3,
        });
        const z_plus = try core.shapes.createCube(.{
            .width = 0.1,
            .height = 0.1,
            .depth = 100.0,
            .num_tiles_x = 1.0,
            .num_tiles_y = 1.0,
            .num_tiles_z = 1.0,
            .texture_mapping = .Cubemap2x3,
        });
        const z_minus = try core.shapes.createCube(.{
            .width = 0.1,
            .height = 0.1,
            .depth = 100.0,
            .num_tiles_x = 1.0,
            .num_tiles_y = 1.0,
            .num_tiles_z = 1.0,
            .texture_mapping = .Cubemap2x3,
        });

        return .{
            .x_plus = x_plus,
            .x_minus = x_minus,
            .y_plus = y_plus,
            .y_minus = y_minus,
            .z_plus = z_plus,
            .z_minus = z_minus,
            .x_plus_mat = Mat4.fromTranslation(&vec3(50.05, 0.0, 0.0)),
            .x_minus_mat = Mat4.fromTranslation(&vec3(-50.05, 0.0, 0.0)),
            .y_plus_mat = Mat4.fromTranslation(&vec3(0.0, 50.05, 0.0)),
            .y_minus_mat = Mat4.fromTranslation(&vec3(0.0, -50.05, 0.0)),
            .z_plus_mat = Mat4.fromTranslation(&vec3(0.0, 0.0, 50.05)),
            .z_minus_mat = Mat4.fromTranslation(&vec3(0.0, 0.0, -50.05)),
            .texture_id = texture_id,
        };
    }

    pub fn draw(self: *const Self, shader: *const Shader, projection: *const Mat4, view: *const Mat4) void {
        shader.setMat4(uniforms.Mat_Projection, projection);
        shader.setMat4(uniforms.Mat_View, view);
        shader.bindTextureAuto("textureDiffuse", self.texture_id);

        shader.setMat4(uniforms.Mat_Model, &self.x_plus_mat);
        self.x_plus.draw();
        shader.setMat4(uniforms.Mat_Model, &self.x_minus_mat);
        self.x_minus.draw();
        shader.setMat4(uniforms.Mat_Model, &self.y_plus_mat);
        self.y_plus.draw();
        shader.setMat4(uniforms.Mat_Model, &self.y_minus_mat);
        self.y_minus.draw();
        shader.setMat4(uniforms.Mat_Model, &self.z_plus_mat);
        self.z_plus.draw();
        shader.setMat4(uniforms.Mat_Model, &self.z_minus_mat);
        self.z_minus.draw();
    }
};
