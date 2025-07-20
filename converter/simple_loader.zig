// Simplified ASSIMP loader that extracts data without OpenGL dependencies
const std = @import("std");
const assimp_mod = @import("assimp");

// Use @cImport to access ASSIMP C functions
const assimp = @cImport({
    @cInclude("assimp/cimport.h");
    @cInclude("assimp/scene.h");
    @cInclude("assimp/postprocess.h");
});
const math = @import("math");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const Mat4 = math.Mat4;
const Quat = math.Quat;

pub const SimpleVertex = struct {
    position: Vec3,
    normal: Vec3,
    uv: Vec2,
    tangent: Vec3,
    bi_tangent: Vec3,
    bone_ids: [4]i32,
    bone_weights: [4]f32,

    pub fn init() SimpleVertex {
        return SimpleVertex{
            .position = Vec3.init(0, 0, 0),
            .normal = Vec3.init(0, 1, 0),
            .uv = Vec2.new(0, 0),
            .tangent = Vec3.init(1, 0, 0),
            .bi_tangent = Vec3.init(0, 0, 1),
            .bone_ids = [_]i32{ -1, -1, -1, -1 },
            .bone_weights = [_]f32{ 0.0, 0.0, 0.0, 0.0 },
        };
    }

    pub fn setBoneData(self: *SimpleVertex, bone_id: u32, weight: f32) void {
        if (weight == 0.0) return;

        for (0..4) |i| {
            if (self.bone_ids[i] < 0) {
                self.bone_ids[i] = @intCast(bone_id);
                self.bone_weights[i] = weight;
                break;
            }
        }
    }
};

pub const SimpleMesh = struct {
    name: []const u8,
    vertices: ArrayList(SimpleVertex),
    indices: ArrayList(u32),
    material_index: ?u32, // Reference to material in the model

    pub fn init(allocator: Allocator, name: []const u8) SimpleMesh {
        return SimpleMesh{
            .name = name,
            .vertices = ArrayList(SimpleVertex).init(allocator),
            .indices = ArrayList(u32).init(allocator),
            .material_index = null,
        };
    }

    pub fn deinit(self: *SimpleMesh) void {
        self.vertices.deinit();
        self.indices.deinit();
    }
};

pub const SimpleAnimation = struct {
    name: []const u8,
    duration: f32,
    ticks_per_second: f32,
};

pub const SimpleBone = struct {
    name: []const u8,
    id: u32,
    offset_matrix: [16]f32, // Inverse bind matrix
    parent_id: ?u32, // Parent bone index, null for root bones
};

