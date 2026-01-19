const std = @import("std");
const core = @import("core");
const math = @import("math");
const sprites = @import("sprite_sheet.zig");
const world = @import("state.zig");
const gl = @import("zopengl").bindings;

const ArrayList = std.ArrayList;

const AABB = core.AABB;
const State = world.State;
const Shader = core.Shader;
const Animation = core.animation;
const SpriteSheet = sprites.SpriteSheet;
const SpriteSheetSprite = sprites.SpriteSheetSprite;

const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const vec3 = math.vec3;
const vec4 = math.vec4;
const Mat4 = math.Mat4;
const Quat = math.Quat;

const Texture = core.texture.Texture;
const TextureConfig = core.texture.TextureConfig;
const TextureWrap = core.texture.TextureWrap;
const TextureFilter = core.texture.TextureFilter;
const Animator = Animation.Animator;
const AnimationClip = Animation.AnimationClip;

const ArenaAllocator = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.BulletsMatrix);
const uniforms = core.constants.Uniforms;

const SIZE_OF_U32 = @sizeOf(u32);
const SIZE_OF_FLOAT = @sizeOf(f32);
const SIZE_OF_VEC3 = @sizeOf(Vec3);
const SIZE_OF_VEC4 = @sizeOf(Vec4);
const SIZE_OF_MAT4 = @sizeOf(Mat4);

const SCALE_VEC: Vec3 = vec3(world.BULLET_SCALE, world.BULLET_SCALE, world.BULLET_SCALE);
const BULLET_NORMAL: Vec3 = vec3(0.0, 1.0, 0.0);
const CANONICAL_DIR: Vec3 = vec3(0.0, 0.0, 1.0);
const UP_VEC = vec3(0.0, 1.0, 0.0);
const MODEL_FORWARD = vec3(0.0, 0.0, 1.0);

const BULLET_ENEMY_MAX_COLLISION_DIST: f32 = world.BULLET_COLLIDER.height / 2.0 + world.BULLET_COLLIDER.radius + world.ENEMY_COLLIDER.height / 2.0 + world.ENEMY_COLLIDER.radius;

// Trim off margin around the bullet image
const TEXTURE_MARGIN: f32 = 0.1;

// Bullet is two intersecting planes.
// An easy way to give it the appearance of volume visible from different directions.
const BULLET_POSITIONS_H_V = [_]f32{
    // Positions
    world.BULLET_SCALE * (-0.243), 0.0,                           world.BULLET_SCALE * (-1.0),
    world.BULLET_SCALE * (-0.243), 0.0,                           world.BULLET_SCALE * 0.0,
    world.BULLET_SCALE * 0.243,    0.0,                           world.BULLET_SCALE * 0.0,
    world.BULLET_SCALE * 0.243,    0.0,                           world.BULLET_SCALE * (-1.0),
    0.0,                           world.BULLET_SCALE * (-0.243), world.BULLET_SCALE * (-1.0),
    0.0,                           world.BULLET_SCALE * (-0.243), world.BULLET_SCALE * 0.0,
    0.0,                           world.BULLET_SCALE * 0.243,    world.BULLET_SCALE * 0.0,
    0.0,                           world.BULLET_SCALE * 0.243,    world.BULLET_SCALE * (-1.0),
};

const BULLET_TEXCOORDS_H_V = [_]f32{
    // Texcoords
    1.0 - TEXTURE_MARGIN, 0.0 + TEXTURE_MARGIN,
    0.0 + TEXTURE_MARGIN, 0.0 + TEXTURE_MARGIN,
    0.0 + TEXTURE_MARGIN, 1.0 - TEXTURE_MARGIN,
    1.0 - TEXTURE_MARGIN, 1.0 - TEXTURE_MARGIN,
    1.0 - TEXTURE_MARGIN, 0.0 + TEXTURE_MARGIN,
    0.0 + TEXTURE_MARGIN, 0.0 + TEXTURE_MARGIN,
    0.0 + TEXTURE_MARGIN, 1.0 - TEXTURE_MARGIN,
    1.0 - TEXTURE_MARGIN, 1.0 - TEXTURE_MARGIN,
};

