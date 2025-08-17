const std = @import("std");
const math = @import("math");
const core = @import("core");
const zopengl = @import("zopengl");

const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const vec2 = math.vec2;
const vec3 = math.vec3;
const Mat4 = math.Mat4;

const ArenaAllocator = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;
const gl = zopengl.bindings;
const Shader = core.Shader;
const Texture = core.texture.Texture;
const TextureConfig = core.texture.TextureConfig;
const TextureWrap = core.texture.TextureWrap;
const TextureFilter = core.texture.TextureFilter;

const FLOOR_SIZE: f32 = 100.0;
const TILE_SIZE: f32 = 1.0;
const NUM_TILE_WRAPS: f32 = FLOOR_SIZE / TILE_SIZE;

const SIZE_OF_FLOAT = @sizeOf(f32);

const FLOOR_VERTICES: [30]f32 = .{
    // Vertices                                // TexCoord
    -FLOOR_SIZE / 2.0, 0.0, -FLOOR_SIZE / 2.0, 0.0,            0.0,
    -FLOOR_SIZE / 2.0, 0.0, FLOOR_SIZE / 2.0,  NUM_TILE_WRAPS, 0.0,
    FLOOR_SIZE / 2.0,  0.0, FLOOR_SIZE / 2.0,  NUM_TILE_WRAPS, NUM_TILE_WRAPS,
    -FLOOR_SIZE / 2.0, 0.0, -FLOOR_SIZE / 2.0, 0.0,            0.0,
    FLOOR_SIZE / 2.0,  0.0, FLOOR_SIZE / 2.0,  NUM_TILE_WRAPS, NUM_TILE_WRAPS,
    FLOOR_SIZE / 2.0,  0.0, -FLOOR_SIZE / 2.0, 0.0,            NUM_TILE_WRAPS,
};

pub const Floor = struct {
    floor_vao: gl.Uint,
    floor_vbo: gl.Uint,
    texture_floor_diffuse: *Texture,
    texture_floor_normal: *Texture,
    texture_floor_spec: *Texture,

    const Self = @This();

    pub fn deinit(self: *Self) void {
        self.texture_floor_diffuse.deleteGlTexture();
        self.texture_floor_normal.deleteGlTexture();
        self.texture_floor_spec.deleteGlTexture();
    }

    pub fn init(arena: *ArenaAllocator) !Self {
        const texture_config = TextureConfig{
            .flip_v = false,
            .gamma_correction = false,
            .filter = TextureFilter.Linear,
            .wrap = TextureWrap.Repeat,
        };

        const texture_floor_diffuse = try Texture.initFromFile(
            arena,
            "angrybots_assets/Textures/Floor/Floor D.png",
            texture_config,
        );
        const texture_floor_normal = try Texture.initFromFile(
            arena,
            "angrybots_assets/Textures/Floor/Floor N.png",
            texture_config,
        );
        const texture_floor_spec = try Texture.initFromFile(
            arena,
            "angrybots_assets/Textures/Floor/Floor M.png",
            texture_config,
        );

        var floor_vao: gl.Uint = 0;
        var floor_vbo: gl.Uint = 0;

        gl.genVertexArrays(1, &floor_vao);
        gl.genBuffers(1, &floor_vbo);

        gl.bindVertexArray(floor_vao);
        gl.bindBuffer(gl.ARRAY_BUFFER, floor_vbo);

        gl.bufferData(
            gl.ARRAY_BUFFER,
            (FLOOR_VERTICES.len * SIZE_OF_FLOAT),
            &FLOOR_VERTICES,
            gl.STATIC_DRAW,
        );
        gl.vertexAttribPointer(
            0,
            3,
            gl.FLOAT,
            gl.FALSE,
            (5 * SIZE_OF_FLOAT),
            null,
        );
        gl.enableVertexAttribArray(0);
        gl.vertexAttribPointer(
            1,
            2,
            gl.FLOAT,
            gl.FALSE,
            (5 * SIZE_OF_FLOAT),
            @ptrFromInt(3 * SIZE_OF_FLOAT),
        );
        gl.enableVertexAttribArray(1);

        return .{
            .floor_vao = floor_vao,
            .floor_vbo = floor_vbo,
            .texture_floor_diffuse = texture_floor_diffuse,
            .texture_floor_normal = texture_floor_normal,
            .texture_floor_spec = texture_floor_spec,
        };
    }

    pub fn draw(self: *const Self, shader: *const Shader, projection_view: *const Mat4) void {
        shader.useShader();

        shader.bindTexture(0, "texture_diffuse", self.texture_floor_diffuse.gl_texture_id);
        shader.bindTexture(1, "texture_normal", self.texture_floor_normal.gl_texture_id);
        shader.bindTexture(2, "texture_spec", self.texture_floor_spec.gl_texture_id);

        // angle floor
        // const _model = Mat4.from_axis_angle(vec3(0.0, 1.0, 0.0), math.degreesToRadians(45.0));

        const model = Mat4.identity();

        shader.setMat4("PV", projection_view);
        shader.setMat4("model", &model);

        gl.bindVertexArray(self.floor_vao);
        gl.drawArrays(gl.TRIANGLES, 0, 6);
        gl.bindVertexArray(0);
    }
};
