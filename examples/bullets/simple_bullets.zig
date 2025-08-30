// Simple bullet system for testing patterns
const std = @import("std");
const core = @import("core");
const math = @import("math");
const state_mod = @import("state.zig");
const gl = @import("zopengl").bindings;

const ArrayList = std.ArrayList;
const Shader = core.Shader;
const Vec3 = math.Vec3;
const vec3 = math.vec3;
const Mat4 = math.Mat4;
const Quat = math.Quat;

const State = state_mod.State;

pub const Bullet = struct {
    position: Vec3,
    velocity: Vec3,
    lifetime: f32,

    const Self = @This();

    pub fn init(position: Vec3, direction: Vec3, speed: f32) Self {
        return .{
            .position = position,
            .velocity = direction.mulScalar(speed),
            .lifetime = state_mod.BULLET_LIFETIME,
        };
    }

    pub fn update(self: *Self, delta_time: f32) void {
        self.position = self.position.add(&self.velocity.mulScalar(delta_time));
        self.lifetime -= delta_time;
    }

    pub fn isAlive(self: *const Self) bool {
        return self.lifetime > 0.0;
    }
};

pub const SimpleBulletStore = struct {
    bullets: ArrayList(Bullet),
    vao: gl.Uint,
    vbo: gl.Uint,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        var vao: gl.Uint = 0;
        var vbo: gl.Uint = 0;

        // Create simple point rendering
        gl.genVertexArrays(1, &vao);
        gl.genBuffers(1, &vbo);

        return .{
            .bullets = ArrayList(Bullet).init(allocator),
            .vao = vao,
            .vbo = vbo,
        };
    }

    pub fn deinit(self: *Self) void {
        self.bullets.deinit();
        gl.deleteVertexArrays(1, &self.vao);
        gl.deleteBuffers(1, &self.vbo);
    }

    pub fn fireBulletPattern(self: *Self, origin: Vec3, direction: f32, count: i32) !void {
        const spread_angle = 0.2; // radians

        for (0..@intCast(count)) |i| {
            const offset_angle = direction + spread_angle * (@as(f32, @floatFromInt(i)) - @as(f32, @floatFromInt(count)) / 2.0);
            const bullet_dir = vec3(@sin(offset_angle), 0.0, @cos(offset_angle));
            const bullet = Bullet.init(origin, bullet_dir, state_mod.BULLET_SPEED);
            try self.bullets.append(bullet);
        }
    }

    pub fn update(self: *Self, delta_time: f32) void {
        // Update all bullets
        for (self.bullets.items) |*bullet| {
            bullet.update(delta_time);
        }

        // Remove dead bullets (simplified - normally would use retain)
        var alive_count: usize = 0;
        for (self.bullets.items) |bullet| {
            if (bullet.isAlive()) {
                if (alive_count != self.bullets.items.len) {
                    self.bullets.items[alive_count] = bullet;
                }
                alive_count += 1;
            }
        }
        self.bullets.shrinkRetainingCapacity(alive_count);
    }

    pub fn render(self: *Self, shader: *Shader, projection_view: *const Mat4) void {
        if (self.bullets.items.len == 0) return;

        shader.useShader();
        shader.setMat4("projectionView", projection_view);
        shader.setVec3("color", &vec3(1.0, 1.0, 0.0)); // Yellow bullets

        // Upload bullet positions
        var positions = std.ArrayList(f32).init(self.bullets.allocator);
        defer positions.deinit();

        for (self.bullets.items) |bullet| {
            positions.append(bullet.position.x) catch {};
            positions.append(bullet.position.y) catch {};
            positions.append(bullet.position.z) catch {};
        }

        gl.bindVertexArray(self.vao);
        gl.bindBuffer(gl.ARRAY_BUFFER, self.vbo);
        gl.bufferData(gl.ARRAY_BUFFER, @intCast(positions.items.len * @sizeOf(f32)), positions.items.ptr, gl.DYNAMIC_DRAW);

        gl.enableVertexAttribArray(0);
        gl.vertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, 3 * @sizeOf(f32), null);

        gl.pointSize(5.0);
        gl.drawArrays(gl.POINTS, 0, @intCast(self.bullets.items.len));
    }
};
