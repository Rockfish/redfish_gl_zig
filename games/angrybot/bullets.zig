const std = @import("std");
const core = @import("core");
const math = @import("math");
//const aabb = @import("aabb.zig");
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
const log = std.log.scoped(.Bullets);

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
const SIZE_OF_QUAT = @sizeOf(Quat);

const SCALE_VEC: Vec3 = vec3(world.BULLET_SCALE, world.BULLET_SCALE, world.BULLET_SCALE);
const BULLET_NORMAL: Vec3 = vec3(0.0, 1.0, 0.0);
const CANONICAL_DIR: Vec3 = vec3(0.0, 0.0, 1.0);
const UP_VEC = vec3(0.0, 1.0, 0.0); // rotate around y

const BULLET_ENEMY_MAX_COLLISION_DIST: f32 = world.BULLET_COLLIDER.height / 2.0 + world.BULLET_COLLIDER.radius + world.ENEMY_COLLIDER.height / 2.0 + world.ENEMY_COLLIDER.radius;

// Trim off margin around the bullet image
// const TEXTURE_MARGIN: f32 = 0.0625;
// const TEXTURE_MARGIN: f32 = 0.2;
const TEXTURE_MARGIN: f32 = 0.1;

const BULLET_VERTICES_H: [20]f32 = .{
    // Positions                                        // Tex Coords
    world.BULLET_SCALE * (-0.243), 0.0, world.BULLET_SCALE * (-1.0), 1.0 - TEXTURE_MARGIN, 0.0 + TEXTURE_MARGIN,
    world.BULLET_SCALE * (-0.243), 0.0, world.BULLET_SCALE * 0.0,    0.0 + TEXTURE_MARGIN, 0.0 + TEXTURE_MARGIN,
    world.BULLET_SCALE * 0.243,    0.0, world.BULLET_SCALE * 0.0,    0.0 + TEXTURE_MARGIN, 1.0 - TEXTURE_MARGIN,
    world.BULLET_SCALE * 0.243,    0.0, world.BULLET_SCALE * (-1.0), 1.0 - TEXTURE_MARGIN, 1.0 - TEXTURE_MARGIN,
};

// vertical surface to see the bullets from the side

const BULLET_VERTICES_V: [20]f32 = .{
    0.0, world.BULLET_SCALE * (-0.243), world.BULLET_SCALE * (-1.0), 1.0 - TEXTURE_MARGIN, 0.0 + TEXTURE_MARGIN,
    0.0, world.BULLET_SCALE * (-0.243), world.BULLET_SCALE * 0.0,    0.0 + TEXTURE_MARGIN, 0.0 + TEXTURE_MARGIN,
    0.0, world.BULLET_SCALE * 0.243,    world.BULLET_SCALE * 0.0,    0.0 + TEXTURE_MARGIN, 1.0 - TEXTURE_MARGIN,
    0.0, world.BULLET_SCALE * 0.243,    world.BULLET_SCALE * (-1.0), 1.0 - TEXTURE_MARGIN, 1.0 - TEXTURE_MARGIN,
};

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

const BULLET_INDICES: [6]u32 = .{ 0, 1, 2, 0, 2, 3 };

const BULLET_INDICES_H_V: [12]u32 = .{
    0, 1, 2,
    0, 2, 3,
    4, 5, 6,
    4, 6, 7,
};

const VERTICES = BULLET_VERTICES_H_V;
const INDICES = BULLET_INDICES_H_V;

