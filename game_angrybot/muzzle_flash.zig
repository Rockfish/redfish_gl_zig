const std = @import("std");
const core = @import("core");
const math = @import("math");
const gl = @import("zopengl").bindings;
const SpriteSheet = @import("sprite_sheet.zig").SpriteSheet;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const vec3 = math.vec3;
const Mat4 = math.Mat4;
const Shader = core.Shader;
const Texture = core.texture.Texture;
const TextureConfig = core.texture.TextureConfig;
const TextureType = core.texture.TextureType;
const TextureWrap = core.texture.TextureWrap;
const TextureFilter = core.texture.TextureFilter;

const SpriteAge = struct {
    age: f32,
};

pub const MuzzleFlash = struct {
    unit_square_vao: c_uint,
    muzzle_flash_impact_sprite: SpriteSheet,
    muzzle_flash_sprites_age: ArrayList(?SpriteAge),
    allocator: Allocator,

    const Self = @This();

    pub fn deinit(self: *const Self) void {
        self.muzzle_flash_impact_sprite.texture.deinit();
        self.muzzle_flash_sprites_age.deinit();
    }

    pub fn new(allocator: Allocator, unit_square_vao: c_uint) !Self {
        var texture_config = TextureConfig.default();
        texture_config.set_wrap(TextureWrap.Repeat);

        const texture_muzzle_flash_sprite_sheet = try Texture.init(
            allocator, 
            "assets/player/muzzle_spritesheet.png", 
            texture_config,
        );
        const muzzle_flash_impact_sprite = SpriteSheet.init(texture_muzzle_flash_sprite_sheet, 6, 0.03);

        return .{
            .unit_square_vao = unit_square_vao,
            .muzzle_flash_impact_sprite = muzzle_flash_impact_sprite,
            .muzzle_flash_sprites_age = ArrayList(?SpriteAge).init(allocator),
            .allocator = allocator,
        };
    }

    const Tester = struct {
        max_age: f32 = 0.0,
        pub fn predicate(self: *const @This(), spriteAge: SpriteAge) bool {
            return spriteAge.age < self.max_age;
        }
    };

    pub fn update(self: *Self, delta_time: f32) void {
        if (self.muzzle_flash_sprites_age.items.len != 0) {
            for (0..self.muzzle_flash_sprites_age.items.len) |i| {
                self.muzzle_flash_sprites_age.items[i].?.age += delta_time;
            }
            const max_age = self.muzzle_flash_impact_sprite.num_columns * self.muzzle_flash_impact_sprite.time_per_sprite;

            const tester = Tester{ .max_age = max_age };

            try core.utils.retain(
                SpriteAge,
                Tester,
                &self.muzzle_flash_sprites_age,
                tester,
            );
        }
    }

    pub fn getMinAge(self: *const Self) f32 {
        var min_age: f32 = 1000;
        for (self.muzzle_flash_sprites_age.items) |spriteAge| {
            min_age = @min(min_age, spriteAge.?.age);
        }
        return min_age;
    }

    pub fn addFlash(self: *Self) !void {
        const sprite_age = SpriteAge{ .age = 0.0 };
        try self.muzzle_flash_sprites_age.append(sprite_age);
    }

    pub fn draw(self: *const Self, sprite_shader: *Shader, projection_view: *const Mat4, muzzle_transform: *const Mat4) void {
        if (self.muzzle_flash_sprites_age.items.len == 0) {
            return;
        }

        sprite_shader.useShader();
        sprite_shader.setMat4("PV", projection_view);

        gl.enable(gl.BLEND);
        gl.depthMask(gl.FALSE);
        gl.bindVertexArray(self.unit_square_vao);

        sprite_shader.bindTexture(0, "spritesheet", self.muzzle_flash_impact_sprite.texture);

        sprite_shader.setInt("numCols", @intFromFloat(self.muzzle_flash_impact_sprite.num_columns));
        sprite_shader.setFloat("timePerSprite", self.muzzle_flash_impact_sprite.time_per_sprite);

        const scale: f32 = 50.0;

        var model = muzzle_transform.mulMat4(&Mat4.fromScale(&vec3(scale, scale, scale)));

        model = model.mulMat4(&Mat4.fromRotationX(math.degreesToRadians(-90.0)));
        model = model.mulMat4(&Mat4.fromTranslation(&vec3(0.7, 0.0, 0.0))); // adjust for position in the texture

        sprite_shader.setMat4("model", &model);

        for (self.muzzle_flash_sprites_age.items) |sprite_age| {
            if (sprite_age) |s_age| {
                sprite_shader.setFloat("age", s_age.age);
                gl.drawArrays(gl.TRIANGLES, 0, 6);
            }
        }

        gl.disable(gl.BLEND);
        gl.depthMask(gl.TRUE);
    }
};