const BULLET_INDICES_H_V = [_]u32{
    0, 1, 2,
    0, 2, 3,
    4, 5, 6,
    4, 6, 7,
};

const POSITIONS = BULLET_POSITIONS_H_V;
const TEXCOORDS = BULLET_TEXCOORDS_H_V;
const INDICES = BULLET_INDICES_H_V;

pub const BulletPattern = enum {
    Square,
    Circle,
    Line,
    Custom,
};

pub const NUMBER_OF_BULLET_GROUPS: usize = 10;
pub const BULLET_GROUP_SIZE: usize = world.SPREAD_AMOUNT * world.SPREAD_AMOUNT;

pub const BulletGroup = struct {
    start_index: usize,
    group_size: u32,
    time_to_live: f32,
    directions: [BULLET_GROUP_SIZE]Vec3,
    positions: [BULLET_GROUP_SIZE]Vec3,
    transforms: [BULLET_GROUP_SIZE]Mat4,
};

pub const BulletStore = struct {
    bullet_groups: [NUMBER_OF_BULLET_GROUPS]BulletGroup,
    next_group_index: usize = 0,
    // bullet_vao: gl.Uint,
    // transforms_vbo: gl.Uint,
    bullet_texture: *Texture,
    unit_square: core.shapes.Shape,
    instanced_cube: core.shapes.Shape,

    const Self = @This();

    pub fn deinit(self: *Self) void {
        self.bullet_texture.deleteGlTexture();
    }

    pub fn init(arena: *ArenaAllocator) !Self {
        const allocator = arena.allocator();
        _ = allocator;

        const texture_config = TextureConfig{
            .flip_v = false,
            .gamma_correction = false,
            .filter = .Linear,
            .wrap = .Clamp,
        };

        const bullet_texture = try Texture.initFromFile(
            arena,
            // "angrybots_assets/Textures/Bullet/bullet_texture_transparent.png",
            //"assets/Textures/cubemap_template_3x2.png",
            "assets/Textures/grass_block.png",
            // "assets/Textures/container.jpg",
            texture_config,
        );

        const cube = try core.shapes.createCube(.{
            .width = 0.2,
            .height = 0.2,
            // .width = 1.0,
            // .height = 1.0,
            .depth = 1.0,
            .num_tiles_x = 1.0,
            .num_tiles_y = 1.0,
            .num_tiles_z = 1.0,
            .is_instanced = true,
            .texture_mapping = .Cubemap2x3,
        });

        const unit_square = try core.shapes.createSquare();

        const bullet_store: BulletStore = .{
            .bullet_groups = undefined,
            .bullet_texture = bullet_texture,
            .unit_square = unit_square,
            .instanced_cube = cube,
        };

        // Self.createShaderBuffers(&bullet_store);
        log.info("bullet_store created (matrix-based)", .{});

        return bullet_store;
    }

    pub fn createBullets(self: *Self, aim_theta: f32, muzzle_transform: *const Mat4) bool {
        return self.createBulletsWithPattern(aim_theta, muzzle_transform, .Square);
    }

    pub fn createBulletsWithPattern(self: *Self, aim_theta: f32, muzzle_transform: *const Mat4, pattern: BulletPattern) bool {
        const muzzle_world_position = muzzle_transform.mulVec4(&vec4(0.0, 0.0, 0.0, 1.0));
        const projectile_spawn_point = muzzle_world_position.xyz();

        // Generate bullet directions based on pattern
        const bullet_directions: [world.SPREAD_AMOUNT * world.SPREAD_AMOUNT]Vec3 = switch (pattern) {
            .Square => generateSquarePattern(aim_theta),
            .Circle => generateCirclePattern(aim_theta),
            .Line => generateLinePattern(aim_theta),
            .Custom => generateCustomPattern(aim_theta),
        };

        var bullet_group = BulletGroup{
            .start_index = 0,
            .group_size = BULLET_GROUP_SIZE,
            .time_to_live = world.BULLET_LIFETIME,
            .directions = bullet_directions,
            .positions = undefined,
            .transforms = undefined,
        };

        const start: usize = bullet_group.start_index;
        const end = start + bullet_group.group_size;

        for (start..end) |i| {
            const direction = bullet_directions[i];

            const spawn_point = vec3(0.0, 0.0, 0.0);

            const look_quat = math.Quat.lookAtOrientation(spawn_point, direction, UP_VEC);

            const rotation_matrix = math.Mat4.fromQuat(&look_quat);
            const translation_matrix = math.Mat4.fromTranslation(&projectile_spawn_point);
            const scale_matrix = math.Mat4.fromScale(&SCALE_VEC);

            const rotation_matrix_2 = math.Mat4.fromRotationY(math.atan(direction.x / direction.z));
            _ = rotation_matrix_2;

            const transform = translation_matrix.mulMat4(&rotation_matrix).mulMat4(&scale_matrix);

            bullet_group.positions[i] = projectile_spawn_point;
            bullet_group.transforms[i] = transform;
        }

        self.bullet_groups[self.next_group_index] = bullet_group;
        self.next_group_index = (self.next_group_index + 1) % NUMBER_OF_BULLET_GROUPS;
        return true;
    }

    pub fn updateBullets(self: *Self, state: *State) void {
        const distance_change = state.delta_time * world.BULLET_SPEED;

        for (0..NUMBER_OF_BULLET_GROUPS) |i| {
            var group = &self.bullet_groups[i];

            if (group.time_to_live <= 0.0) {
                continue;
            }

            group.time_to_live -= state.delta_time;

            for (0..BULLET_GROUP_SIZE) |bullet_idx| {
                var direction: Vec3 = group.directions[bullet_idx];

                var position: Vec3 = group.positions[bullet_idx];
                const change = direction.mulScalar(distance_change);
                position = position.add(&change);

                group.positions[bullet_idx] = position;

                const spawn_point = vec3(0.0, 0.0, 0.0);
                const look_quat = math.Quat.lookAtOrientation(spawn_point, direction, UP_VEC);
                const rotation_matrix = math.Mat4.fromQuat(&look_quat);

                const rotation_matrix_2 = math.Mat4.fromRotationY(math.atan(direction.x / direction.z));
                _ = rotation_matrix_2;

                const translation_matrix = math.Mat4.fromTranslation(&position);
                const scale_matrix = math.Mat4.fromScale(&SCALE_VEC);

                const transform = translation_matrix.mulMat4(&rotation_matrix).mulMat4(&scale_matrix);
                group.transforms[bullet_idx] = transform;
            }
        }
    }

    const SpriteAgeTester = struct {
        sprite_duration: f32,
        pub fn predicate(self: *const SpriteAgeTester, sprite: SpriteSheetSprite) bool {
            return sprite.age < self.sprite_duration;
        }
    };

    pub fn drawBullets(self: *Self, shader: *Shader, projection_view: *const Mat4) void {
        gl.enable(gl.BLEND);
        gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
        // gl.depthMask(gl.FALSE);
        // gl.disable(gl.CULL_FACE);

        for (0..NUMBER_OF_BULLET_GROUPS) |i| {
            const group = &self.bullet_groups[i];

            if (group.time_to_live <= 0.0) {
                continue;
            }

            shader.useShader();
            shader.setMat4(uniforms.Projection_View, projection_view);
            shader.setBool("useLight", false);

            shader.bindTextureAuto("texture_diffuse", self.bullet_texture.gl_texture_id);
            shader.bindTextureAuto("texture_normal", self.bullet_texture.gl_texture_id);

            self.instanced_cube.drawInstanced(BULLET_GROUP_SIZE, &group.transforms);
        }

        gl.disable(gl.BLEND);
        // gl.enable(gl.CULL_FACE);
        // gl.depthMask(gl.TRUE);
    }

    pub fn drawBulletImpacts(self: *const Self, sprite_shader: *Shader, projection_view: *const Mat4) void {
        sprite_shader.useShader();
        sprite_shader.setMat4(uniforms.Projection_View, projection_view);

        sprite_shader.setInt("numCols", @intFromFloat(self.bullet_impact_spritesheet.num_columns));
        sprite_shader.setFloat("timePerSprite", self.bullet_impact_spritesheet.time_per_sprite);

        _ = sprite_shader.bindTextureAuto("spritesheet", self.bullet_impact_spritesheet.texture.gl_texture_id);

        gl.enable(gl.BLEND);
        gl.depthMask(gl.FALSE);
        gl.disable(gl.CULL_FACE);

        gl.bindVertexArray(self.unit_square_vao);

        const scale: f32 = 2.0;

        for (self.bullet_impact_sprites.items) |sprite| {
            var model = Mat4.fromTranslation(&sprite.?.world_position);
            model = model.mulMat4(&Mat4.fromRotationX(math.degreesToRadians(-90.0)));
            model = model.mulMat4(&Mat4.fromScale(&vec3(scale, scale, scale)));

            sprite_shader.setFloat("age", sprite.?.age);
            sprite_shader.setMat4("model", &model);

            gl.drawArrays(gl.TRIANGLES, 0, 6);
        }

        gl.disable(gl.BLEND);
        gl.enable(gl.CULL_FACE);
        gl.depthMask(gl.TRUE);
    }
};

