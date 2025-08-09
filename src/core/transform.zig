const std = @import("std");
const math = @import("math");

const Allocator = std.mem.Allocator;

const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const vec2 = math.vec2;
const vec3 = math.vec3;
const vec4 = math.vec4;
const Mat4 = math.Mat4;
const Quat = math.Quat;

pub const Transform = struct {
    translation: ?Vec3,
    rotation: ?Quat,
    scale: ?Vec3,

    const Self = @This();

    pub fn init() Transform {
        return Transform{
            .translation = null,
            .rotation = null,
            .scale = null,
        };
    }

    pub fn identity() Transform {
        return Transform{
            .translation = vec3(0.0, 0.0, 0.0),
            .rotation = Quat{ .data = [4]f32{ 0.0, 0.0, 0.0, 1.0 } },
            .scale = vec3(1.0, 1.0, 1.0),
        };
    }

    pub fn clone(self: *const Self) Transform {
        return Transform{
            .translation = self.translation,
            .rotation = self.rotation,
            .scale = self.scale,
        };
    }

    pub fn fromMatrix(m: *const Mat4) Transform {
        return extractTransformFromMatrix(m);
    }

    fn extractTransformFromMatrix(matrix: *const Mat4) Transform {
        // Extract translation (last column)
        const translation = Vec3.init(matrix.data[3][0], matrix.data[3][1], matrix.data[3][2]);

        // Extract scale (length of first three columns)
        const scale_x = std.math.sqrt(matrix.data[0][0] * matrix.data[0][0] + matrix.data[1][0] * matrix.data[1][0] + matrix.data[2][0] * matrix.data[2][0]);
        const scale_y = std.math.sqrt(matrix.data[0][1] * matrix.data[0][1] + matrix.data[1][1] * matrix.data[1][1] + matrix.data[2][1] * matrix.data[2][1]);
        const scale_z = std.math.sqrt(matrix.data[0][2] * matrix.data[0][2] + matrix.data[1][2] * matrix.data[1][2] + matrix.data[2][2] * matrix.data[2][2]);
        const extracted_scale = Vec3.init(scale_x, scale_y, scale_z);

        // Remove scale to get pure rotation matrix
        const rotation_matrix = Mat4{ .data = .{
            .{ matrix.data[0][0] / scale_x, matrix.data[0][1] / scale_y, matrix.data[0][2] / scale_z, 0.0 },
            .{ matrix.data[1][0] / scale_x, matrix.data[1][1] / scale_y, matrix.data[1][2] / scale_z, 0.0 },
            .{ matrix.data[2][0] / scale_x, matrix.data[2][1] / scale_y, matrix.data[2][2] / scale_z, 0.0 },
            .{ 0.0, 0.0, 0.0, 1.0 },
        } };

        // Convert rotation matrix to quaternion
        const rotation = rotation_matrix.toQuat();

        return Transform{
            .translation = translation,
            .rotation = rotation,
            .scale = extracted_scale,
        };
    }

    pub fn clear(self: *Self) void {
        self.translation = null;
        self.rotation = null;
        self.scale = null;
    }

    pub fn mulTransformWeighted(self: *const Self, transform: Transform, weight: f32) Self {
        const translation = if (self.translation != null and transform.translation != null)
            self.translation.?.lerp(&transform.translation.?, weight)
        else
            transform.translation orelse self.translation;

        const rotation = if (self.rotation != null and transform.rotation != null)
            self.rotation.?.slerp(&transform.rotation.?, weight)
        else
            transform.rotation orelse self.rotation;

        const scale = if (self.scale != null and transform.scale != null)
            self.scale.?.lerp(&transform.scale.?, weight)
        else
            transform.scale orelse self.scale;

        return Transform{
            .translation = translation,
            .rotation = rotation,
            .scale = scale,
        };
    }

    pub fn mulTransform(self: *const Self, transform: Transform) Self {
        const translation = if (transform.translation) |t|
            if (self.translation != null or self.rotation != null or self.scale != null)
                self.transformPoint(t)
            else
                t
        else
            self.translation;

        const rotation = if (self.rotation != null and transform.rotation != null)
            Quat.mulQuat(&self.rotation.?, &transform.rotation.?)
        else
            transform.rotation orelse self.rotation;

        const scale = if (self.scale != null and transform.scale != null)
            self.scale.?.mul(&transform.scale.?)
        else
            transform.scale orelse self.scale;

        return Transform{
            .translation = translation,
            .rotation = rotation,
            .scale = scale,
        };
    }

    pub fn transformPoint(self: *const Self, point: Vec3) Vec3 {
        var _point = if (self.scale) |s| s.mul(&point) else point;
        _point = if (self.rotation) |r| r.rotateVec(&_point) else _point;
        _point = if (self.translation) |t| t.add(&_point) else _point;
        return _point;
    }

    pub fn toMatrix(self: *const Self) Mat4 {
        const translation = self.translation orelse vec3(0.0, 0.0, 0.0);
        const rotation = self.rotation orelse Quat{ .data = [4]f32{ 0.0, 0.0, 0.0, 1.0 } };
        const scale = self.scale orelse vec3(1.0, 1.0, 1.0);
        return Mat4.fromTranslationRotationScale(&translation, &rotation, &scale);
    }

    pub fn asString(self: *const Self, buf: []u8) [:0]u8 {
        const t = self.translation orelse vec3(0.0, 0.0, 0.0);
        const r = self.rotation orelse Quat{ .data = [4]f32{ 0.0, 0.0, 0.0, 1.0 } };
        const s = self.scale orelse vec3(1.0, 1.0, 1.0);
        return std.fmt.bufPrintZ(
            buf,
            "{{.translation={{{d}, {d}, {d}}} .rotation={{{d}, {d}, {d}, {d}}} .scale={{{d}, {d}, {d}}}}}",
            .{ t.x, t.y, t.z, r.data[0], r.data[1], r.data[2], r.data[3], s.x, s.y, s.z },
        ) catch @panic("bufPrintZ error.");
    }

    pub fn equal(self: *const Self, other: Transform) bool {
        const self_t = self.translation;
        const other_t = other.translation;
        const self_r = self.rotation;
        const other_r = other.rotation;
        const self_s = self.scale;
        const other_s = other.scale;

        // Check if both are null or both have same values
        const trans_equal = (self_t == null and other_t == null) or
            (self_t != null and other_t != null and self_t.?.x == other_t.?.x and self_t.?.y == other_t.?.y and self_t.?.z == other_t.?.z);

        const rot_equal = (self_r == null and other_r == null) or
            (self_r != null and other_r != null and self_r.?.data[0] == other_r.?.data[0] and self_r.?.data[1] == other_r.?.data[1] and self_r.?.data[2] == other_r.?.data[2] and self_r.?.data[3] == other_r.?.data[3]);

        const scale_equal = (self_s == null and other_s == null) or
            (self_s != null and other_s != null and self_s.?.x == other_s.?.x and self_s.?.y == other_s.?.y and self_s.?.z == other_s.?.z);

        return trans_equal and rot_equal and scale_equal;
    }
};
