// Simple bullet system for testing patterns
const std = @import("std");
const core = @import("core");
const math = @import("math");
const containers = @import("containers");
const gl = @import("zopengl").bindings;

const Allocator = std.mem.Allocator;
const ManagedArrayList = containers.ManagedArrayList;
const Shader = core.Shader;
const Shape = core.shapes.Shape;
const Transform = core.Transform;
const Lines = core.shapes.Lines;
const LineSegment = core.shapes.LineSegment;
const Color = core.Color;
const Vec3 = math.Vec3;
const vec3 = math.vec3;
const vec4 = math.vec4;
const Mat4 = math.Mat4;
const Quat = math.Quat;
const uniforms = core.constants.Uniforms;

// const State = state_mod.State;
pub const BULLET_SCALE: f32 = 2.0;
pub const BULLET_LIFETIME: f32 = 10.0;
pub const Bullet_Speed: f32 = 2.0;

pub const Bullets_Per_Side: i32 = 3;
pub const Spread_Degrees: f32 = 10.0;

const Forward_Dir: Vec3 = vec3(0.0, 0.0, -1.0);

// pub const Bullet = struct {
//     position: Vec3,
//     direction: Vec3, // initial direction, seems it must constant
//     speed: f32,
//     rotation_mat: Mat4,
//     lifetime: f32 = 10.0,
// };

