const std = @import("std");
const math = @import("math");
const shape = @import("shape.zig");
const constants = @import("../constants.zig");

const Mat4 = math.Mat4;
const uniforms = constants.Uniforms;

const ArenaAllocator = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;

const Shader = @import("../shader.zig").Shader;
const Texture = @import("../texture.zig").Texture;
const TextureConfig = @import("../texture.zig").TextureConfig;
const TextureWrap = @import("../texture.zig").TextureWrap;
const TextureFilter = @import("../texture.zig").TextureFilter;
const Shape = shape.Shape;

pub const PlaneConfig = struct {
    plane_size: f32 = 100.0,
    tile_size: f32 = 1.0,
    diffuse_texture: ?[:0]const u8 = null,
    normal_texture: ?[:0]const u8 = null,
    spectal_texture: ?[:0]const u8 = null,
};

pub const Plane = struct {
    allocator: Allocator,
    shape: *Shape = undefined,
    texture_diffuse: *Texture = undefined,
    texture_normal: *Texture = undefined,
    texture_spec: *Texture = undefined,

    const Self = @This();

    pub fn deinit(self: *Self) void {
        self.texture_diffuse.deleteGlTexture();
        self.texture_normal.deleteGlTexture();
        self.texture_spec.deleteGlTexture();
        self.shape.deinit();
        self.allocator.destroy(self.shape);
    }

    pub fn init(allocator: Allocator, config: PlaneConfig) !Self {
        var self = Self{ .allocator = allocator };

        const positions = [_][3]f32{
            .{ -config.plane_size / 2.0, 0.0, -config.plane_size / 2.0 },
            .{ config.plane_size / 2.0, 0.0, -config.plane_size / 2.0 },
            .{ config.plane_size / 2.0, 0.0, config.plane_size / 2.0 },
            .{ -config.plane_size / 2.0, 0.0, config.plane_size / 2.0 },
        };

        const num_tile_wraps: f32 = config.plane_size / config.tile_size;
        const texcoords = [_][2]f32{
            .{ 0.0, 0.0 },
            .{ num_tile_wraps, 0.0 },
            .{ num_tile_wraps, num_tile_wraps },
            .{ 0.0, num_tile_wraps },
        };

        const normals = [_][3]f32{
            .{ 0.0, 1.0, 0.0 },
            .{ 0.0, 1.0, 0.0 },
        };

        const indices = [_]u32{ 0, 2, 1, 0, 3, 2 };

        try loadTextures(&self, config);

        self.shape = try shape.initGLBuffers(
            allocator,
            .square,
            &positions,
            &texcoords,
            &normals,
            &.{},
            &indices,
            false,
        );

        return self;
    }

    fn loadTextures(self: *Self, config: PlaneConfig) !void {
        const texture_config = TextureConfig{
            .flip_v = false,
            .gamma_correction = false,
            .filter = TextureFilter.Linear,
            .wrap = TextureWrap.Repeat,
        };

        if (config.diffuse_texture) |texture_path| {
            self.texture_diffuse = try Texture.initFromFile(
                self.allocator,
                texture_path,
                texture_config,
            );
        }
        if (config.normal_texture) |texture_path| {
            self.texture_normal = try Texture.initFromFile(
                self.allocator,
                texture_path,
                texture_config,
            );
        }
        if (config.spectal_texture) |texture_path| {
            self.texture_spec = try Texture.initFromFile(
                self.allocator,
                texture_path,
                texture_config,
            );
        }
    }

    pub fn draw(self: *Self, shader: *Shader, projection: *const Mat4, view: *const Mat4) void {
        shader.setMat4(uniforms.Mat_Projection, projection);
        shader.setMat4(uniforms.Mat_View, view);
        shader.setMat4(uniforms.Mat_Model, &Mat4.Identity);
        shader.bindTextureAuto(uniforms.Texture_Diffuse, self.texture_diffuse.gl_texture_id);
        shader.bindTextureAuto(uniforms.Texture_Normal, self.texture_normal.gl_texture_id);
        shader.bindTextureAuto(uniforms.Texture_Spec, self.texture_spec.gl_texture_id);

        self.shape.draw(shader);
    }
};