pub const BulletStore = struct {
    all_bullet_positions: ArrayList(Vec3),
    all_bullet_rotations: ArrayList(Quat),
    all_bullet_directions: ArrayList(Vec3),
    // precalculated rotations
    x_rotations: ArrayList(Quat),
    y_rotations: ArrayList(Quat),
    bullet_vao: gl.Uint,
    rotations_vbo: gl.Uint,
    positions_vbo: gl.Uint,
    bullet_groups: ArrayList(BulletGroup),
    bullet_texture: *Texture,
    bullet_impact_spritesheet: SpriteSheet,
    bullet_impact_sprites: ArrayList(?SpriteSheetSprite),
    unit_square_vao: c_uint,

    const Self = @This();

    pub fn deinit(self: *Self) void {
        self.bullet_texture.deleteGlTexture();
        self.all_bullet_positions.deinit();
        self.all_bullet_rotations.deinit();
        self.all_bullet_directions.deinit();
        self.x_rotations.deinit();
        self.y_rotations.deinit();
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

        // Pre calculate the bullet spread rotations. Only needs to be done once.
        var x_rotations = ArrayList(Quat).init(allocator);
        var y_rotations = ArrayList(Quat).init(allocator);

        const rotation_per_bullet = world.ROTATION_PER_BULLET * math.pi / 180.0;
        const spread_amount_f32: f32 = @floatFromInt(world.SPREAD_AMOUNT);
        const spread_centering = rotation_per_bullet * (spread_amount_f32 - @as(f32, 1.0)) / @as(f32, 4.0);

        for (0..world.SPREAD_AMOUNT) |i| {
            const i_f32: f32 = @floatFromInt(i);
            const y_rot = Quat.fromAxisAngle(
                &vec3(0.0, 1.0, 0.0),
                rotation_per_bullet * ((i_f32 - world.SPREAD_AMOUNT) / @as(f32, 2.0)) + spread_centering,
            );
            const x_rot = Quat.fromAxisAngle(
                &vec3(1.0, 0.0, 0.0),
                rotation_per_bullet * ((i_f32 - world.SPREAD_AMOUNT) / @as(f32, 2.0)) + spread_centering + math.pi,
            );
            // std.debug.print("x_rot = {any}\n", .{x_rot});
            try x_rotations.append(x_rot);
            try y_rotations.append(y_rot);
        }

        var bullet_store: BulletStore = .{
            .all_bullet_positions = ArrayList(Vec3).init(allocator),
            .all_bullet_rotations = ArrayList(Quat).init(allocator),
            .all_bullet_directions = ArrayList(Vec3).init(allocator),
            .x_rotations = x_rotations,
            .y_rotations = y_rotations,
            .bullet_groups = ArrayList(BulletGroup).init(allocator),
            .bullet_impact_sprites = ArrayList(?SpriteSheetSprite).init(allocator),
            .bullet_vao = 1000, //bullet_vao,
            .rotations_vbo = 1000, //instance_rotation_vbo,
            .positions_vbo = 1000, //instance_position_vbo,
            .bullet_texture = bullet_texture,
            .bullet_impact_spritesheet = bullet_impact_spritesheet,
            .unit_square_vao = unit_square_vao,
        };

        Self.createShaderBuffers(&bullet_store);
        log.info("bullet_store created", .{});
        //log.debug("bullet_store = {any}", .{bullet_store});

        return bullet_store;
    }

    pub fn createBullets(self: *Self, aim_theta: f32, muzzle_transform: *const Mat4) !bool {
        const muzzle_world_position = muzzle_transform.mulVec4(&vec4(0.0, 0.0, 0.0, 1.0));
        const projectile_spawn_point = muzzle_world_position.xyz();

        var mid_dir_quat = Quat.default();
        mid_dir_quat = mid_dir_quat.mulQuat(&Quat.fromAxisAngle(&UP_VEC, aim_theta));

        const start_index = self.all_bullet_positions.items.len;
        const bullet_group_size = world.SPREAD_AMOUNT * world.SPREAD_AMOUNT;

        const bullet_group = BulletGroup.new(start_index, bullet_group_size, world.BULLET_LIFETIME);

        try self.all_bullet_positions.resize(start_index + bullet_group_size);
        try self.all_bullet_rotations.resize(start_index + bullet_group_size);
        try self.all_bullet_directions.resize(start_index + bullet_group_size);

        const start: usize = start_index;
        const end = start + bullet_group_size;

        for (start..end) |index| {
            const count = index - start;
            const i = @divTrunc(count, world.SPREAD_AMOUNT);
            const j = @mod(count, world.SPREAD_AMOUNT);

            const y_quat = mid_dir_quat.mulQuat(&self.y_rotations.items[i]);
            const rot_quat = y_quat.mulQuat(&self.x_rotations.items[j]);

            const direction = rot_quat.rotateVec(&CANONICAL_DIR);

            self.all_bullet_positions.items[index] = projectile_spawn_point;
            self.all_bullet_rotations.items[index] = rot_quat;
            self.all_bullet_directions.items[index] = direction;
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
            // self.bullet_groups.drain(0..first_live_bullet_group);
            try core.utils.removeRange(BulletGroup, &self.bullet_groups, 0, first_live_bullet_group);
        }

        if (first_live_bullet != 0) {
            try core.utils.removeRange(Vec3, &self.all_bullet_positions, 0, first_live_bullet);
            try core.utils.removeRange(Vec3, &self.all_bullet_directions, 0, first_live_bullet);
            try core.utils.removeRange(Quat, &self.all_bullet_rotations, 0, first_live_bullet);

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
        // state.enemies.retain(|e| e.is_alive);
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
        var rotations_vbo: gl.Uint = 0;
        var positions_vbo: gl.Uint = 0;

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

        // Per instance data

        // per instance rotation vbo
        gl.genBuffers(1, &rotations_vbo);
        gl.bindBuffer(gl.ARRAY_BUFFER, rotations_vbo);

        // location: 2: bullet rotations
        gl.enableVertexAttribArray(2);
        gl.vertexAttribPointer(
            2,
            4,
            gl.FLOAT,
            gl.FALSE,
            SIZE_OF_QUAT,
            null,
        );
        // one rotation per bullet instance
        gl.vertexAttribDivisor(2, 1);

        // per instance position offset vbo
        gl.genBuffers(1, &positions_vbo);
        gl.bindBuffer(gl.ARRAY_BUFFER, positions_vbo);

        // location: 3: bullet position offsets
        gl.enableVertexAttribArray(3);
        gl.vertexAttribPointer(
            3,
            3,
            gl.FLOAT,
            gl.FALSE,
            SIZE_OF_VEC3,
            null,
        );
        // one offset per bullet instance
        gl.vertexAttribDivisor(3, 1);

        self.bullet_vao = bullet_vao;
        self.rotations_vbo = rotations_vbo;
        self.positions_vbo = positions_vbo;
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

        // bind and load bullet rotations
        gl.bindBuffer(gl.ARRAY_BUFFER, self.rotations_vbo);
        gl.bufferData(
            gl.ARRAY_BUFFER,
            @intCast(self.all_bullet_rotations.items.len * SIZE_OF_QUAT),
            self.all_bullet_rotations.items.ptr,
            gl.STREAM_DRAW,
        );

        // bind and load bullet positions
        gl.bindBuffer(gl.ARRAY_BUFFER, self.positions_vbo);
        gl.bufferData(
            gl.ARRAY_BUFFER,
            @intCast(self.all_bullet_positions.items.len * SIZE_OF_VEC3),
            self.all_bullet_positions.items.ptr,
            gl.STREAM_DRAW,
        );

        // draw all bullet instances
        gl.drawElementsInstanced(
            gl.TRIANGLES,
            INDICES.len, // 6,
            gl.UNSIGNED_INT,
            null,
            @intCast(self.all_bullet_positions.items.len),
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

        const scale: f32 = 2.0; // 0.25f32;

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

pub fn rotateByQuat(v: *Vec3, q: *Quat) Vec3 {
    const q_prime = Quat.from_xyzw(q.w, -q.x, -q.y, -q.z);
    return partialHamiltonProduct(&partialHamiltonProduct2(q, v), &q_prime);
}

pub fn partialHamiltonProduct2(quat: *Quat, vec: *Vec3) Quat {
    return Quat.from_xyzw(
        quat.w * vec.x + quat.y * vec.z - quat.z * vec.y,
        quat.w * vec.y - quat.x * vec.z + quat.z * vec.x,
        quat.w * vec.z + quat.x * vec.y - quat.y * vec.x,
        -quat.x * vec.x - quat.y * vec.y - quat.z * vec.z,
    );
}

pub fn partialHamiltonProduct(q1: *Quat, q2: *Quat) Vec3 {
    return vec3(
        q1.w * q2.x + q1.x * q2.w + q1.y * q2.z - q1.z * q2.y,
        q1.w * q2.y - q1.x * q2.z + q1.y * q2.w + q1.z * q2.x,
        q1.w * q2.z + q1.x * q2.y - q1.y * q2.x + q1.z * q2.w,
    );
}

fn hamiltonProductQuatVec(quat: *Quat, vec: *Vec3) Quat {
    return Quat.from_xyzw(
        quat.w * vec.x + quat.y * vec.z - quat.z * vec.y,
        quat.w * vec.y - quat.x * vec.z + quat.z * vec.x,
        quat.w * vec.z + quat.x * vec.y - quat.y * vec.x,
        -quat.x * vec.x - quat.y * vec.y - quat.z * vec.z,
    );
}

fn hamiltonProductQuatQuat(first: Quat, other: *Quat) Quat {
    return Quat.from_xyzw(
        first.w * other.x + first.x * other.w + first.y * other.z - first.z * other.y,
        first.w * other.y - first.x * other.z + first.y * other.w + first.z * other.x,
        first.w * other.z + first.x * other.y - first.y * other.x + first.z * other.w,
        first.w * other.w - first.x * other.x - first.y * other.y - first.z * other.z,
    );
}

test "bullets.test_oriented_rotation" {
    const canonical_dir = vec3(0.0, 0.0, -1.0);

    for (0..361) |angle| {
        const x_sin = math.sin(math.degreesToRadians(angle));
        const y_cos = math.cos(math.degreesToRadians(angle));

        const direction = vec3(x_sin, 0.0, y_cos);

        const normalized_direction = direction; //.normalize_or_zero();

        const rot_vec = vec3(0.0, 1.0, 0.0); // rotate around y

        const x = vec3(canonical_dir.x, 0.0, canonical_dir.z).normalize_or_zero();
        const y = vec3(normalized_direction.x, 0.0, normalized_direction.z).normalize_or_zero();

        // direction angle with respect to the canonical direction
        const theta = geom.orientedAngle(x, y, rot_vec) * -1.0;

        std.debug.print("angle: {d}  direction: {any}   theta: {d}", .{ angle, normalized_direction, theta });
    }
}