// Pattern generation functions
fn generateSquarePattern(aim_theta: f32) [world.SPREAD_AMOUNT * world.SPREAD_AMOUNT]Vec3 {
    var directions: [world.SPREAD_AMOUNT * world.SPREAD_AMOUNT]Vec3 = undefined;

    const rotation_per_bullet = world.ROTATION_PER_BULLET * math.pi / 180.0;
    const spread_amount_f32: f32 = @floatFromInt(world.SPREAD_AMOUNT);
    const spread_centering = rotation_per_bullet * (spread_amount_f32 - 1.0) / 4.0;

    var mid_dir_quat = Quat.default();
    mid_dir_quat = mid_dir_quat.mulQuat(&Quat.fromAxisAngle(&UP_VEC, aim_theta));

    var idx: usize = 0;
    for (0..world.SPREAD_AMOUNT) |i| {
        for (0..world.SPREAD_AMOUNT) |j| {
            const i_f32: f32 = @floatFromInt(i);
            const j_f32: f32 = @floatFromInt(j);

            const y_angle = rotation_per_bullet * ((i_f32 - spread_amount_f32 / 2.0)) + spread_centering;
            const x_angle = rotation_per_bullet * ((j_f32 - spread_amount_f32 / 2.0)) + spread_centering + math.pi;

            const y_quat = Quat.fromAxisAngle(&vec3(0.0, 1.0, 0.0), y_angle);
            const x_quat = Quat.fromAxisAngle(&vec3(1.0, 0.0, 0.0), x_angle);

            const combined_quat = mid_dir_quat.mulQuat(&y_quat).mulQuat(&x_quat);
            directions[idx] = combined_quat.rotateVec(&CANONICAL_DIR);
            idx += 1;
        }
    }

    return directions;
}

