const std = @import("std");
const core = @import("core");
const math = @import("math");
const containers = @import("containers");
const gl = @import("zopengl").bindings;
const SpriteSheet = @import("sprite_sheet.zig").SpriteSheet;

const ArenaAllocator = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;
const ManagedArrayList = containers.ManagedArrayList;

const vec3 = math.vec3;
const Mat4 = math.Mat4;
const Shader = core.Shader;
const Texture = core.texture.Texture;
const TextureConfig = core.texture.TextureConfig;
const TextureWrap = core.texture.TextureWrap;
const TextureFilter = core.texture.TextureFilter;

const SpriteAge = struct {
    age: f32,
};

pub const MuzzleFlash = struct {
    unit_square_vao: c_uint,
    muzzle_flash_impact_sprite: SpriteSheet,
    muzzle_flash_sprites_age: ManagedArrayList(?SpriteAge),

    const Self = @This();

    pub fn deinit(self: *const Self) void {
        self.muzzle_flash_impact_sprite.texture.deleteGlTexture();
        self.muzzle_flash_sprites_age.deinit();
    }

    pub fn init(allocator: Allocator, unit_square_vao: c_uint) !Self {
        const texture_config: TextureConfig = .{ .wrap = .Repeat };

        const texture_muzzle_flash_sprite_sheet = try Texture.initFromFile(
            allocator,
            "assets/angrybots_assets/Textures/Bullet/muzzle_spritesheet.png",
            texture_config,
        );

        const muzzle_flash_impact_sprite = SpriteSheet.init(
            texture_muzzle_flash_sprite_sheet,
            6,
            0.03,
        );

        return .{
            .unit_square_vao = unit_square_vao,
            .muzzle_flash_impact_sprite = muzzle_flash_impact_sprite,
            .muzzle_flash_sprites_age = ManagedArrayList(?SpriteAge).init(allocator),
        };
    }

    const Tester = struct {
        max_age: f32 = 0.0,
        pub fn predicate(self: *const @This(), spriteAge: SpriteAge) bool {
            return spriteAge.age < self.max_age;
        }
    };

    pub fn update(self: *Self, delta_time: f32) void {
        if (self.muzzle_flash_sprites_age.list.items.len != 0) {
            for (0..self.muzzle_flash_sprites_age.list.items.len) |i| {
                self.muzzle_flash_sprites_age.list.items[i].?.age += delta_time;
            }
            const max_age = self.muzzle_flash_impact_sprite.num_columns * self.muzzle_flash_impact_sprite.time_per_sprite;

            const tester = Tester{ .max_age = max_age };

            core.utils.retain(
                SpriteAge,
                Tester,
                &self.muzzle_flash_sprites_age,
                tester,
            );
        }
    }

    pub fn getMinAge(self: *const Self) f32 {
        var min_age: f32 = 1000;
        for (self.muzzle_flash_sprites_age.list.items) |spriteAge| {
            min_age = @min(min_age, spriteAge.?.age);
        }
        return min_age;
    }

    pub fn addFlash(self: *Self) !void {
        const sprite_age = SpriteAge{ .age = 0.0 };
        try self.muzzle_flash_sprites_age.append(sprite_age);
    }

    pub fn draw(self: *const Self, sprite_shader: *Shader, projection_view: *const Mat4, muzzle_transform: *const Mat4) void {
        if (self.muzzle_flash_sprites_age.list.items.len == 0) {
            return;
        }

        sprite_shader.useShader();
        sprite_shader.setMat4("projectionView", projection_view);

        gl.enable(gl.BLEND);
        gl.depthMask(gl.FALSE);
        gl.bindVertexArray(self.unit_square_vao);

        sprite_shader.bindTextureAuto("spritesheet", self.muzzle_flash_impact_sprite.texture.gl_texture_id);

        sprite_shader.setInt("numCols", @intFromFloat(self.muzzle_flash_impact_sprite.num_columns));
        sprite_shader.setFloat("timePerSprite", self.muzzle_flash_impact_sprite.time_per_sprite);

        const scale: f32 = 50.0;

        var model = muzzle_transform.mulMat4(&Mat4.fromScale(vec3(scale, scale, scale)));

        model = model.mulMat4(&Mat4.fromRotationX(math.degreesToRadians(-90.0)));
        model = model.mulMat4(&Mat4.fromRotationZ(math.degreesToRadians(-90.0)));
        model = model.mulMat4(&Mat4.fromTranslation(vec3(0.7, -0.5, -0.7))); // adjust for position in the texture

        sprite_shader.setMat4("model", &model);

        for (self.muzzle_flash_sprites_age.list.items) |sprite_age| {
            if (sprite_age) |s_age| {
                sprite_shader.setFloat("age", s_age.age);
                gl.drawArrays(gl.TRIANGLES, 0, 6);
            }
        }

        gl.disable(gl.BLEND);
        gl.depthMask(gl.TRUE);
    }
};
