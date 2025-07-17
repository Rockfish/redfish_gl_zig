// ASSIMP utility functions for converting C structures to Zig types
const std = @import("std");
const math = @import("math");

// Use @cImport to access ASSIMP C functions
const assimp = @cImport({
    @cInclude("assimp/cimport.h");
    @cInclude("assimp/scene.h");
    @cInclude("assimp/postprocess.h");
});

const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const Mat4 = math.Mat4;
const Quat = math.Quat;

/// Convert ASSIMP aiMatrix4x4 to our Mat4 type
pub fn mat4FromAiMatrix(aiMat: anytype) Mat4 {
    const data: [4][4]f32 = .{
        .{ aiMat.a1, aiMat.b1, aiMat.c1, aiMat.d1 }, // m00, m01, m02, m03
        .{ aiMat.a2, aiMat.b2, aiMat.c2, aiMat.d2 }, // m10, m11, m12, m13
        .{ aiMat.a3, aiMat.b3, aiMat.c3, aiMat.d3 }, // m20, m21, m22, m23
        .{ aiMat.a4, aiMat.b4, aiMat.c4, aiMat.d4 }, // m30, m31, m32, m33
    };
    return Mat4{ .data = data };
}

/// Convert ASSIMP aiVector3D to our Vec3 type
pub fn vec3FromAiVector3D(vec3d: anytype) Vec3 {
    return Vec3.init(vec3d.x, vec3d.y, vec3d.z);
}

/// Convert ASSIMP aiQuaternion to our Quat type
pub fn quatFromAiQuaternion(aiQuat: anytype) Quat {
    return Quat{ .data = .{ aiQuat.x, aiQuat.y, aiQuat.z, aiQuat.w } };
}

/// Transform struct for decomposed matrix data
pub const Transform = struct {
    translation: Vec3,
    rotation: Quat,
    scale: Vec3,

    pub fn fromMatrix(m: *const Mat4) Transform {
        return extractTransformFromMatrix(m);
    }
};

/// Decompose a 4x4 transformation matrix into translation, rotation, and scale components
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