var buf: [500]u8 = undefined;
pub const BulletSystem = struct {
    allocator: Allocator,
    shader: *Shader,
    gravity: f32 = 0.2,
    x_rotations: ManagedArrayList(Quat),
    y_rotations: ManagedArrayList(Quat),
    bullet_positions: ManagedArrayList(Vec3),
    bullet_rotations: ManagedArrayList(Quat),
    bullet_rotations_initial: ManagedArrayList(Quat),
    bullet_directions: ManagedArrayList(Vec3),
    bullet_velocities: ManagedArrayList(Vec3),
    bullet_right_vectors: ManagedArrayList(Vec3),
    bullet_cube: core.shapes.Shape,
    rotations_vbo: gl.Uint = 0,
    positions_vbo: gl.Uint = 0,
    line_shader: *Shader,
    lines: Lines,
    is_lines_visible: bool = false,
    plain_cube: core.shapes.Shape,
    plain_cube_shader: *Shader,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Self {
        const instanced_shader = try Shader.init(
            allocator,
            "examples/bullets/shaders/instanced_quats.vert",
            "examples/bullets/shaders/basic_model.frag",
        );

        const cubemap_texture = try core.texture.Texture.initFromFile(
            allocator,
            "assets/Textures/cubemap_template_2x3.png",
            .{
                .flip_v = false,
                .gamma_correction = false,
                .filter = .Linear,
                .wrap = .Clamp,
            },
        );

        instanced_shader.setBool(uniforms.Has_Texture, true);
        instanced_shader.bindTextureAuto(uniforms.Texture_Diffuse, cubemap_texture.gl_texture_id);

        var x_rotations = ManagedArrayList(Quat).init(allocator);
        var y_rotations = ManagedArrayList(Quat).init(allocator);

        const radians_per_bullet: f32 = math.degreesToRadians(Spread_Degrees);
        const num_bullets_per_side: f32 = @floatFromInt(Bullets_Per_Side);
        const spread_centering = (num_bullets_per_side - 1.0) * radians_per_bullet * 0.5;

        for (0..Bullets_Per_Side) |i| {
            const angle: f32 = radians_per_bullet * @as(f32, @floatFromInt(i)) - spread_centering;
            const y_rot = Quat.fromAxisAngle(vec3(0.0, 1.0, 0.0), angle);
            const x_rot = Quat.fromAxisAngle(vec3(1.0, 0.0, 0.0), angle);
            try x_rotations.append(x_rot);
            try y_rotations.append(y_rot);
        }

        const cube_config: core.shapes.CubeConfig = .{
            .width = 1.0,
            .height = 1.0,
            .depth = 1.0,
            .num_tiles_x = 1.0,
            .num_tiles_y = 1.0,
            .num_tiles_z = 1.0,
            .texture_mapping = .Cubemap2x3,
            .is_instanced = false, // bullet is handling instancing
        };

        const bullet_cube = core.shapes.createCube(cube_config) catch {};
        const plain_cube = core.shapes.createCube(cube_config) catch {};

        const plain_cube_shader = try Shader.init(
            allocator,
            "examples/bullets/shaders/basic_texture.vert",
            "examples/bullets/shaders/basic_texture.frag",
        );
        plain_cube_shader.setBool(uniforms.Has_Texture, true);
        plain_cube_shader.bindTextureAuto(uniforms.Texture_Diffuse, cubemap_texture.gl_texture_id);

        const lines_shader = try Shader.init(
            allocator,
            "examples/bullets/shaders/lines.vert",
            "examples/bullets/shaders/lines.frag",
        );

        const lines = try Lines.init(allocator, lines_shader, 10.0, 1.0, 144);

        var bullet_system: BulletSystem = .{
            .allocator = allocator,
            .shader = instanced_shader,
            .x_rotations = x_rotations,
            .y_rotations = y_rotations,
            .bullet_positions = ManagedArrayList(Vec3).init(allocator),
            .bullet_rotations = ManagedArrayList(Quat).init(allocator),
            .bullet_rotations_initial = ManagedArrayList(Quat).init(allocator),
            .bullet_directions = ManagedArrayList(Vec3).init(allocator),
            .bullet_velocities = ManagedArrayList(Vec3).init(allocator),
            .bullet_right_vectors = ManagedArrayList(Vec3).init(allocator),
            .bullet_cube = bullet_cube,
            .line_shader = lines_shader,
            .lines = lines,
            .plain_cube = plain_cube,
            .plain_cube_shader = plain_cube_shader,
        };

        bullet_system.createRotationsBuffers();

        return bullet_system;
    }

    pub fn deinit(self: *Self) void {
        self.bullet_cube.deinit();
    }

    pub fn createBullets(self: *Self, aim_transform: Transform) !void {
        const start_index = 0;
        const bullet_group_size = Bullets_Per_Side * Bullets_Per_Side;

        try self.bullet_positions.resize(start_index + bullet_group_size);
        try self.bullet_rotations.resize(start_index + bullet_group_size);
        try self.bullet_rotations_initial.resize(start_index + bullet_group_size);
        try self.bullet_directions.resize(start_index + bullet_group_size);
        try self.bullet_velocities.resize(start_index + bullet_group_size);
        try self.bullet_right_vectors.resize(start_index + bullet_group_size);

        const start: usize = start_index;
        const end = start + bullet_group_size;

        for (start..end) |index| {
            const count = index - start;
            const i = @divTrunc(count, Bullets_Per_Side);
            const j = @mod(count, Bullets_Per_Side);

            const y_rot = self.y_rotations.items()[i];
            const x_rot = self.x_rotations.items()[j];
            const x_y_rot = x_rot.mulQuat(y_rot);

            const rotation = aim_transform.rotation.mulQuat(x_y_rot);
            const direction = rotation.rotateVec(Forward_Dir);

            self.bullet_positions.items()[index] = aim_transform.translation;
            self.bullet_rotations.items()[index] = rotation;
            self.bullet_rotations_initial.items()[index] = rotation;
            self.bullet_directions.items()[index] = direction;

            const velocity = direction.mulScalar(Bullet_Speed);
            self.bullet_velocities.items()[index] = velocity;

            const down = vec3(0.0, -1.0, 0.0);
            const right = blk: {
                const r = direction.cross(down).toNormalized();
                // Handle edge case: firing straight up or down
                if (r.lengthSquared() < 0.001) {
                    break :blk vec3(1.0, 0.0, 0.0); // Arbitrary right for vertical shots
                }
                break :blk r;
            };
            _ = right;
            //self.bullet_right_vectors.items()[index] = right;
            self.bullet_right_vectors.items()[index] = self.bullet_rotations.items()[index].right();
        }
    }

    pub fn resetBullets(self: *Self, aim_transform: Transform) !void {
        try self.createBullets(aim_transform);
    }

    pub fn update_x(self: *Self, delta_time: f32) void {
        const delta = delta_time * Bullet_Speed;

        const start: usize = 0;
        const end = self.bullet_positions.items().len;

        for (start..end) |bullet_index| {
            const position = self.bullet_positions.items()[bullet_index];
            const direction = self.bullet_directions.items()[bullet_index];

            const change = direction.mulScalar(delta);
            self.bullet_positions.items()[bullet_index] = position.add(change);
        }
    }

    pub fn update(self: *Self, delta_time: f32) void {
        const gravity_vec = vec3(0.0, -self.gravity, 0.0);
        const gravity_delta = gravity_vec.mulScalar(delta_time);

        for (0..self.bullet_positions.items().len) |i| {
            var velocity = self.bullet_velocities.items()[i];
            const position = self.bullet_positions.items()[i];

            velocity = velocity.add(gravity_delta);

            self.bullet_velocities.items()[i] = velocity;
            self.bullet_positions.items()[i] = position.add(velocity.mulScalar(delta_time));

            const forward = velocity.toNormalized();

            if (forward.lengthSquared() > 0.001) {
                const right = self.bullet_right_vectors.items()[i];
                self.bullet_rotations.items()[i] = Quat.fromDirectionWithRight(forward, right);
            }
        }
    }

    pub fn drawLines(self: *Self, projection: *const Mat4, view: *const Mat4) void {
        self.line_shader.setMat4(uniforms.Mat_Projection, projection);
        self.line_shader.setMat4(uniforms.Mat_View, view);

        var transformed: [Bullets_Per_Side * Bullets_Per_Side]LineSegment = undefined;
        const start: usize = 0;
        const end: usize = self.bullet_rotations_initial.items().len;

        for (start..end) |i| {
            const rotation = self.bullet_rotations_initial.items()[i];
            const line_dir = rotation.rotateVec(Forward_Dir);
            // const line_dir = self.bullet_directions.items()[i];
            transformed[i] = .{
                .start = Vec3.Zero,
                .end = line_dir.mulScalar(10.0),
                .color = Color.yellow,
            };
        }

        self.lines.draw(&transformed, projection, view);
    }

    pub fn drawBullets(self: *Self, projection: *const Mat4, view: *const Mat4) void {
        if (self.bullet_positions.items().len == 0) {
            return;
        }

        self.shader.useShader();
        self.shader.setMat4(uniforms.Mat_Projection, projection);
        self.shader.setMat4(uniforms.Mat_View, view);

        gl.bindVertexArray(self.bullet_cube.vao);

        // rotations
        gl.bindBuffer(gl.ARRAY_BUFFER, self.rotations_vbo);
        gl.bufferData(
            gl.ARRAY_BUFFER,
            @intCast(self.bullet_rotations.items().len * @sizeOf(Quat)),
            self.bullet_rotations.items().ptr,
            gl.STREAM_DRAW,
        );

        // positions
        gl.bindBuffer(gl.ARRAY_BUFFER, self.positions_vbo);
        gl.bufferData(
            gl.ARRAY_BUFFER,
            @intCast(self.bullet_positions.items().len * @sizeOf(Vec3)),
            self.bullet_positions.items().ptr,
            gl.STREAM_DRAW,
        );

        gl.drawElementsInstanced(
            gl.TRIANGLES,
            self.bullet_cube.num_indices,
            gl.UNSIGNED_INT,
            null,
            @intCast(self.bullet_positions.items().len),
        );
    }

    pub fn draw(self: *Self, projection: *const Mat4, view: *const Mat4) void {
        if (self.is_lines_visible) self.drawLines(projection, view);
        self.drawBullets(projection, view);
    }

    fn createRotationsBuffers(self: *Self) void {
        var rotations_vbo: gl.Uint = 0;
        var positions_vbo: gl.Uint = 0;

        gl.bindVertexArray(self.bullet_cube.vao);

        // per instance rotation vbo
        gl.genBuffers(1, &rotations_vbo);
        gl.bindBuffer(gl.ARRAY_BUFFER, rotations_vbo);

        // location 8: bullet rotations (quaternion)
        gl.enableVertexAttribArray(8);
        gl.vertexAttribPointer(
            8,
            4,
            gl.FLOAT,
            gl.FALSE,
            @sizeOf(Quat),
            null,
        );
        // one rotation per bullet instance
        gl.vertexAttribDivisor(8, 1);

        // per instance position offset vbo
        gl.genBuffers(1, &positions_vbo);
        gl.bindBuffer(gl.ARRAY_BUFFER, positions_vbo);

        // location 9: bullet position offsets
        gl.enableVertexAttribArray(9);
        gl.vertexAttribPointer(
            9,
            3,
            gl.FLOAT,
            gl.FALSE,
            @sizeOf(Vec3),
            null,
        );
        // one offset per bullet instance
        gl.vertexAttribDivisor(9, 1);

        self.rotations_vbo = rotations_vbo;
        self.positions_vbo = positions_vbo;
    }
};
