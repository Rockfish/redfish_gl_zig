const std = @import("std");
const core = @import("core");
const math = @import("math");
const geom = @import("geom.zig");
const sprites = @import("sprite_sheet.zig");
const world = @import("state.zig");
const gl = @import("zopengl").bindings;
const Enemy = @import("enemy.zig").Enemy;

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
const AnimationRepeat = Animation.AnimationRepeat;

const ArenaAllocator = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.BulletsMatrix);

pub const BulletGroup = struct {
    start_index: usize,
    group_size: u32,
    time_to_live: f32,

    pub fn deinit(self: *BulletGroup) void {
        _ = self;
    }

    const Self = @This();

    pub fn new(start_index: usize, group_size: u32, time_to_live: f32) Self {
        return .{
            .start_index = start_index,
            .group_size = group_size,
            .time_to_live = time_to_live,
        };
    }
};

const SIZE_OF_U32 = @sizeOf(u32);
const SIZE_OF_FLOAT = @sizeOf(f32);
const SIZE_OF_VEC3 = @sizeOf(Vec3);
const SIZE_OF_VEC4 = @sizeOf(Vec4);
const SIZE_OF_MAT4 = @sizeOf(Mat4);

const SCALE_VEC: Vec3 = vec3(world.BULLET_SCALE, world.BULLET_SCALE, world.BULLET_SCALE);
const BULLET_NORMAL: Vec3 = vec3(0.0, 1.0, 0.0);
const CANONICAL_DIR: Vec3 = vec3(0.0, 0.0, 1.0);
const UP_VEC = vec3(0.0, 1.0, 0.0);
const MODEL_FORWARD = vec3(0.0, 0.0, -1.0);

const BULLET_ENEMY_MAX_COLLISION_DIST: f32 = world.BULLET_COLLIDER.height / 2.0 + world.BULLET_COLLIDER.radius + world.ENEMY_COLLIDER.height / 2.0 + world.ENEMY_COLLIDER.radius;

// Trim off margin around the bullet image
const TEXTURE_MARGIN: f32 = 0.1;

const BULLET_VERTICES_H_V: [40]f32 = .{
    // Positions                                        // Tex Coords
    world.BULLET_SCALE * (-0.243), 0.0,                           world.BULLET_SCALE * (-1.0), 1.0 - TEXTURE_MARGIN, 0.0 + TEXTURE_MARGIN,
    world.BULLET_SCALE * (-0.243), 0.0,                           world.BULLET_SCALE * 0.0,    0.0 + TEXTURE_MARGIN, 0.0 + TEXTURE_MARGIN,
    world.BULLET_SCALE * 0.243,    0.0,                           world.BULLET_SCALE * 0.0,    0.0 + TEXTURE_MARGIN, 1.0 - TEXTURE_MARGIN,
    world.BULLET_SCALE * 0.243,    0.0,                           world.BULLET_SCALE * (-1.0), 1.0 - TEXTURE_MARGIN, 1.0 - TEXTURE_MARGIN,
    0.0,                           world.BULLET_SCALE * (-0.243), world.BULLET_SCALE * (-1.0), 1.0 - TEXTURE_MARGIN, 0.0 + TEXTURE_MARGIN,
    0.0,                           world.BULLET_SCALE * (-0.243), world.BULLET_SCALE * 0.0,    0.0 + TEXTURE_MARGIN, 0.0 + TEXTURE_MARGIN,
    0.0,                           world.BULLET_SCALE * 0.243,    world.BULLET_SCALE * 0.0,    0.0 + TEXTURE_MARGIN, 1.0 - TEXTURE_MARGIN,
    0.0,                           world.BULLET_SCALE * 0.243,    world.BULLET_SCALE * (-1.0), 1.0 - TEXTURE_MARGIN, 1.0 - TEXTURE_MARGIN,
};

const BULLET_INDICES_H_V: [12]u32 = .{
    0, 1, 2,
    0, 2, 3,
    4, 5, 6,
    4, 6, 7,
};

