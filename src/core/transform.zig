const std = @import("std");
const math = @import("math");

const Vec3 = math.Vec3;
const vec3 = math.vec3;
const Mat4 = math.Mat4;
const Quat = math.Quat;

/// Transform borrows heavily on Bevy's implementation.
/// By openGL convention X is right, Y is up, Z is forward
pub const Transform = struct {
    translation: Vec3,
    rotation: Quat,
    scale: Vec3,

    const Self = @This();

    pub inline fn identity() Transform {
        return Transform{
            .translation = Vec3.zero(),
            .rotation = Quat.identity(),
            .scale = Vec3.one(),
        };
    }

    pub inline fn clone(self: *const Self) Transform {
        return Transform{
            .translation = self.translation,
            .rotation = self.rotation,
            .scale = self.scale,
        };
    }

    pub inline fn clear(self: *Self) void {
        self.translation = Vec3.zero();
        self.rotation = Quat.identity();
        self.scale = Vec3.one();
    }

    /// Creates Transform at point x,y,z
    pub inline fn fromXYZ(x: f32, y: f32, z: f32) Transform {
        return Transform{
            .translation = Vec3.init(x, y, z),
            .rotation = Quat.identity(),
            .scale = Vec3.one(),
        };
    }

    pub inline fn fromTranslation(translation: Vec3) Transform {
        return Transform{
            .translation = translation,
            .rotation = Quat.identity(),
            .scale = Vec3.one(),
        };
    }

    pub inline fn fromRotaion(rotation: Quat) Transform {
        return Transform{
            .translation = Vec3.zero(),
            .rotation = rotation,
            .scale = Vec3.one(),
        };
    }

    pub inline fn fromScale(scale: Vec3) Transform {
        return Transform{
            .translation = Vec3.zero(),
            .rotation = Quat.identity(),
            .scale = scale,
        };
    }

    pub fn fromMatrix(matrix: *const Mat4) Transform {
        const translation = matrix.getWAxis();

        const x_axis = matrix.getXAxis();
        const y_axis = matrix.getYAxis();
        const z_axis = matrix.getZAxis();

        const scale = Vec3.init(
            x_axis.length(),
            y_axis.length(),
            z_axis.length(),
        );

        const inv_scale = scale.recip();

        const rotation_matrix = Mat4{ .data = .{
            .{ x_axis.x * inv_scale.x, x_axis.y * inv_scale.x, x_axis.z * inv_scale.x, 0.0 },
            .{ y_axis.x * inv_scale.y, y_axis.y * inv_scale.y, y_axis.z * inv_scale.y, 0.0 },
            .{ z_axis.x * inv_scale.z, z_axis.y * inv_scale.z, z_axis.z * inv_scale.z, 0.0 },
            .{ 0.0, 0.0, 0.0, 1.0 },
        } };

        const rotation = rotation_matrix.toQuat();

        return Transform{
            .translation = translation,
            .rotation = rotation,
            .scale = scale,
        };
    }

    pub fn toMatrix(self: *const Self) Mat4 {
        return Mat4.fromTranslationRotationScale(
            &self.translation,
            &self.rotation,
            &self.scale,
        );
    }

    /// Returns the view matrix (inverse transform) for use as a camera view matrix.
    /// This is equivalent to Mat4.lookAtRhGl() when the transform represents a camera.
    /// The view matrix transforms world-space coordinates into camera-space coordinates.
    pub fn toViewMatrix(self: *const Self) Mat4 {
        const rot_mat = Mat4.fromQuat(&self.rotation);

        // Extract basis vectors (columns of rotation matrix)
        const right = rot_mat.getXAxis();
        const up = rot_mat.getYAxis();
        const back = rot_mat.getZAxis();

        // View matrix: transpose of rotation (each column contains one component from all basis vectors)
        // This matches lookAtRhGl format: data[col] = [right.col, up.col, -forward.col, 0]
        // Since back = -forward, then -forward = back, so we use back directly
        return Mat4{ .data = .{
            .{ right.x, up.x, back.x, 0.0 },
            .{ right.y, up.y, back.y, 0.0 },
            .{ right.z, up.z, back.z, 0.0 },
            .{
                -right.dot(&self.translation),
                -up.dot(&self.translation),
                -back.dot(&self.translation),
                1.0,
            },
        } };
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

    /// Rotates this Transform so that it looks in the given direction.
    /// The forward direction (negative Z-axis in OpenGL convention) will point in the given direction.
    /// The up vector determines the orientation around that direction.
    ///
    /// Fallback behavior (matching Bevy's implementation):
    /// - If direction cannot be normalized (zero vector), uses (0, 0, -1) as default (NEG_Z)
    /// - If up cannot be normalized, uses (0, 1, 0) as default (Y)
    /// - If direction is parallel to up, finds an orthogonal vector for the right direction
    pub fn lookTo(self: *Self, direction: Vec3, up: Vec3) void {
        // Back is opposite of forward direction (Bevy uses NEG_Z as forward default)
        const back_unnormalized = direction.mulScalar(-1.0);
        const back = blk: {
            const normalized = back_unnormalized.toNormalized();
            // toNormalized returns zero vector if input is zero length
            if (normalized.lengthSquared() == 0.0) {
                break :blk Vec3.init(0.0, 0.0, -1.0); // NEG_Z default
            }
            break :blk normalized;
        };

        const up_norm = blk: {
            const normalized = up.toNormalized();
            if (normalized.lengthSquared() == 0.0) {
                break :blk Vec3.init(0.0, 1.0, 0.0); // Y default
            }
            break :blk normalized;
        };

        // Compute right vector (perpendicular to both up and back)
        const right_vec = up_norm.cross(&back);
        const right = blk: {
            const normalized = right_vec.toNormalized();
            if (normalized.lengthSquared() == 0.0) {
                // If up and back are parallel, find any orthonormal vector to up
                // Strategy: use a vector that's not parallel to up_norm, cross it
                const arbitrary = if (@abs(up_norm.y) < 0.9)
                    Vec3.init(0.0, 1.0, 0.0)
                else
                    Vec3.init(1.0, 0.0, 0.0);
                const ortho = up_norm.cross(&arbitrary);
                break :blk ortho.toNormalized();
            }
            break :blk normalized;
        };

        // Recompute up to ensure orthogonality (back cross right)
        const final_up = back.cross(&right);

        // Create rotation matrix from basis vectors (column-major format)
        // Columns are: right, up, back (matching Bevy's Mat3::from_cols)
        const rotation_matrix = Mat4{ .data = .{
            .{ right.x, right.y, right.z, 0.0 },
            .{ final_up.x, final_up.y, final_up.z, 0.0 },
            .{ back.x, back.y, back.z, 0.0 },
            .{ 0.0, 0.0, 0.0, 1.0 },
        } };

        self.rotation = rotation_matrix.toQuat();
    }

    /// Rotates this Transform to look at the given target position.
    /// The forward direction (negative Z-axis in OpenGL convention) will point towards the target.
    /// The up vector determines the orientation around that direction.
    ///
    /// Fallback behavior:
    /// - If target equals translation (zero direction), uses default forward direction
    /// - Other fallbacks same as lookTo
    pub fn lookAt(self: *Self, target: Vec3, up: Vec3) void {
        const direction = target.sub(&self.translation);
        self.lookTo(direction, up);
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
};