fn generateCirclePattern(aim_theta: f32) [world.SPREAD_AMOUNT * world.SPREAD_AMOUNT]Vec3 {
    var directions: [world.SPREAD_AMOUNT * world.SPREAD_AMOUNT]Vec3 = undefined;

    var mid_dir_quat = Quat.default();
    mid_dir_quat = mid_dir_quat.mulQuat(&Quat.fromAxisAngle(&UP_VEC, aim_theta));

    const total_bullets = world.SPREAD_AMOUNT * world.SPREAD_AMOUNT;
    const max_spread_angle = world.ROTATION_PER_BULLET * math.pi / 180.0 * @as(f32, @floatFromInt(world.SPREAD_AMOUNT));

    var idx: usize = 0;
    for (0..world.SPREAD_AMOUNT) |ring| {
        const ring_f32: f32 = @floatFromInt(ring);
        const bullets_in_ring: usize = if (ring == 0) 1 else world.SPREAD_AMOUNT;

        // Distance from center increases with ring
        const ring_spread = (ring_f32 / @as(f32, @floatFromInt(world.SPREAD_AMOUNT - 1))) * max_spread_angle;

        for (0..bullets_in_ring) |i| {
            if (idx >= total_bullets) break;

            if (ring == 0) {
                // Center bullet
                directions[idx] = mid_dir_quat.rotateVec(&CANONICAL_DIR);
            } else {
                // Ring bullets
                const angle = (2.0 * math.pi * @as(f32, @floatFromInt(i))) / @as(f32, @floatFromInt(bullets_in_ring));

                // Create direction vector in a circle
                const x_offset = std.math.cos(angle) * ring_spread;
                const y_offset = std.math.sin(angle) * ring_spread;

                // Apply offsets as rotations
                const x_quat = Quat.fromAxisAngle(&vec3(1.0, 0.0, 0.0), x_offset);
                const y_quat = Quat.fromAxisAngle(&vec3(0.0, 1.0, 0.0), y_offset);

                const combined_quat = mid_dir_quat.mulQuat(&y_quat).mulQuat(&x_quat);
                directions[idx] = combined_quat.rotateVec(&CANONICAL_DIR);
            }
            idx += 1;
        }
    }

    // Fill remaining slots if needed
    while (idx < total_bullets) {
        directions[idx] = mid_dir_quat.rotateVec(&CANONICAL_DIR);
        idx += 1;
    }

    return directions;
}

