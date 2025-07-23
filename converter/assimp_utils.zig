// ASSIMP utility functions for converting C structures to Zig types
const std = @import("std");
const math = @import("math");

// Use @cImport to access ASSIMP C functions
pub const assimp = @cImport({
    @cInclude("assimp/cimport.h");
    @cInclude("assimp/scene.h");
    @cInclude("assimp/postprocess.h");
});

pub const aiImportFile = assimp.aiImportFile;
pub const aiReleaseImport = assimp.aiReleaseImport;
pub const aiGetErrorString = assimp.aiGetErrorString;

pub const aiProcess_CalcTangentSpace = assimp.aiProcess_CalcTangentSpace;
pub const aiProcess_Triangulate = assimp.aiProcess_Triangulate;
pub const aiProcess_JoinIdenticalVertices = assimp.aiProcess_JoinIdenticalVertices;
pub const aiProcess_SortByPType = assimp.aiProcess_SortByPType;
pub const aiProcess_FlipUVs = assimp.aiProcess_FlipUVs;
pub const aiProcess_FindInvalidData = assimp.aiProcess_FindInvalidData;

pub const aiMatrix4x4 = assimp.struct_aiMatrix4x4;
pub const aiQuaternion = assimp.struct_aiQuaternion;
pub const aiVector3D = assimp.struct_aiVector3D;
pub const aiString = assimp.struct_aiString;
pub const aiNodeAnim = assimp.struct_aiNodeAnim;
pub const aiScene = assimp.struct_aiScene;
pub const aiMesh = assimp.struct_aiMesh;
pub const aiMaterial = assimp.struct_aiMaterial;
pub const aiAnimation = assimp.struct_aiAnimation;
pub const aiLight = assimp.struct_aiLight;
pub const aiCamera = assimp.struct_aiCamera;
pub const aiVectorKey = assimp.struct_aiVectorKey;
pub const aiQuatKey = assimp.struct_aiQuatKey;
pub const aiMatrixKey = assimp.struct_aiMatrixKey;
pub const aiColor3D = assimp.struct_aiColor3D;
pub const aiColor4D = assimp.struct_aiColor4D;
pub const aiFace = assimp.struct_aiFace;
pub const aiNode = assimp.struct_aiNode;

const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const Mat4 = math.Mat4;
const Quat = math.Quat;

pub fn mat4FromAiMatrix(aiMat: aiMatrix4x4) Mat4 {
    const data: [4][4]f32 = .{
        .{ aiMat.a1, aiMat.b1, aiMat.c1, aiMat.d1 }, // m00, m01, m02, m03
        .{ aiMat.a2, aiMat.b2, aiMat.c2, aiMat.d2 }, // m10, m11, m12, m13
        .{ aiMat.a3, aiMat.b3, aiMat.c3, aiMat.d3 }, // m20, m21, m22, m23
        .{ aiMat.a4, aiMat.b4, aiMat.c4, aiMat.d4 }, // m30, m31, m32, m33
    };
    return Mat4{ .data = data };
}

/// Convert ASSIMP aiVector3D to our Vec3 type
pub fn vec3FromAiVector3D(vec3d: aiVector3D) Vec3 {
    return Vec3.init(vec3d.x, vec3d.y, vec3d.z);
}

/// Convert ASSIMP aiQuaternion to our Quat type
pub fn quatFromAiQuaternion(aiQuat: aiQuaternion) Quat {
    return Quat{ .data = .{ aiQuat.x, aiQuat.y, aiQuat.z, aiQuat.w } };
}

/// Transform struct for decomposed matrix data
pub const Transform = struct {
    translation: Vec3,
    rotation: Quat,
    scale: Vec3,

    pub fn fromMatrix(m: *const Mat4) Transform {
        return original_extractTransformFromMatrix(m);
    }
};

/// Check if a Mat4 matrix is identity (within epsilon tolerance)
/// Returns true if the matrix is identity, false otherwise
pub fn isIdentityMatrix(matrix: *const Mat4, epsilon: f32) bool {
    // Identity matrix in column-major format:
    // Column 0: [1, 0, 0, 0]
    // Column 1: [0, 1, 0, 0]
    // Column 2: [0, 0, 1, 0]
    // Column 3: [0, 0, 0, 1]

    const identity = [4][4]f32{
        .{ 1.0, 0.0, 0.0, 0.0 },
        .{ 0.0, 1.0, 0.0, 0.0 },
        .{ 0.0, 0.0, 1.0, 0.0 },
        .{ 0.0, 0.0, 0.0, 1.0 },
    };

    for (0..4) |col| {
        for (0..4) |row| {
            if (@abs(matrix.data[col][row] - identity[col][row]) > epsilon) {
                return false;
            }
        }
    }

    return true;
}

/// Decompose a 4x4 transformation matrix into translation, rotation, and scale components
/// Input matrix is column-major (Mat4 format): data[column][row]
/// All Mat4 matrices in this codebase are column-major as per math library documentation
fn extractTransformFromMatrix(matrix: *const Mat4) Transform {
    // Extract translation (last column for column-major matrix)
    const translation = Vec3.init(matrix.data[3][0], matrix.data[3][1], matrix.data[3][2]);

    // Extract scale (length of first three columns for column-major matrix)
    const scale_x = std.math.sqrt(matrix.data[0][0] * matrix.data[0][0] + matrix.data[0][1] * matrix.data[0][1] + matrix.data[0][2] * matrix.data[0][2]);
    const scale_y = std.math.sqrt(matrix.data[1][0] * matrix.data[1][0] + matrix.data[1][1] * matrix.data[1][1] + matrix.data[1][2] * matrix.data[1][2]);
    const scale_z = std.math.sqrt(matrix.data[2][0] * matrix.data[2][0] + matrix.data[2][1] * matrix.data[2][1] + matrix.data[2][2] * matrix.data[2][2]);
    const extracted_scale = Vec3.init(scale_x, scale_y, scale_z);

    // Remove scale to get pure rotation matrix (column-major)
    const rotation_matrix = Mat4{ .data = .{
        .{ matrix.data[0][0] / scale_x, matrix.data[0][1] / scale_x, matrix.data[0][2] / scale_x, 0.0 },
        .{ matrix.data[1][0] / scale_y, matrix.data[1][1] / scale_y, matrix.data[1][2] / scale_y, 0.0 },
        .{ matrix.data[2][0] / scale_z, matrix.data[2][1] / scale_z, matrix.data[2][2] / scale_z, 0.0 },
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

fn original_extractTransformFromMatrix(matrix: *const Mat4) Transform {
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
