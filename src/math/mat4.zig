const std = @import("std");
const cglm = @import("cglm.zig").CGLM;
const _vec = @import("vec.zig");
const _quat = @import("quat.zig");

const Vec3 = _vec.Vec3;
const Vec4 = _vec.Vec4;
const Quat = _quat.Quat;

pub fn mat4(x_axis: Vec4, y_axis: Vec4, z_axis: Vec4, w_axis: Vec4) Mat4 {
    return Mat4.fromColumns(x_axis, y_axis, z_axis, w_axis);
}

pub const Mat4 = extern struct {
    data: [4][4]f32,

    const Self = @This();

    pub fn identity() Self {
        return Mat4{ .data = .{
            .{ 1.0, 0.0, 0.0, 0.0 },
            .{ 0.0, 1.0, 0.0, 0.0 },
            .{ 0.0, 0.0, 1.0, 0.0 },
            .{ 0.0, 0.0, 0.0, 1.0 },
        } };
    }

    pub fn zero() Self {
        return Mat4{ .data = .{
            .{ 0.0, 0.0, 0.0, 0.0 },
            .{ 0.0, 0.0, 0.0, 0.0 },
            .{ 0.0, 0.0, 0.0, 0.0 },
            .{ 0.0, 0.0, 0.0, 0.0 },
        } };
    }

    pub fn fromColumns(x_axis: Vec4, y_axis: Vec4, z_axis: Vec4, w_axis: Vec4) Self {
        return Mat4{ .data = .{
            x_axis.asArray(),
            y_axis.asArray(),
            z_axis.asArray(),
            w_axis.asArray(),
        } };
    }

    pub fn toArray(self: *const Self) [16]f32 {
        return @as(*[16]f32, @ptrCast(@constCast(self))).*;
    }

    pub fn toArrayPtr(self: *const Self) *[16]f32 {
        return @as(*[16]f32, @ptrCast(@constCast(self)));
    }

    pub fn getTranspose(m: *const Mat4) Mat4 {
        var result: [4][4]f32 = undefined;
        cglm.glmc_mat4_transpose_to(@constCast(&m.data), &result);
        return Mat4{ .data = result };
    }

    pub fn getInverse(m: *const Mat4) Self {
        var result: [4][4]f32 = undefined;
        cglm.glmc_mat4_inv(@constCast(&m.data), &result);
        return Mat4{ .data = result };
    }

    pub fn fromTranslation(t: *const Vec3) Self {
        return Mat4{ .data = .{
            .{ 1.0, 0.0, 0.0, 0.0 },
            .{ 0.0, 1.0, 0.0, 0.0 },
            .{ 0.0, 0.0, 1.0, 0.0 },
            .{ t.x, t.y, t.z, 1.0 },
        } };
    }

    pub fn fromScale(s: *const Vec3) Self {
        return Mat4{ .data = .{
            .{ s.x, 0.0, 0.0, 0.0 },
            .{ 0.0, s.y, 0.0, 0.0 },
            .{ 0.0, 0.0, s.z, 0.0 },
            .{ 0.0, 0.0, 0.0, 1.0 },
        } };
    }

    pub fn fromRotationX(angle: f32) Mat4 {
        var result: [4][4]f32 = undefined;
        const axis: [3]f32 = .{ 1.0, 0.0, 0.0 };
        cglm.glmc_rotate_make(&result, angle, @as([*c]f32, @ptrCast(@constCast(&axis))));
        return Mat4{ .data = result };
    }

    pub fn fromRotationY(angle: f32) Mat4 {
        var result: [4][4]f32 = undefined;
        const axis: [3]f32 = .{ 0.0, 1.0, 0.0 };
        cglm.glmc_rotate_make(&result, angle, @as([*c]f32, @ptrCast(@constCast(&axis))));
        return Mat4{ .data = result };
    }

    pub fn fromRotationZ(angle: f32) Mat4 {
        var result: [4][4]f32 = undefined;
        const axis: [3]f32 = .{ 0.0, 0.0, 1.0 };
        cglm.glmc_rotate_make(&result, angle, @as([*c]f32, @ptrCast(@constCast(&axis))));
        return Mat4{ .data = result };
    }

    pub fn fromAxisAngle(axis: *const Vec3, angleRadians: f32) Mat4 {
        var result: [4][4]f32 = undefined;
        cglm.glmc_rotate_make(&result, angleRadians, @as([*c]f32, @ptrCast(@constCast(axis))));
        return Mat4{ .data = result };
    }

    pub fn translate(self: *Self, translationVec3: *const Vec3) void {
        cglm.glmc_translate(@constCast(&self.data), @as([*c]f32, @ptrCast(@constCast(translationVec3))));
    }

    pub fn scale(self: *Self, scaleVec3: *const Vec3) void {
        cglm.glmc_scale(@constCast(&self.data), @as([*c]f32, @ptrCast(@constCast(scaleVec3))));
    }

    pub fn rotateByDegrees(self: *Self, axis: *const Vec3, angleDegrees: f32) void {
        cglm.glmc_rotated(@constCast(&self.data), std.math.degreesToRadians(angleDegrees), @ptrCast(@constCast(axis)));
    }

    pub fn mulMat4(self: *const Self, other: *const Mat4) Self {
        var result: [4][4]f32 = undefined;
        cglm.glmc_mat4_mul(@constCast(&self.data), @constCast(&other.data), &result);
        return Mat4{ .data = result };
    }

    pub fn mulByMat4(self: *Self, other: *const Mat4) void {
        var result: [4][4]f32 = undefined;
        cglm.glmc_mat4_mul(@constCast(&self.data), @constCast(&other.data), &result);
        self.data = result;
    }

    pub fn mulVec4(self: *const Self, vec: *const Vec4) Vec4 {
        var result: [4]f32 = undefined;
        cglm.glmc_mat4_mulv(@constCast(&self.data), @as([*c]f32, @ptrCast(@constCast(vec))), &result);
        return @as(*Vec4, @ptrCast(&result)).*;
    }

    pub fn toQuat(self: *const Self) Quat {
        var result: [4]f32 = undefined;
        cglm.glmc_mat4_quat(@constCast(&self.data), &result);
        return Quat{ .data = result };
    }

    pub fn perspectiveRhGl(fov: f32, aspect: f32, near: f32, far: f32) Self {
        var projection: [4][4]f32 = undefined;
        cglm.glmc_perspective_rh_no(fov, aspect, near, far, &projection);
        return Mat4{ .data = projection };
    }

    pub fn orthographicRhGl(left: f32, right: f32, bottom: f32, top: f32, near: f32, far: f32) Self {
        var ortho: [4][4]f32 = undefined;
        cglm.glmc_ortho_rh_no(left, right, bottom, top, near, far, &ortho);
        return Mat4{ .data = ortho };
    }

    pub fn lookAtRhGl(eye: *const Vec3, center: *const Vec3, up: *const Vec3) Self {
        var view: [4][4]f32 = undefined;
        cglm.glmc_lookat_rh_no(
            @as([*c]f32, @ptrCast(@constCast(eye))),
            @as([*c]f32, @ptrCast(@constCast(center))),
            @as([*c]f32, @ptrCast(@constCast(up))),
            &view,
        );
        return Mat4{ .data = view };
    }

    pub fn lookToRhGl(eye: *const Vec3, direction: *const Vec3, up: *const Vec3) Self {
        var view: [4][4]f32 = undefined;
        cglm.glmc_look_rh_no(
            @as([*c]f32, @ptrCast(@constCast(eye))),
            @as([*c]f32, @ptrCast(@constCast(direction))),
            @as([*c]f32, @ptrCast(@constCast(up))),
            &view,
        );
        return Mat4{ .data = view };
    }

    pub fn removeTranslation(self: *const Self) Mat4 {
        return Mat4{ .data = .{
            .{ self.data[0][0], self.data[0][1], self.data[0][2], 0.0 },
            .{ self.data[1][0], self.data[1][1], self.data[1][2], 0.0 },
            .{ self.data[2][0], self.data[2][1], self.data[2][2], 0.0 },
            .{ 0.0, 0.0, 0.0, 0.0 },
        } };
    }

    pub const TrnRotScl = struct {
        translation: Vec3,
        rotation: Quat,
        scale: Vec3,
    };

    pub fn getTranslationRotationScale(self: *const Self) TrnRotScl {
        var tran: [4]f32 = undefined;
        var rota: [4][4]f32 = undefined;
        var scal: [3]f32 = undefined;

        cglm.glmc_decompose(@constCast(&self.data), &tran, &rota, &scal);

        var quat: [4]f32 = undefined;
        cglm.glmc_mat4_quat(@constCast(&self.data), &quat);

        return TrnRotScl{
            .translation = Vec3.init(tran[0], tran[1], tran[2]),
            .rotation = Quat{
                .data = quat,
            },
            .scale = Vec3.fromArray(scal),
        };
    }

    pub fn fromTranslationRotationScale(tran: *const Vec3, rota: *const Quat, scal: *const Vec3) Mat4 {
        const axis = Quat.toAxes(rota);

        const mat = Mat4{
            .data = .{
                axis[0].scale(scal.x).asArray(),
                axis[1].scale(scal.y).asArray(),
                axis[2].scale(scal.z).asArray(),
                .{ tran.x, tran.y, tran.z, 1.0 },
            },
        };
        return mat;
    }

    // pub fn to_scale_rotation_translation(&self) (Vec3, Quat, Vec3) {
    //         const det = self.determinant();
    //         glam_assert!(det != 0.0);
    //
    //         const scale = Vec3.new(
    //             self.x_axis.length() * math.signum(det),
    //             self.y_axis.length(),
    //             self.z_axis.length(),
    //         );
    //
    //         glam_assert!(scale.cmpne(Vec3.ZERO).all());
    //
    //         const inv_scale = scale.recip();
    //
    //         const rotation = Quat.from_rotation_axes(
    //             self.x_axis.mul(inv_scale.x).xyz(),
    //             self.y_axis.mul(inv_scale.y).xyz(),
    //             self.z_axis.mul(inv_scale.z).xyz(),
    //         );
    //
    //         const translation = self.w_axis.xyz();
    //
    //         (scale, rotation, translation)
    //     }

    // pub fn lookToRh(eyepos: Vec4, eyedir: Vec4, updir: Vec4) Mat4 {
    //     return lookToLh(eyepos, -eyedir, updir);
    // }
    //
    // pub fn lookAtLh(eyepos: Vec4, focuspos: Vec4, updir: Vec4) Mat4 {
    //     return lookToLh(eyepos, focuspos - eyepos, updir);
    // }
    //
    // pub fn lookAtRh(eyepos: Vec4, focuspos: Vec4, updir: Vec4) Mat4 {
    //     return lookToLh(eyepos, eyepos - focuspos, updir);
    // }
};