fn generateLinePattern(aim_theta: f32) [world.SPREAD_AMOUNT * world.SPREAD_AMOUNT]Vec3 {
    var directions: [world.SPREAD_AMOUNT * world.SPREAD_AMOUNT]Vec3 = undefined;

    var mid_dir_quat = Quat.default();
    mid_dir_quat = mid_dir_quat.mulQuat(&Quat.fromAxisAngle(&UP_VEC, aim_theta));

    const rotation_per_bullet = world.ROTATION_PER_BULLET * math.pi / 180.0;
    const total_bullets = world.SPREAD_AMOUNT * world.SPREAD_AMOUNT;

    for (0..total_bullets) |i| {
        const i_f32: f32 = @floatFromInt(i);
        const total_f32: f32 = @floatFromInt(total_bullets);

        // Spread bullets in a line along Y-axis
        const y_angle = rotation_per_bullet * (i_f32 - total_f32 / 2.0);
        const y_quat = Quat.fromAxisAngle(&vec3(0.0, 1.0, 0.0), y_angle);

        const combined_quat = mid_dir_quat.mulQuat(&y_quat);
        directions[i] = combined_quat.rotateVec(&CANONICAL_DIR);
    }

    return directions;
}

fn generateCustomPattern(aim_theta: f32) [world.SPREAD_AMOUNT * world.SPREAD_AMOUNT]Vec3 {
    // Example custom pattern - spiral
    var directions: [world.SPREAD_AMOUNT * world.SPREAD_AMOUNT]Vec3 = undefined;

    var mid_dir_quat = Quat.default();
    mid_dir_quat = mid_dir_quat.mulQuat(&Quat.fromAxisAngle(&UP_VEC, aim_theta));

    const total_bullets = world.SPREAD_AMOUNT * world.SPREAD_AMOUNT;
    const max_spread_angle = world.ROTATION_PER_BULLET * math.pi / 180.0 * @as(f32, @floatFromInt(world.SPREAD_AMOUNT));

    for (0..total_bullets) |i| {
        const i_f32: f32 = @floatFromInt(i);
        const total_f32: f32 = @floatFromInt(total_bullets);

        // Spiral pattern
        const t = i_f32 / total_f32;
        const spiral_angle = t * 4.0 * math.pi; // 2 full rotations
        const spiral_radius = t * max_spread_angle;

        const x_offset = std.math.cos(spiral_angle) * spiral_radius;
        const y_offset = std.math.sin(spiral_angle) * spiral_radius;

        const x_quat = Quat.fromAxisAngle(&vec3(1.0, 0.0, 0.0), x_offset);
        const y_quat = Quat.fromAxisAngle(&vec3(0.0, 1.0, 0.0), y_offset);

        const combined_quat = mid_dir_quat.mulQuat(&y_quat).mulQuat(&x_quat);
        directions[i] = combined_quat.rotateVec(&CANONICAL_DIR);
    }

    return directions;
}
