const std = @import("std");
const cglm = @import("cglm.zig").CGLM;
const vec = @import("vec.zig");
const mat4_ = @import("mat4.zig");
const utils = @import("utils.zig");

const Vec3 = vec.Vec3;
const Vec4 = vec.Vec4;
const Mat4 = mat4_.Mat4;
pub const Versor = [4]f32;

pub const asCF32 = utils.asCF32;

pub fn quat(x: f32, y: f32, z: f32, w: f32) Quat {
    return Quat{ .data = .{ x, y, z, w } };
}

pub const Quat = extern struct {
    data: [4]f32,

    const Self = @This();

    pub fn identity() Self {
        return Quat{ .data = .{ 0.0, 0.0, 0.0, 1.0 } };
    }

    pub fn default() Self {
        return Quat{ .data = .{ 0.0, 0.0, 0.0, 1.0 } };
    }

    pub fn init(x: f32, y: f32, z: f32, w: f32) Self {
        return Quat{ .data = .{ x, y, z, w } };
    }

    pub fn clone(self: *const Self) Quat {
        return Quat{ .data = self.data };
    }

    pub fn fromArray(val: [4]f32) Self {
        return Quat{ .data = .{ val[0], val[1], val[2], val[3] } };
    }

    pub fn fromMat4(mat4: Mat4) Quat {
        var result: Quat = undefined;
        cglm.glmc_mat4_quat(@constCast(&mat4.data), result.asCPtrF32());
        return result;
    }

    pub fn fromAxisAngle(axis: *const Vec3, angle: f32) Quat {
        // glam_assert!(axis.is_normalized());
        const normalized_axis = axis.normalizeTo();
        const s = std.math.sin(angle * 0.5);
        const c = std.math.cos(angle * 0.5);
        const v = normalized_axis.mulScalar(s);
        return init(v.x, v.y, v.z, c);
    }

    pub inline fn asCPtrF32(q: *const Quat) [*c]f32 {
        return @as([*c]f32, @ptrCast(@constCast(q)));
    }

    pub fn normalize(self: *Self) void {
        cglm.glmc_quat_normalize(&self.data);
    }

    pub fn normalizeTo(q: *const Quat) Quat {
        var result: [4]f32 = undefined;
        cglm.glmc_quat_normalize_to(@as([*c]f32, @ptrCast(@constCast(q))), &result);
        return @as(*Quat, @ptrCast(&result)).*;
    }

    pub fn mulQuat(p: *const Quat, q: *const Quat) Quat {
        var result: [4]f32 = undefined;
        cglm.glmc_quat_mul(@constCast(&p.data), @constCast(&q.data), &result);
        return Quat{ .data = result };
    }

    pub fn mulByQuat(self: *Self, other: *const Quat) void {
        var result: [4]f32 = undefined;
        cglm.glmc_quat_mul(&self.data, @constCast(&other.data), &result);
        self.data = result;
    }

    pub fn rotateVec(self: *const Self, v: *const Vec3) Vec3 {
        var result: [3]f32 = undefined;
        cglm.glmc_quat_rotatev(@constCast(&self.data), @as(*[3]f32, @ptrCast(@alignCast(@constCast(v)))), &result);
        return Vec3.fromArray(result);
    }

    pub fn slerp(self: *const Self, rot: *const Quat, t: f32) Quat {
        var result: [4]f32 = undefined;
        cglm.glmc_quat_slerp(@constCast(&self.data), @constCast(&rot.data), t, &result);
        return Quat{ .data = result };
    }

    pub fn toAxes(rotation: *const Quat) [3]Vec4 {
        // glam_assert!(rotation.is_normalized());
        const normalized_rotation = rotation.normalizeTo();
        const x = normalized_rotation.data[0];
        const y = normalized_rotation.data[1];
        const z = normalized_rotation.data[2];
        const w = normalized_rotation.data[3];
        const x2 = x + x;
        const y2 = y + y;
        const z2 = z + z;
        const xx = x * x2;
        const xy = x * y2;
        const xz = x * z2;
        const yy = y * y2;
        const yz = y * z2;
        const zz = z * z2;
        const wx = w * x2;
        const wy = w * y2;
        const wz = w * z2;

        const x_axis: Vec4 = Vec4.init(1.0 - (yy + zz), xy + wz, xz - wy, 0.0);
        const y_axis: Vec4 = Vec4.init(xy - wz, 1.0 - (xx + zz), yz + wx, 0.0);
        const z_axis: Vec4 = Vec4.init(xz + wy, yz - wx, 1.0 - (xx + yy), 0.0);
        return .{ x_axis, y_axis, z_axis };
    }

    pub fn lookAtOrientation(position: Vec3, target: Vec3, up: Vec3) Quat {
        var dir = target.sub(&position);
        if (dir.lengthSquared() == 0.0) {
            return Quat.identity();
        }
        dir.normalize();

        var up_normalized = up;
        up_normalized.normalize();

        var result: Quat = Quat.identity();
        cglm.glmc_quat_for(
            dir.asCPtrF32(),
            up_normalized.asCPtrF32(),
            result.asCPtrF32(),
        );

        return result;
    }
};
