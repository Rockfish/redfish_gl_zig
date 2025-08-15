const std = @import("std");
const math = @import("math");

const Vec3 = math.Vec3;
const vec3 = math.vec3;
const Mat4 = math.Mat4;
const Quat = math.Quat;

pub const Transform = struct {
    translation: Vec3,
    rotation: Quat,
    scale: Vec3,

    const Self = @This();

    pub fn init() Transform {
        return Transform{
            .translation = vec3(0.0, 0.0, 0.0),
            .rotation = Quat{ .data = [4]f32{ 0.0, 0.0, 0.0, 1.0 } },
            .scale = vec3(1.0, 1.0, 1.0),
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
        self.translation = Vec3.zero();
        self.rotation = Quat.identity();
        self.scale = Vec3.one();
    }

    /// Blends this transform with another `transform` based on the given `weight`.
    /// The `weight` should be in the range [0.0, 1.0], where 0.0 means no influence from the other transform,
    /// and 1.0 means full influence from the other transform.
    pub fn blendTransforms(self: *const Transform, transform: Transform, weight: f32) Transform {
        const translation = self.translation.lerp(&transform.translation, weight);
        const rotation = self.rotation.slerp(&transform.rotation, weight);
        const scale = self.scale.lerp(&transform.scale, weight);
        return Transform{
            .translation = translation,
            .rotation = rotation,
            .scale = scale,
        };
    }

    /// Composes or multiply this transform with another transform.
    pub fn composeTransforms(self: *const Transform, transform: Transform) Transform {
        const translation = self.transformPoint(transform.translation);
        const rotation = Quat.mulQuat(&self.rotation, &transform.rotation);
        const scale = self.scale.mul(&transform.scale);
        return Transform{
            .translation = translation,
            .rotation = rotation,
            .scale = scale,
        };
    }

    /// Transforms the given `point`, applying scale, rotation and translation.
    pub fn transformPoint(self: *const Self, in_point: Vec3) Vec3 {
        var point = self.scale.mul(&in_point);
        point = self.rotation.rotateVec(&point);
        point = self.translation.add(&point);
        return point;
    }

    pub fn toMatrix(self: *const Self) Mat4 {
        return Mat4.fromTranslationRotationScale(&self.translation, &self.rotation, &self.scale);
    }

    pub fn asString(self: *const Self, buf: []u8) [:0]u8 {
        return std.fmt.bufPrintZ(
            buf,
            "{{.translation={{{d}, {d}, {d}}} .rotation={{{d}, {d}, {d}, {d}}} .scale={{{d}, {d}, {d}}}}}",
            .{
                self.translation.x,
                self.translation.y,
                self.translation.z,
                self.rotation.data[0],
                self.rotation.data[1],
                self.rotation.data[2],
                self.rotation.data[3],
                self.scale.x,
                self.scale.y,
                self.scale.z,
            },
        ) catch @panic("bufPrintZ error.");
    }

    pub fn equal(self: *const Self, other: Transform) bool {
        // zig fmt: off
        return self.translation.x == other.translation.x
            and self.translation.y == other.translation.y
            and self.translation.z == other.translation.z
            and self.rotation.data[0] == other.rotation.data[0]
            and self.rotation.data[1] == other.rotation.data[1]
            and self.rotation.data[2] == other.rotation.data[2]
            and self.rotation.data[3] == other.rotation.data[3]
            and self.scale.x == self.scale.x
            and self.scale.y == self.scale.y
            and self.scale.z == self.scale.z;
    }
};