const VERTICES = BULLET_VERTICES_H_V;
const INDICES = BULLET_INDICES_H_V;

pub const BulletPattern = enum {
    Square,
    Circle,
    Line,
    Custom,
};

pub const BulletStore = struct {
    all_bullet_positions: ArrayList(Vec3),
    all_bullet_directions: ArrayList(Vec3),
    all_bullet_transforms: ArrayList(Mat4),
    bullet_vao: gl.Uint,
    transforms_vbo: gl.Uint,
    bullet_groups: ArrayList(BulletGroup),
    bullet_texture: *Texture,
    bullet_impact_spritesheet: SpriteSheet,
    bullet_impact_sprites: ArrayList(?SpriteSheetSprite),
    unit_square_vao: c_uint,

    const Self = @This();

    pub fn deinit(self: *Self) void {
        self.bullet_texture.deleteGlTexture();
        self.all_bullet_positions.deinit();
        self.all_bullet_directions.deinit();
        self.all_bullet_transforms.deinit();
        self.bullet_groups.deinit();
        self.bullet_impact_sprites.deinit();
        self.bullet_impact_spritesheet.deinit();
    }

    pub fn init(arena: *ArenaAllocator, unit_square_vao: c_uint) !Self {
        const allocator = arena.allocator();

        const texture_config = TextureConfig{
            .flip_v = false,
            .gamma_correction = false,
            .filter = .Nearest,
            .wrap = .Repeat,
        };

        const bullet_texture = try Texture.initFromFile(arena, "angrybots_assets/Textures/Bullet/bullet_texture_transparent.png", texture_config);
        const texture_impact_sprite_sheet = try Texture.initFromFile(arena, "angrybots_assets/Textures/Bullet/impact_spritesheet_with_00.png", texture_config);

        const bullet_impact_spritesheet = SpriteSheet.init(texture_impact_sprite_sheet, 11, 0.05);

        var bullet_store: BulletStore = .{
            .all_bullet_positions = ArrayList(Vec3).init(allocator),
            .all_bullet_directions = ArrayList(Vec3).init(allocator),
            .all_bullet_transforms = ArrayList(Mat4).init(allocator),
            .bullet_groups = ArrayList(BulletGroup).init(allocator),
            .bullet_impact_sprites = ArrayList(?SpriteSheetSprite).init(allocator),
            .bullet_vao = 1000,
            .transforms_vbo = 1000,
            .bullet_texture = bullet_texture,
            .bullet_impact_spritesheet = bullet_impact_spritesheet,
            .unit_square_vao = unit_square_vao,
        };

        Self.createShaderBuffers(&bullet_store);
        log.info("bullet_store created (matrix-based)", .{});

        return bullet_store;
    }

    pub fn createBullets(self: *Self, aim_theta: f32, muzzle_transform: *const Mat4) !bool {
        return self.createBulletsWithPattern(aim_theta, muzzle_transform, .Square);
    }

    pub fn createBulletsWithPattern(self: *Self, aim_theta: f32, muzzle_transform: *const Mat4, pattern: BulletPattern) !bool {
        const muzzle_world_position = muzzle_transform.mulVec4(&vec4(0.0, 0.0, 0.0, 1.0));
        const projectile_spawn_point = muzzle_world_position.xyz();

        // Generate bullet directions based on pattern
        const bullet_directions = switch (pattern) {
            .Square => generateSquarePattern(aim_theta),
            .Circle => generateCirclePattern(aim_theta),
            .Line => generateLinePattern(aim_theta),
            .Custom => generateCustomPattern(aim_theta),
        };

        const start_index = self.all_bullet_positions.items.len;
        const bullet_group_size = bullet_directions.len;

        const bullet_group = BulletGroup.new(start_index, @intCast(bullet_group_size), world.BULLET_LIFETIME);

        try self.all_bullet_positions.resize(start_index + bullet_group_size);
        try self.all_bullet_directions.resize(start_index + bullet_group_size);
        try self.all_bullet_transforms.resize(start_index + bullet_group_size);

        const start: usize = start_index;
        const end = start + bullet_group_size;

        for (start..end, 0..) |index, i| {
            const direction = bullet_directions[i];

            // Create transform matrix using lookAt approach
            // Negate direction because bullets move in negative direction (position.sub(&change))
            const movement_direction = direction.mulScalar(-1.0);
            const look_quat = math.Quat.lookAtOrientation(MODEL_FORWARD, movement_direction, UP_VEC);
            const rotation_matrix = math.Mat4.fromQuat(&look_quat);
            const translation_matrix = math.Mat4.fromTranslation(&projectile_spawn_point);
            const scale_matrix = math.Mat4.fromScale(&SCALE_VEC);

            // Combine transforms: T * R * S
            const transform = translation_matrix.mulMat4(&rotation_matrix).mulMat4(&scale_matrix);

            self.all_bullet_positions.items[index] = projectile_spawn_point;
            self.all_bullet_directions.items[index] = direction;
            self.all_bullet_transforms.items[index] = transform;
        }

        try self.bullet_groups.append(bullet_group);
        return true;
    }

    pub fn updateBullets(self: *Self, state: *State) !void {
        if (self.all_bullet_positions.items.len == 0) {
            return;
        }

        const use_aabb = state.enemies.items.len != 0;
        const num_sub_groups: u32 = if (use_aabb) @as(u32, @intCast(9)) else @as(u32, @intCast(1));

        const delta_position_magnitude = state.delta_time * world.BULLET_SPEED;

        var first_live_bullet_group: usize = 0;

        for (self.bullet_groups.items) |*group| {
            group.time_to_live -= state.delta_time;

            if (group.time_to_live <= 0.0) {
                first_live_bullet_group += 1;
            } else {
                const bullet_group_start_index = group.start_index;
                const num_bullets_in_group = group.group_size;
                const sub_group_size: u32 = @divTrunc(num_bullets_in_group, num_sub_groups);

                for (0..num_sub_groups) |sub_group| {
                    var bullet_start = sub_group_size * sub_group;

                    var bullet_end = if (sub_group == (num_sub_groups - 1))
                        num_bullets_in_group
                    else
                        (bullet_start + sub_group_size);

                    bullet_start += bullet_group_start_index;
                    bullet_end += bullet_group_start_index;

                    for (bullet_start..bullet_end) |bullet_index| {
                        var direction = self.all_bullet_directions.items[bullet_index];
                        const change = direction.mulScalar(delta_position_magnitude);

                        var position = self.all_bullet_positions.items[bullet_index];
                        position = position.sub(&change);
                        self.all_bullet_positions.items[bullet_index] = position;

                        // Update transform matrix with new position
                        // Negate direction because bullets move in negative direction (position.sub(&change))
                        const movement_direction = direction.mulScalar(-1.0);
                        const look_quat = math.Quat.lookAtOrientation(MODEL_FORWARD, movement_direction, UP_VEC);
                        const rotation_matrix = math.Mat4.fromQuat(&look_quat);
                        const translation_matrix = math.Mat4.fromTranslation(&position);
                        const scale_matrix = math.Mat4.fromScale(&SCALE_VEC);

                        const transform = translation_matrix.mulMat4(&rotation_matrix).mulMat4(&scale_matrix);
                        self.all_bullet_transforms.items[bullet_index] = transform;
                    }

                    var subgroup_bound_box = AABB.init();

                    if (use_aabb) {
                        for (bullet_start..bullet_end) |bullet_index| {
                            subgroup_bound_box.expand_to_include(self.all_bullet_positions.items[bullet_index]);
                        }
                        subgroup_bound_box.expand_by(BULLET_ENEMY_MAX_COLLISION_DIST);
                    }

                    for (0..state.enemies.items.len) |i| {
                        const enemy = &state.enemies.items[i].?;

                        if (use_aabb and !subgroup_bound_box.contains_point(enemy.position)) {
                            continue;
                        }
                        for (bullet_start..bullet_end) |bullet_index| {
                            if (bulletCollidesWithEnemy(
                                &self.all_bullet_positions.items[bullet_index],
                                &self.all_bullet_directions.items[bullet_index],
                                enemy,
                            )) {
                                log.info("enemy killed", .{});
                                enemy.is_alive = false;
                                break;
                            }
                        }
                    }
                }
            }
        }

        var first_live_bullet: usize = 0;

        if (first_live_bullet_group != 0) {
            first_live_bullet =
                self.bullet_groups.items[first_live_bullet_group - 1].start_index + self.bullet_groups.items[first_live_bullet_group - 1].group_size;
            try core.utils.removeRange(BulletGroup, &self.bullet_groups, 0, first_live_bullet_group);
        }

        if (first_live_bullet != 0) {
            try core.utils.removeRange(Vec3, &self.all_bullet_positions, 0, first_live_bullet);
            try core.utils.removeRange(Vec3, &self.all_bullet_directions, 0, first_live_bullet);
            try core.utils.removeRange(Mat4, &self.all_bullet_transforms, 0, first_live_bullet);

            for (self.bullet_groups.items) |*group| {
                group.start_index -= first_live_bullet;
            }
        }

        if (self.bullet_impact_sprites.items.len != 0) {
            for (0..self.bullet_impact_sprites.items.len) |i| {
                self.bullet_impact_sprites.items[i].?.age = self.bullet_impact_sprites.items[i].?.age + state.delta_time;
            }

            const sprite_duration = self.bullet_impact_spritesheet.num_columns * self.bullet_impact_spritesheet.time_per_sprite;

            const sprite_tester = SpriteAgeTester{ .sprite_duration = sprite_duration };

            core.utils.retain(
                SpriteSheetSprite,
                SpriteAgeTester,
                &self.bullet_impact_sprites,
                sprite_tester,
            );
        }

        for (state.enemies.items) |enemy| {
            if (!enemy.?.is_alive) {
                const sprite_sheet_sprite = SpriteSheetSprite{ .age = 0.0, .world_position = enemy.?.position };
                try self.bullet_impact_sprites.append(sprite_sheet_sprite);
                try state.burn_marks.addMark(enemy.?.position);
                state.sound_engine.playSound(.Explosion);
            }
        }

        const enemyTester = EnemyTester{};
        core.utils.retain(
            Enemy,
            EnemyTester,
            &state.enemies,
            enemyTester,
        );
    }

    const SpriteAgeTester = struct {
        sprite_duration: f32,
        pub fn predicate(self: *const SpriteAgeTester, sprite: SpriteSheetSprite) bool {
            return sprite.age < self.sprite_duration;
        }
    };

    const EnemyTester = struct {
        pub fn predicate(self: *const EnemyTester, enemy: Enemy) bool {
            _ = self;
            return enemy.is_alive;
        }
    };

    fn createShaderBuffers(self: *Self) void {
        var bullet_vao: gl.Uint = 0;
        var bullet_vertices_vbo: gl.Uint = 0;
        var bullet_indices_ebo: gl.Uint = 0;
        var transforms_vbo: gl.Uint = 0;

        gl.genVertexArrays(1, &bullet_vao);
        gl.genBuffers(1, &bullet_vertices_vbo);
        gl.genBuffers(1, &bullet_indices_ebo);

        gl.bindVertexArray(bullet_vao);
        gl.bindBuffer(gl.ARRAY_BUFFER, bullet_vertices_vbo);

        // vertices data
        gl.bufferData(
            gl.ARRAY_BUFFER,
            (VERTICES.len * SIZE_OF_FLOAT),
            &VERTICES,
            gl.STATIC_DRAW,
        );

        // indices data
        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, bullet_indices_ebo);
        gl.bufferData(
            gl.ELEMENT_ARRAY_BUFFER,
            (INDICES.len * SIZE_OF_U32),
            &INDICES,
            gl.STATIC_DRAW,
        );

        // location 0: vertex positions
        gl.enableVertexAttribArray(0);
        gl.vertexAttribPointer(
            0,
            3,
            gl.FLOAT,
            gl.FALSE,
            (5 * SIZE_OF_FLOAT),
            null,
        );

        // location 1: texture coordinates
        gl.enableVertexAttribArray(1);
        gl.vertexAttribPointer(
            1,
            2,
            gl.FLOAT,
            gl.FALSE,
            (5 * SIZE_OF_FLOAT),
            @ptrFromInt(3 * SIZE_OF_FLOAT),
        );

        // Per instance transform matrix (locations 2, 3, 4, 5)
        gl.genBuffers(1, &transforms_vbo);
        gl.bindBuffer(gl.ARRAY_BUFFER, transforms_vbo);

        // Mat4 is 4 Vec4s, so we need 4 attribute locations
        for (0..4) |i| {
            const location: c_uint = @intCast(2 + i);
            gl.enableVertexAttribArray(location);
            gl.vertexAttribPointer(
                location,
                4,
                gl.FLOAT,
                gl.FALSE,
                SIZE_OF_MAT4,
                @ptrFromInt(i * SIZE_OF_VEC4),
            );
            // one matrix per bullet instance
            gl.vertexAttribDivisor(location, 1);
        }

        self.bullet_vao = bullet_vao;
        self.transforms_vbo = transforms_vbo;
    }

    pub fn drawBullets(self: *Self, shader: *Shader, projection_view: *const Mat4) void {
        if (self.all_bullet_positions.items.len == 0) {
            return;
        }

        gl.enable(gl.BLEND);
        gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

        gl.depthMask(gl.FALSE);
        gl.disable(gl.CULL_FACE);

        shader.useShader();
        shader.setMat4("projectionView", projection_view);
        shader.setBool("useLight", false);

        shader.bindTextureAuto("texture_diffuse", self.bullet_texture.gl_texture_id);
        shader.bindTextureAuto("texture_normal", self.bullet_texture.gl_texture_id);

        // bind bullet vertices and indices
        gl.bindVertexArray(self.bullet_vao);

        // bind and load bullet transform matrices
        gl.bindBuffer(gl.ARRAY_BUFFER, self.transforms_vbo);
        gl.bufferData(
            gl.ARRAY_BUFFER,
            @intCast(self.all_bullet_transforms.items.len * SIZE_OF_MAT4),
            self.all_bullet_transforms.items.ptr,
            gl.STREAM_DRAW,
        );

        // draw all bullet instances
        gl.drawElementsInstanced(
            gl.TRIANGLES,
            INDICES.len,
            gl.UNSIGNED_INT,
            null,
            @intCast(self.all_bullet_transforms.items.len),
        );

        gl.disable(gl.BLEND);
        gl.enable(gl.CULL_FACE);
        gl.depthMask(gl.TRUE);
    }

    pub fn drawBulletImpacts(self: *const Self, sprite_shader: *Shader, projection_view: *const Mat4) void {
        sprite_shader.useShader();
        sprite_shader.setMat4("projectionView", projection_view);

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

fn bulletCollidesWithEnemy(position: *Vec3, direction: *Vec3, enemy: *Enemy) bool {
    if (position.distance(&enemy.position) > BULLET_ENEMY_MAX_COLLISION_DIST) {
        return false;
    }

    const a0 = position.sub(&direction.mulScalar(world.BULLET_COLLIDER.height / 2.0));
    const a1 = position.add(&direction.mulScalar(world.BULLET_COLLIDER.height / 2.0));
    const b0 = enemy.position.sub(&enemy.dir.mulScalar(world.ENEMY_COLLIDER.height / 2.0));
    const b1 = enemy.position.add(&enemy.dir.mulScalar(world.ENEMY_COLLIDER.height / 2.0));

    const closet_distance = geom.distanceBetweenLineSegments(&a0, &a1, &b0, &b1);

    return closet_distance <= (world.BULLET_COLLIDER.radius + world.ENEMY_COLLIDER.radius);
}