pub const SimpleModel = struct {
    name: []const u8,
    meshes: ArrayList(SimpleMesh),
    animations: ArrayList(SimpleAnimation),
    bones: ArrayList(SimpleBone),
    bone_name_to_id: std.StringHashMap(u32),
    allocator: Allocator,

    pub fn init(allocator: Allocator, name: []const u8) SimpleModel {
        return SimpleModel{
            .name = name,
            .meshes = ArrayList(SimpleMesh).init(allocator),
            .animations = ArrayList(SimpleAnimation).init(allocator),
            .bones = ArrayList(SimpleBone).init(allocator),
            .bone_name_to_id = std.StringHashMap(u32).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SimpleModel) void {
        // Free mesh names and mesh data
        for (self.meshes.items) |*mesh| {
            self.allocator.free(mesh.name);
            mesh.deinit();
        }
        self.meshes.deinit();

        // Free animation names
        for (self.animations.items) |*animation| {
            self.allocator.free(animation.name);
        }
        self.animations.deinit();

        // Free bone names and hashmap keys
        for (self.bones.items) |*bone| {
            self.allocator.free(bone.name);
        }
        var iterator = self.bone_name_to_id.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.bones.deinit();
        self.bone_name_to_id.deinit();
    }
};

pub const LoadResult = struct {
    model: SimpleModel,
    scene: *const assimp.aiScene, // Keep a reference to the scene for material processing

    pub fn deinit(self: *LoadResult) void {
        self.model.deinit();
        assimp.aiReleaseImport(self.scene);
    }
};

pub fn loadModelWithAssimp(allocator: Allocator, file_path: []const u8, verbose: bool) !LoadResult {
    if (verbose) {
        std.debug.print("  Loading {s} with ASSIMP...\n", .{file_path});
    }

    // Convert to null-terminated string for ASSIMP
    const path_z = try allocator.dupeZ(u8, file_path);
    defer allocator.free(path_z);

    // Load with ASSIMP
    const aiScene = assimp.aiImportFile(
        path_z,
        assimp.aiProcess_CalcTangentSpace |
            assimp.aiProcess_Triangulate |
            assimp.aiProcess_JoinIdenticalVertices |
            assimp.aiProcess_SortByPType |
            assimp.aiProcess_FlipUVs |
            assimp.aiProcess_FindInvalidData, // this fixes animation by removing duplicate keys
    );

    if (aiScene == null) {
        const errorMessage = assimp.aiGetErrorString();
        std.debug.print("ASSIMP Error: {s}\n", .{errorMessage});
        return error.AssimpLoadFailed;
    }

    // Create simple model
    var model = SimpleModel.init(allocator, "converted_model");

    if (verbose) {
        std.debug.print("  Found {d} meshes\n", .{aiScene[0].mNumMeshes});
    }

    // Process meshes
    for (0..aiScene[0].mNumMeshes) |mesh_idx| {
        const aiMesh = aiScene[0].mMeshes[mesh_idx][0];

        // Get mesh name from ASSIMP, or use default if empty
        const mesh_name = if (aiMesh.mName.length > 0)
            try allocator.dupe(u8, aiMesh.mName.data[0..aiMesh.mName.length])
        else
            try std.fmt.allocPrint(allocator, "mesh_{d}", .{mesh_idx});

        var mesh = SimpleMesh.init(allocator, mesh_name);

        // Store material index
        mesh.material_index = if (aiMesh.mMaterialIndex < aiScene[0].mNumMaterials) aiMesh.mMaterialIndex else null;

        if (verbose) {
            std.debug.print("    Processing mesh {d}: {d} vertices, {d} faces, material: {?d}\n", .{ mesh_idx, aiMesh.mNumVertices, aiMesh.mNumFaces, mesh.material_index });
        }

        // Process vertices
        for (0..aiMesh.mNumVertices) |v_idx| {
            var vertex = SimpleVertex.init();

            // Position
            vertex.position = Vec3.init(
                aiMesh.mVertices[v_idx].x,
                aiMesh.mVertices[v_idx].y,
                aiMesh.mVertices[v_idx].z,
            );

            // Normal
            if (aiMesh.mNormals != null) {
                vertex.normal = Vec3.init(
                    aiMesh.mNormals[v_idx].x,
                    aiMesh.mNormals[v_idx].y,
                    aiMesh.mNormals[v_idx].z,
                );
            }

            // UV coordinates
            if (aiMesh.mTextureCoords[0] != null) {
                const tex_coords = aiMesh.mTextureCoords[0];
                vertex.uv = Vec2.new(tex_coords[v_idx].x, tex_coords[v_idx].y);
            }

            try mesh.vertices.append(vertex);
        }

        // Process bone weights for this mesh
        if (aiMesh.mNumBones > 0) {
            if (verbose) {
                std.debug.print("      Processing {d} bones for mesh {d}\n", .{ aiMesh.mNumBones, mesh_idx });
            }

            for (0..aiMesh.mNumBones) |bone_idx| {
                const aiBone = aiMesh.mBones[bone_idx][0];
                const bone_name = aiBone.mName.data[0..aiBone.mName.length];

                // Get or create bone ID
                var bone_id: u32 = undefined;
                if (model.bone_name_to_id.get(bone_name)) |existing_id| {
                    bone_id = existing_id;
                } else {
                    bone_id = @intCast(model.bones.items.len);

                    // Convert ASSIMP matrix to array format
                    var offset_matrix: [16]f32 = undefined;
                    const ai_matrix = aiBone.mOffsetMatrix;
                    offset_matrix[0] = ai_matrix.a1;
                    offset_matrix[1] = ai_matrix.b1;
                    offset_matrix[2] = ai_matrix.c1;
                    offset_matrix[3] = ai_matrix.d1;
                    offset_matrix[4] = ai_matrix.a2;
                    offset_matrix[5] = ai_matrix.b2;
                    offset_matrix[6] = ai_matrix.c2;
                    offset_matrix[7] = ai_matrix.d2;
                    offset_matrix[8] = ai_matrix.a3;
                    offset_matrix[9] = ai_matrix.b3;
                    offset_matrix[10] = ai_matrix.c3;
                    offset_matrix[11] = ai_matrix.d3;
                    offset_matrix[12] = ai_matrix.a4;
                    offset_matrix[13] = ai_matrix.b4;
                    offset_matrix[14] = ai_matrix.c4;
                    offset_matrix[15] = ai_matrix.d4;

                    const simple_bone = SimpleBone{
                        .name = try allocator.dupe(u8, bone_name),
                        .id = bone_id,
                        .offset_matrix = offset_matrix,
                        .parent_id = null, // Will be set later when processing hierarchy
                    };

                    try model.bones.append(simple_bone);
                    try model.bone_name_to_id.put(try allocator.dupe(u8, bone_name), bone_id);

                    if (verbose) {
                        std.debug.print("        Added bone {d}: {s}\n", .{ bone_id, bone_name });
                    }
                }

                // Apply bone weights to vertices
                for (0..aiBone.mNumWeights) |weight_idx| {
                    const weight = aiBone.mWeights[weight_idx];
                    const vertex_id = weight.mVertexId;
                    const weight_value = weight.mWeight;

                    if (vertex_id < mesh.vertices.items.len) {
                        mesh.vertices.items[vertex_id].setBoneData(bone_id, weight_value);
                    }
                }
            }
        }

        // Process indices
        for (0..aiMesh.mNumFaces) |f_idx| {
            const face = aiMesh.mFaces[f_idx];
            for (0..face.mNumIndices) |i_idx| {
                try mesh.indices.append(face.mIndices[i_idx]);
            }
        }

        try model.meshes.append(mesh);
    }

    // Process animations
    if (verbose) {
        std.debug.print("  Found {d} animations\n", .{aiScene[0].mNumAnimations});
    }
    for (0..aiScene[0].mNumAnimations) |anim_idx| {
        const aiAnim = aiScene[0].mAnimations[anim_idx][0];
        const anim_name = if (aiAnim.mName.length > 0)
            try allocator.dupe(u8, aiAnim.mName.data[0..aiAnim.mName.length])
        else
            try std.fmt.allocPrint(allocator, "animation_{d}", .{anim_idx});

        const animation = SimpleAnimation{
            .name = anim_name,
            .duration = @floatCast(aiAnim.mDuration),
            .ticks_per_second = @floatCast(aiAnim.mTicksPerSecond),
        };
        try model.animations.append(animation);
    }

    if (verbose) {
        std.debug.print("  Successfully loaded model with {d} meshes, {d} animations, {d} bones\n", .{ model.meshes.items.len, model.animations.items.len, model.bones.items.len });
    }

    return LoadResult{
        .model = model,
        .scene = aiScene,
    };
}
