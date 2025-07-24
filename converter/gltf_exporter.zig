// glTF 2.0 exporter that converts SimpleModel to proper glTF JSON + binary format
const std = @import("std");
const simple_loader = @import("simple_loader.zig");
const material_processor = @import("material_processor.zig");
const assimp = @import("assimp_utils.zig");
const math = @import("math");

// Use @cImport to access ASSIMP C functions for animation processing
// const assimp = @cImport({
//     @cInclude("assimp/cimport.h");
//     @cInclude("assimp/scene.h");
//     @cInclude("assimp/anim.h");
// });

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const SimpleModel = simple_loader.SimpleModel;
const SimpleMesh = simple_loader.SimpleMesh;

const MaterialProcessor = material_processor.MaterialProcessor;
const GltfMaterial = material_processor.GltfMaterial;
const GltfTexture = material_processor.GltfTexture;
const GltfImage = material_processor.GltfImage;
const GltfSampler = material_processor.GltfSampler;

// glTF 2.0 JSON structure types
const GltfAsset = struct {
    version: []const u8 = "2.0",
    generator: []const u8 = "redfish_gl_zig converter",
};

const GltfScene = struct {
    nodes: []u32,
};

const GltfNode = struct {
    mesh: ?u32 = null,
    name: ?[]const u8 = null,
    children: ?[]u32 = null,
    translation: ?[3]f32 = null,
    rotation: ?[4]f32 = null,
    scale: ?[3]f32 = null,
    matrix: ?[16]f32 = null,
    skin: ?u32 = null,
};

const GltfBuffer = struct {
    byteLength: u32,
    uri: []const u8,
};

const GltfBufferView = struct {
    buffer: u32,
    byteOffset: u32,
    byteLength: u32,
    target: ?u32 = null, // 34962 = ARRAY_BUFFER, 34963 = ELEMENT_ARRAY_BUFFER
};

const GltfAccessor = struct {
    bufferView: u32,
    byteOffset: u32 = 0,
    componentType: u32, // 5120=BYTE, 5123=UNSIGNED_SHORT, 5125=UNSIGNED_INT, 5126=FLOAT
    count: u32,
    type: []const u8, // "SCALAR", "VEC2", "VEC3", "VEC4"
    max: ?[]f32 = null,
    min: ?[]f32 = null,
};

const GltfMeshPrimitive = struct {
    attributes: std.StringHashMap(u32),
    indices: ?u32 = null,
    material: ?u32 = null, // Reference to material index
    mode: u32 = 4, // 4 = TRIANGLES
};

const GltfMesh = struct {
    name: []const u8,
    primitives: []GltfMeshPrimitive,
};

const GltfSkin = struct {
    inverseBindMatrices: ?u32 = null, // accessor index
    skeleton: ?u32 = null, // node index (root joint)
    joints: []u32, // array of node indices
    name: ?[]const u8 = null,
};

// glTF animation structures
pub const GltfAnimation = struct {
    name: []const u8,
    channels: []GltfAnimationChannel,
    samplers: []GltfAnimationSampler,
};

pub const GltfAnimationChannel = struct {
    sampler: u32,
    target: GltfAnimationChannelTarget,
};

pub const GltfAnimationChannelTarget = struct {
    node: u32,
    path: []const u8, // "translation", "rotation", "scale"
};

pub const GltfAnimationSampler = struct {
    input: u32, // accessor index for timestamps
    output: u32, // accessor index for values
    interpolation: []const u8 = "LINEAR",
};

const GltfDocument = struct {
    asset: GltfAsset,
    scenes: []GltfScene,
    nodes: []GltfNode,
    meshes: []GltfMesh,
    materials: ?[]GltfMaterial = null,
    textures: ?[]GltfTexture = null,
    images: ?[]GltfImage = null,
    samplers: ?[]GltfSampler = null,
    animations: ?[]GltfAnimation = null,
    skins: ?[]GltfSkin = null,
    buffers: []GltfBuffer,
    bufferViews: []GltfBufferView,
    accessors: []GltfAccessor,
    scene: u32 = 0,
};

/// Check if a SimpleMesh has bone weight data (skeletal animation)
fn meshHasBoneWeights(mesh: *const SimpleMesh) bool {
    for (mesh.vertices.items) |vertex| {
        if (vertex.bone_ids[0] >= 0) {
            return true;
        }
    }
    return false;
}

/// Build parent mapping from node children arrays (child_index -> parent_index)
fn buildParentMap(allocator: Allocator, nodes: []const GltfNode) !std.AutoHashMap(u32, u32) {
    var parent_map = std.AutoHashMap(u32, u32).init(allocator);

    for (nodes, 0..) |node, parent_idx| {
        if (node.children) |children| {
            for (children) |child_idx| {
                try parent_map.put(child_idx, @intCast(parent_idx));
            }
        }
    }

    return parent_map;
}

/// Find path from node to root, returns reversed path (node to root)
fn findPathToRoot(parent_map: *const std.AutoHashMap(u32, u32), node_idx: u32, path: *std.ArrayList(u32)) !void {
    var current = node_idx;
    try path.append(current);

    while (parent_map.get(current)) |parent_idx| {
        try path.append(parent_idx);
        current = parent_idx;
    }
}

/// Find lowest common ancestor of all joints using standard LCA algorithm
/// Returns scene root (node 0) if no common ancestor found (disconnected hierarchies)
fn findLowestCommonAncestor(allocator: Allocator, parent_map: *const std.AutoHashMap(u32, u32), joint_indices: []const u32) !u32 {
    if (joint_indices.len == 0) {
        return error.NoJointsProvided;
    }

    if (joint_indices.len == 1) {
        return joint_indices[0];
    }

    // Get path to root for first joint
    var first_path = std.ArrayList(u32).init(allocator);
    defer first_path.deinit();
    try findPathToRoot(parent_map, joint_indices[0], &first_path);

    // Convert to set for fast lookup
    var first_path_set = std.AutoHashMap(u32, void).init(allocator);
    defer first_path_set.deinit();
    for (first_path.items) |node_idx| {
        try first_path_set.put(node_idx, {});
    }

    // For each other joint, find first common ancestor with first joint
    var lca = joint_indices[0];

    for (joint_indices[1..]) |joint_idx| {
        var current_path = std.ArrayList(u32).init(allocator);
        defer current_path.deinit();
        try findPathToRoot(parent_map, joint_idx, &current_path);

        // Find first node in current path that exists in first path
        var found_lca = false;
        for (current_path.items) |node_idx| {
            if (first_path_set.contains(node_idx)) {
                lca = node_idx;
                found_lca = true;
                break;
            }
        }

        if (!found_lca) {
            // No common ancestor found - use scene root (node 0) as fallback
            // This handles disconnected joint hierarchies
            return 0;
        }

        // Update first_path_set to only contain nodes up to new LCA
        first_path_set.clearRetainingCapacity();
        var found_new_lca = false;
        for (first_path.items) |node_idx| {
            try first_path_set.put(node_idx, {});
            if (node_idx == lca) {
                found_new_lca = true;
                break;
            }
        }

        if (!found_new_lca) {
            // Fallback to scene root if LCA logic fails
            return 0;
        }
    }

    return lca;
}

/// Find proper skeleton root as lowest common ancestor of all joints
fn findSkeletonRoot(allocator: Allocator, nodes: []const GltfNode, joint_indices: []const u32) !u32 {
    var parent_map = try buildParentMap(allocator, nodes);
    defer parent_map.deinit();

    return findLowestCommonAncestor(allocator, &parent_map, joint_indices);
}

/// Calculate world transform by traversing up parent chain
fn calculateWorldTransform(nodes: []const GltfNode, parent_map: *const std.AutoHashMap(u32, u32), node_idx: u32) math.Mat4 {
    var transform = math.Mat4.identity();
    var current = node_idx;

    // Collect transforms from node to root
    var transforms = std.ArrayList(math.Mat4).init(std.heap.page_allocator);
    defer transforms.deinit();

    while (true) {
        const node = &nodes[current];
        var local_transform = math.Mat4.identity();

        // Create local transform from TRS components
        const translation = if (node.translation) |t| math.Vec3.init(t[0], t[1], t[2]) else math.Vec3.init(0, 0, 0);
        const rotation = if (node.rotation) |r| math.Quat{ .data = .{ r[0], r[1], r[2], r[3] } } else math.Quat.identity();
        const scale = if (node.scale) |s| math.Vec3.init(s[0], s[1], s[2]) else math.Vec3.init(1, 1, 1);

        local_transform = math.Mat4.fromTranslationRotationScale(&translation, &rotation, &scale);

        transforms.append(local_transform) catch break;

        if (parent_map.get(current)) |parent_idx| {
            current = parent_idx;
        } else {
            break;
        }
    }

    // Multiply transforms in reverse order (root to node)
    var i = transforms.items.len;
    while (i > 0) {
        i -= 1;
        transform = transform.mulMat4(&transforms.items[i]);
    }

    return transform;
}

/// Remove node from its parent's children array
fn removeFromParent(nodes: []GltfNode, child_idx: u32, parent_map: *const std.AutoHashMap(u32, u32)) void {
    if (parent_map.get(child_idx)) |parent_idx| {
        const parent = &nodes[parent_idx];
        if (parent.children) |children| {
            // Find and remove child_idx from children array
            for (children, 0..) |child, i| {
                if (child == child_idx) {
                    // Shift remaining elements left
                    for (i..children.len - 1) |j| {
                        children[j] = children[j + 1];
                    }
                    // Note: We can't actually shrink the slice here, but the extra element won't be used
                    break;
                }
            }
        }
    }
}

/// Bake world transform into node's local transform
fn bakeWorldTransform(node: *GltfNode, world_transform: math.Mat4) void {
    const transform = assimp.Transform.fromMatrix(&world_transform);
    node.translation = transform.translation.asArray();
    node.rotation = transform.rotation.asArray();
    node.scale = transform.scale.asArray();
}

/// Move skinned mesh nodes to scene root to avoid parent transform conflicts
fn hoistSkinnedMeshesToRoot(allocator: Allocator, nodes: []GltfNode, scene: *GltfScene) !void {
    var parent_map = try buildParentMap(allocator, nodes);
    defer parent_map.deinit();

    var nodes_to_hoist = std.ArrayList(u32).init(allocator);
    defer nodes_to_hoist.deinit();

    // Find all nodes with skin assignment
    for (nodes, 0..) |node, i| {
        if (node.skin != null) {
            try nodes_to_hoist.append(@intCast(i));
            std.debug.print("    Found skinned mesh node {d}: {s}\n", .{ i, node.name orelse "unnamed" });
        }
    }

    std.debug.print("    Found {d} skinned mesh nodes to hoist\n", .{nodes_to_hoist.items.len});

    // Hoist each skinned mesh node
    for (nodes_to_hoist.items) |node_idx| {
        // Calculate world transform
        const world_transform = calculateWorldTransform(nodes, &parent_map, node_idx);

        // Remove from current parent
        removeFromParent(nodes, node_idx, &parent_map);

        // Add to scene root if not already there
        var already_in_scene = false;
        for (scene.nodes) |scene_node| {
            if (scene_node == node_idx) {
                already_in_scene = true;
                break;
            }
        }

        if (!already_in_scene) {
            // Extend scene.nodes array to include this node
            var new_scene_nodes = try allocator.alloc(u32, scene.nodes.len + 1);
            @memcpy(new_scene_nodes[0..scene.nodes.len], scene.nodes);
            new_scene_nodes[scene.nodes.len] = node_idx;
            scene.nodes = new_scene_nodes;
        }

        // Bake world transform into local transform
        bakeWorldTransform(&nodes[node_idx], world_transform);
    }
}

pub const GltfExporter = struct {
    allocator: Allocator,
    binary_data: ArrayList(u8),
    verbose: bool = false,

    pub fn init(allocator: Allocator, verbose: bool) GltfExporter {
        return GltfExporter{
            .allocator = allocator,
            .binary_data = ArrayList(u8).init(allocator),
            .verbose = verbose,
        };
    }

    pub fn deinit(self: *GltfExporter) void {
        self.binary_data.deinit();
    }

    /// Process ASSIMP node hierarchy with mesh index mapping from SimpleMesh to glTF mesh
    fn processNodeHierarchyWithMapping(
        self: *GltfExporter,
        ai_node: *const assimp.aiNode,
        nodes: *ArrayList(GltfNode),
        node_name_map: *std.StringHashMap(u32),
        mesh_to_node_map: *std.AutoHashMap(u32, u32),
        simple_to_gltf_mesh_map: *const std.AutoHashMap(usize, u32),
    ) !u32 {
        const allocator = self.allocator;
        const current_index: u32 = @intCast(nodes.items.len);

        // Extract node name
        const ai_name = ai_node.mName;
        const node_name = try allocator.dupe(u8, ai_name.data[0..ai_name.length]);

        // Extract transform data using proven ASSIMP utilities
        const ai_transform = ai_node.mTransformation;
        const transform_matrix = assimp.mat4FromAiMatrix(ai_transform);

        // Only apply transform if it's not identity (matching ASSIMP's behavior)
        // Use same epsilon as ASSIMP's default: AI_CONFIG_CHECK_IDENTITY_MATRIX_EPSILON_DEFAULT
        const configEpsilon: f32 = 0.01; // 10e-3 as per ASSIMP default (10 * 10^-3)
        var gltf_node = GltfNode{
            .name = node_name,
        };

        if (!assimp.isIdentityMatrix(&transform_matrix, configEpsilon)) {
            const transform = assimp.Transform.fromMatrix(&transform_matrix);
            gltf_node.translation = transform.translation.asArray();
            gltf_node.rotation = transform.rotation.asArray();
            gltf_node.scale = transform.scale.asArray();
        }

        // Associate meshes with this node if any, using the correct mapping
        if (ai_node.mNumMeshes > 0) {
            // For simplicity, take the first mesh if multiple meshes are assigned to one node
            const simple_mesh_index = ai_node.mMeshes[0];

            // Map SimpleMesh index to glTF mesh index
            if (simple_to_gltf_mesh_map.get(simple_mesh_index)) |gltf_mesh_idx| {
                gltf_node.mesh = gltf_mesh_idx;
                try mesh_to_node_map.put(simple_mesh_index, current_index);
                if (self.verbose) {
                    std.debug.print("    Node {d} '{s}': SimpleMesh {d} -> glTF mesh {d}\n", .{ current_index, node_name, simple_mesh_index, gltf_mesh_idx });
                }
            } else {
                if (self.verbose) {
                    std.debug.print("    Warning: SimpleMesh {d} not found in mapping for node '{s}'\n", .{ simple_mesh_index, node_name });
                }
            }
        }

        // Add node to list
        try nodes.append(gltf_node);

        // Add to node name mapping for animation support
        try node_name_map.put(node_name, current_index);

        if (self.verbose) {
            std.debug.print("    Processed node {d}: {s} (meshes: {d}, children: {d})\n", .{ current_index, node_name, ai_node.mNumMeshes, ai_node.mNumChildren });
        }

        // Process children recursively and build children array
        if (ai_node.mNumChildren > 0) {
            var children = try allocator.alloc(u32, ai_node.mNumChildren);

            for (ai_node.mChildren[0..ai_node.mNumChildren], 0..) |child_node, i| {
                const child_index = try self.processNodeHierarchyWithMapping(
                    child_node,
                    nodes,
                    node_name_map,
                    mesh_to_node_map,
                    simple_to_gltf_mesh_map,
                );
                children[i] = child_index;
            }

            // Update the node with children (nodes list may have been reallocated)
            nodes.items[current_index].children = children;
        }

        return current_index;
    }

    pub fn exportModel(
        self: *GltfExporter,
        model: *const SimpleModel,
        input_path: []const u8,
        output_path: []const u8,
        scene: ?*const anyopaque,
    ) !void {
        if (self.verbose) {
            std.debug.print("Exporting model to glTF: {s}\n", .{output_path});
        }

        // Reset binary data
        self.binary_data.clearRetainingCapacity();

        // Create glTF document structure
        var gltf_doc = try self.buildGltfDocument(model, input_path, output_path, scene);
        defer self.cleanupGltfDocument(&gltf_doc);

        // Write binary buffer file
        const bin_path = try self.getBinPath(output_path);
        defer self.allocator.free(bin_path);
        try self.writeBinaryFile(bin_path);

        // Write JSON file
        try self.writeJsonFile(output_path, &gltf_doc, bin_path);

        std.debug.print("Exported glTF document to {s}\n", .{output_path});
        std.debug.print("   scenes: {d}\n   nodes: {d}\n   meshes: {d}\n   materials: {d}\n   textures: {d}\n   images: {d}\n   samplers: {d}\n   animations: {d}\n   skins: {d}\n   buffers: {d}\n   bufferViews: {d}\n   accessors: {d}\n", .{
            gltf_doc.scenes.len,
            gltf_doc.nodes.len,
            gltf_doc.meshes.len,
            if (gltf_doc.materials) |m| m.len else 0,
            if (gltf_doc.textures) |t| t.len else 0,
            if (gltf_doc.images) |i| i.len else 0,
            if (gltf_doc.samplers) |s| s.len else 0,
            if (gltf_doc.animations) |a| a.len else 0,
            if (gltf_doc.skins) |sk| sk.len else 0,
            gltf_doc.buffers.len,
            gltf_doc.bufferViews.len,
            gltf_doc.accessors.len,
        });

        if (self.verbose) {
            std.debug.print("Successfully exported: {s} ({d} bytes binary)\n", .{ output_path, self.binary_data.items.len });
        }
    }

    fn buildGltfDocument(
        self: *GltfExporter,
        model: *const SimpleModel,
        input_path: []const u8,
        output_path: []const u8,
        scene: ?*const anyopaque,
    ) !GltfDocument {
        const allocator = self.allocator;

        // Process materials if ASSIMP scene is provided
        var material_proc: ?MaterialProcessor = null;
        if (scene) |ai_scene_ptr| {
            material_proc = MaterialProcessor.init(allocator, input_path, output_path, self.verbose);
            try material_proc.?.processMaterials(@ptrCast(@alignCast(ai_scene_ptr)));
        }

        // Initialize data structures
        var nodes = ArrayList(GltfNode).init(allocator);
        var mesh_groups = std.StringHashMap(ArrayList(usize)).init(allocator);
        defer {
            var iter = mesh_groups.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.deinit();
                allocator.free(entry.key_ptr.*);
            }
            mesh_groups.deinit();
        }
        var buffer_views = ArrayList(GltfBufferView).init(allocator);
        var accessors = ArrayList(GltfAccessor).init(allocator);

        // Create node name to index mapping for animation support
        var node_name_map = std.StringHashMap(u32).init(allocator);
        defer node_name_map.deinit();

        // Create mesh to node mapping to track which node contains which mesh
        var mesh_to_node_map = std.AutoHashMap(u32, u32).init(allocator);
        defer mesh_to_node_map.deinit();

        // Group SimpleMeshes by base name to create proper glTF meshes with multiple primitives first
        // This must happen before node processing so we have correct mesh indices
        if (self.verbose) {
            std.debug.print("  Grouping {d} SimpleMeshes by name...\n", .{model.meshes.items.len});
        }
        for (model.meshes.items, 0..) |*mesh, mesh_idx| {
            const mesh_name = try allocator.dupe(u8, mesh.name);

            if (mesh_groups.getPtr(mesh_name)) |group| {
                // Add to existing group
                try group.append(mesh_idx);
                allocator.free(mesh_name); // Free the duplicate since we're not using it
            } else {
                // Create new group
                var new_group = ArrayList(usize).init(allocator);
                try new_group.append(mesh_idx);
                try mesh_groups.put(mesh_name, new_group);
            }
        }

        // Create glTF meshes from grouped SimpleMeshes
        var meshes_list = ArrayList(GltfMesh).init(allocator);
        var mesh_groups_iter = mesh_groups.iterator();
        while (mesh_groups_iter.next()) |group_entry| {
            const mesh_name = group_entry.key_ptr.*;
            const mesh_indices = group_entry.value_ptr.*;

            if (self.verbose) {
                std.debug.print("  Creating glTF mesh '{s}' with {d} primitives\n", .{ mesh_name, mesh_indices.items.len });
            }

            // Create primitives for this mesh
            var primitives = ArrayList(GltfMeshPrimitive).init(allocator);

            for (mesh_indices.items) |mesh_idx| {
                const mesh = &model.meshes.items[mesh_idx];
                if (self.verbose) {
                    std.debug.print("    Processing primitive {d}: {s} ({d} vertices, {d} indices)\n", .{ mesh_idx, mesh.name, mesh.vertices.items.len, mesh.indices.items.len });
                }

                // Create mesh primitive with attributes
                var attributes = std.StringHashMap(u32).init(allocator);

                // Write vertex data to binary buffer and create accessors
                const position_accessor = try self.writeVertexAttribute(mesh, "POSITION", &buffer_views, &accessors, null);
                const normal_accessor = try self.writeVertexAttribute(mesh, "NORMAL", &buffer_views, &accessors, null);
                const uv_accessor = try self.writeVertexAttribute(mesh, "TEXCOORD_0", &buffer_views, &accessors, null);

                try attributes.put("POSITION", position_accessor);
                try attributes.put("NORMAL", normal_accessor);
                try attributes.put("TEXCOORD_0", uv_accessor);

                // Write indices and create accessor
                var indices_accessor: ?u32 = null;
                if (mesh.indices.items.len > 0) {
                    indices_accessor = try self.writeIndexData(mesh, &buffer_views, &accessors);
                }

                // Create mesh primitive
                const primitive = GltfMeshPrimitive{
                    .attributes = attributes,
                    .indices = indices_accessor,
                    .material = mesh.material_index,
                };

                try primitives.append(primitive);
            }

            // Create the glTF mesh with all primitives
            const gltf_mesh = GltfMesh{
                .name = try allocator.dupe(u8, mesh_name),
                .primitives = try primitives.toOwnedSlice(),
            };

            try meshes_list.append(gltf_mesh);
        }

        const meshes = try meshes_list.toOwnedSlice();

        // Create mapping from SimpleMesh index to glTF mesh index
        var simple_to_gltf_mesh_map = std.AutoHashMap(usize, u32).init(allocator);
        defer simple_to_gltf_mesh_map.deinit();

        var mesh_groups_iter2 = mesh_groups.iterator();
        var gltf_mesh_idx: u32 = 0;
        while (mesh_groups_iter2.next()) |group_entry| {
            const group_mesh_indices = group_entry.value_ptr.*;
            for (group_mesh_indices.items) |simple_mesh_idx| {
                try simple_to_gltf_mesh_map.put(simple_mesh_idx, gltf_mesh_idx);
            }
            gltf_mesh_idx += 1;
        }

        // Build node hierarchy from ASSIMP scene if available
        var scene_root_nodes = ArrayList(u32).init(allocator);
        defer scene_root_nodes.deinit();

        if (scene) |ai_scene_ptr| {
            const ai_scene: *const assimp.aiScene = @ptrCast(@alignCast(ai_scene_ptr));
            if (self.verbose) {
                std.debug.print("  Processing ASSIMP scene with {d} meshes...\n", .{ai_scene.mNumMeshes});
            }

            // Process the root node hierarchy with mesh mapping
            const root_node_index = try self.processNodeHierarchyWithMapping(
                ai_scene.mRootNode,
                &nodes,
                &node_name_map,
                &mesh_to_node_map,
                &simple_to_gltf_mesh_map,
            );

            // Add root node to scene
            try scene_root_nodes.append(root_node_index);
        } else {
            if (self.verbose) {
                std.debug.print("  Creating fallback nodes for {d} glTF meshes...\n", .{meshes.len});
            }
            for (meshes, 0..) |mesh, mesh_idx| {
                const node_name = try allocator.dupe(u8, mesh.name);
                try nodes.append(GltfNode{
                    .mesh = @intCast(mesh_idx),
                    .name = node_name,
                });
                try node_name_map.put(node_name, @intCast(mesh_idx));
                try scene_root_nodes.append(@intCast(mesh_idx));
                if (self.verbose) {
                    std.debug.print("    Created node {d} for mesh '{s}'\n", .{ mesh_idx, mesh.name });
                }
            }
        }

        // Process bones as joint nodes - map existing hierarchy nodes to joint indices
        var joint_indices = try allocator.alloc(u32, model.bones.items.len);
        if (model.bones.items.len > 0) {
            if (self.verbose) {
                std.debug.print("  Processing {d} bones as joint nodes\n", .{model.bones.items.len});
            }

            for (model.bones.items, 0..) |*bone, bone_idx| {
                // Check if bone already exists in node hierarchy (preferred)
                if (node_name_map.get(bone.name)) |existing_node_idx| {
                    joint_indices[bone_idx] = existing_node_idx;
                    if (self.verbose) {
                        std.debug.print("    Joint {d}: {s} -> existing node index {d}\n", .{ bone_idx, bone.name, existing_node_idx });
                    }
                } else {
                    // Fallback: create new node if bone not found in hierarchy
                    const node_idx: u32 = @intCast(nodes.items.len);
                    joint_indices[bone_idx] = node_idx;

                    const bone_name = try allocator.dupe(u8, bone.name);
                    try nodes.append(GltfNode{
                        .mesh = null, // Joint nodes don't have meshes
                        .name = bone_name,
                    });

                    // Add bone to node name mapping for animation support
                    try node_name_map.put(bone_name, node_idx);

                    if (self.verbose) {
                        std.debug.print("    Joint {d}: {s} -> new node index {d}\n", .{ bone_idx, bone.name, node_idx });
                    }
                }
            }
            // Now add bone vertex attributes to all mesh primitives with joint remapping
            for (meshes, 0..) |*gltf_mesh, gltf_mesh_index| {
                if (self.verbose) {
                    std.debug.print("    Processing bone attributes for glTF mesh {d}: {s} ({d} primitives)\n", .{ gltf_mesh_index, gltf_mesh.name, gltf_mesh.primitives.len });
                }

                for (gltf_mesh.primitives, 0..) |*primitive, primitive_idx| {
                    // Find the corresponding SimpleMesh for this primitive
                    // We need to iterate through mesh groups to find which SimpleMesh this primitive corresponds to
                    var found_simple_mesh: ?*const SimpleMesh = null;
                    var simple_mesh_idx: usize = 0;

                    // Find the SimpleMesh index that corresponds to this primitive
                    var bone_mesh_groups_iter = mesh_groups.iterator();
                    while (bone_mesh_groups_iter.next()) |group_entry| {
                        const group_mesh_name = group_entry.key_ptr.*;
                        const group_mesh_indices = group_entry.value_ptr.*;

                        if (std.mem.eql(u8, group_mesh_name, gltf_mesh.name)) {
                            if (primitive_idx < group_mesh_indices.items.len) {
                                simple_mesh_idx = group_mesh_indices.items[primitive_idx];
                                found_simple_mesh = &model.meshes.items[simple_mesh_idx];
                                break;
                            }
                        }
                    }

                    if (found_simple_mesh) |simple_mesh| {
                        // Check if any vertex has bone data
                        var has_bone_data = false;
                        for (simple_mesh.vertices.items) |vertex| {
                            if (vertex.bone_ids[0] >= 0) {
                                has_bone_data = true;
                                break;
                            }
                        }

                        if (has_bone_data) {
                            if (self.verbose) {
                                std.debug.print("      Adding bone attributes to primitive {d} (SimpleMesh {d}: {s})\n", .{ primitive_idx, simple_mesh_idx, simple_mesh.name });
                            }
                            const joints_accessor = try self.writeVertexAttribute(simple_mesh, "JOINTS_0", &buffer_views, &accessors, joint_indices);
                            const weights_accessor = try self.writeVertexAttribute(simple_mesh, "WEIGHTS_0", &buffer_views, &accessors, null);

                            // Add to mesh primitive attributes
                            try primitive.attributes.put("JOINTS_0", joints_accessor);
                            try primitive.attributes.put("WEIGHTS_0", weights_accessor);
                        }
                    }
                }
            }
        }

        // Create skin object if bones exist
        var skins_opt: ?[]GltfSkin = null;
        if (model.bones.items.len > 0) {
            if (self.verbose) {
                std.debug.print("  Creating skin with {d} joints\n", .{model.bones.items.len});
            }

            // Create inverse bind matrices accessor
            const ibm_start = self.binary_data.items.len;
            for (model.bones.items) |*bone| {
                // Clean up floating-point precision errors in the matrix
                var cleaned_matrix = bone.offset_matrix;
                cleaned_matrix = self.cleanMatrix(cleaned_matrix);

                // Convert cleaned matrix to bytes
                const matrix_bytes = std.mem.asBytes(&cleaned_matrix);
                try self.binary_data.appendSlice(matrix_bytes);
            }

            // Create buffer view for inverse bind matrices
            const ibm_buffer_view = GltfBufferView{
                .buffer = 0,
                .byteOffset = @intCast(ibm_start),
                .byteLength = @intCast(model.bones.items.len * 16 * @sizeOf(f32)),
                .target = null,
            };
            try buffer_views.append(ibm_buffer_view);

            // Create accessor for inverse bind matrices
            const ibm_accessor = GltfAccessor{
                .bufferView = @intCast(buffer_views.items.len - 1),
                .byteOffset = 0,
                .componentType = 5126, // FLOAT
                .count = @intCast(model.bones.items.len),
                .type = "MAT4",
            };
            try accessors.append(ibm_accessor);

            // Find proper skeleton root as lowest common ancestor of all joints
            const skeleton_root = if (joint_indices.len > 0)
                try findSkeletonRoot(allocator, nodes.items, joint_indices)
            else
                null;

            // Create skin
            const skin = GltfSkin{
                .inverseBindMatrices = @intCast(accessors.items.len - 1),
                .skeleton = skeleton_root,
                .joints = joint_indices,
                .name = "character_skin",
            };

            skins_opt = try allocator.dupe(GltfSkin, &[_]GltfSkin{skin});

            // Link only nodes with skeletal meshes to skin
            if (model.meshes.items.len > 0) {
                var skinned_node_count: u32 = 0;

                // Create reverse mapping: glTF mesh index -> SimpleMesh index
                var gltf_to_simple_mesh_map = std.AutoHashMap(u32, usize).init(allocator);
                defer gltf_to_simple_mesh_map.deinit();

                var simple_to_gltf_iter = simple_to_gltf_mesh_map.iterator();
                while (simple_to_gltf_iter.next()) |entry| {
                    try gltf_to_simple_mesh_map.put(entry.value_ptr.*, entry.key_ptr.*);
                }

                for (nodes.items, 0..) |*node, i| {
                    if (node.mesh != null) {
                        const gltf_mesh_index = node.mesh.?;

                        // Check if this mesh has bone data
                        if (gltf_to_simple_mesh_map.get(gltf_mesh_index)) |simple_mesh_idx| {
                            const simple_mesh = &model.meshes.items[simple_mesh_idx];

                            // Only assign skin if mesh has bone weights
                            if (meshHasBoneWeights(simple_mesh)) {
                                node.skin = 0; // Reference to first (and only) skin
                                skinned_node_count += 1;
                                if (self.verbose) {
                                    std.debug.print("    Linked node {d} '{s}' with skeletal mesh {d} to skin\n", .{ i, node.name orelse "unnamed", gltf_mesh_idx });
                                }
                            } else {
                                if (self.verbose) {
                                    std.debug.print("    Node {d} '{s}' with non-skeletal mesh {d} remains unbound\n", .{ i, node.name orelse "unnamed", gltf_mesh_idx });
                                }
                            }
                        }
                    }
                }
                if (self.verbose) {
                    std.debug.print("    Skin created with {d} joints, linked to {d} mesh nodes\n", .{ joint_indices.len, skinned_node_count });
                }
                if (skinned_node_count == 0 and self.verbose) {
                    std.debug.print("    Warning: Skin created but no nodes with meshes found to link it to\n", .{});
                }
            }
        }

        // Create initial scene with root nodes
        var scene_struct = GltfScene{
            .nodes = try scene_root_nodes.toOwnedSlice(),
        };

        // Hoist skinned mesh nodes to scene root to avoid parent transform conflicts
        if (skins_opt != null) {
            if (self.verbose) {
                std.debug.print("  Hoisting skinned mesh nodes to scene root...\n", .{});
            }
            try hoistSkinnedMeshesToRoot(allocator, nodes.items, &scene_struct);
        }

        // Process animations if ASSIMP scene is provided and has animations
        var animations_opt: ?[]GltfAnimation = null;
        if (scene) |ai_scene_ptr| {
            const ai_scene: *const assimp.aiScene = @ptrCast(@alignCast(ai_scene_ptr));
            const animations = try self.processAnimations(ai_scene, &node_name_map, &buffer_views, &accessors);
            if (animations.len > 0) {
                animations_opt = animations;
            }
        }

        // Create buffer description AFTER all data has been written
        const buffer = GltfBuffer{
            .byteLength = @intCast(self.binary_data.items.len),
            .uri = "data.bin",
        };

        var gltf_doc = GltfDocument{
            .asset = GltfAsset{},
            .scenes = try allocator.dupe(GltfScene, &[_]GltfScene{scene_struct}),
            .nodes = try nodes.toOwnedSlice(),
            .meshes = meshes,
            .buffers = try allocator.dupe(GltfBuffer, &[_]GltfBuffer{buffer}),
            .bufferViews = try buffer_views.toOwnedSlice(),
            .accessors = try accessors.toOwnedSlice(),
            .animations = animations_opt,
            .skins = skins_opt,
        };

        // Add material data if available
        if (material_proc) |*mat_proc| {
            defer mat_proc.deinit();

            if (mat_proc.materials.items.len > 0) {
                gltf_doc.materials = try mat_proc.materials.toOwnedSlice();
            }
            if (mat_proc.textures.items.len > 0) {
                gltf_doc.textures = try mat_proc.textures.toOwnedSlice();
            }
            if (mat_proc.images.items.len > 0) {
                gltf_doc.images = try mat_proc.images.toOwnedSlice();
            }
            if (mat_proc.samplers.items.len > 0) {
                gltf_doc.samplers = try mat_proc.samplers.toOwnedSlice();
            }
        }

        return gltf_doc;
    }

    fn writeVertexAttribute(self: *GltfExporter, mesh: *const SimpleMesh, attribute: []const u8, buffer_views: *ArrayList(GltfBufferView), accessors: *ArrayList(GltfAccessor), joint_remapping: ?[]const u32) !u32 {
        _ = joint_remapping; // No longer used - preserve original bone indices
        const start_offset: u32 = @intCast(self.binary_data.items.len);
        var min_values: [4]f32 = undefined;
        var max_values: [4]f32 = undefined;
        var calculate_bounds = false;
        var first_vertex = true;

        if (std.mem.eql(u8, attribute, "POSITION")) {
            calculate_bounds = true;
            // Write position data
            for (mesh.vertices.items) |vertex| {
                const pos = vertex.position;
                try self.writeFloat(pos.x);
                try self.writeFloat(pos.y);
                try self.writeFloat(pos.z);

                // Update min/max for bounds
                if (first_vertex) {
                    min_values[0] = pos.x;
                    min_values[1] = pos.y;
                    min_values[2] = pos.z;
                    max_values[0] = pos.x;
                    max_values[1] = pos.y;
                    max_values[2] = pos.z;
                    first_vertex = false;
                } else {
                    min_values[0] = @min(min_values[0], pos.x);
                    min_values[1] = @min(min_values[1], pos.y);
                    min_values[2] = @min(min_values[2], pos.z);
                    max_values[0] = @max(max_values[0], pos.x);
                    max_values[1] = @max(max_values[1], pos.y);
                    max_values[2] = @max(max_values[2], pos.z);
                }
            }
        } else if (std.mem.eql(u8, attribute, "NORMAL")) {
            calculate_bounds = true;
            // Write normal data
            for (mesh.vertices.items) |vertex| {
                const norm = vertex.normal;
                try self.writeFloat(norm.x);
                try self.writeFloat(norm.y);
                try self.writeFloat(norm.z);

                // Update min/max for bounds
                if (first_vertex) {
                    min_values[0] = norm.x;
                    min_values[1] = norm.y;
                    min_values[2] = norm.z;
                    max_values[0] = norm.x;
                    max_values[1] = norm.y;
                    max_values[2] = norm.z;
                    first_vertex = false;
                } else {
                    min_values[0] = @min(min_values[0], norm.x);
                    min_values[1] = @min(min_values[1], norm.y);
                    min_values[2] = @min(min_values[2], norm.z);
                    max_values[0] = @max(max_values[0], norm.x);
                    max_values[1] = @max(max_values[1], norm.y);
                    max_values[2] = @max(max_values[2], norm.z);
                }
            }
        } else if (std.mem.eql(u8, attribute, "TEXCOORD_0")) {
            calculate_bounds = true;
            // Write UV data
            for (mesh.vertices.items) |vertex| {
                const uv = vertex.uv;
                try self.writeFloat(uv.x);
                try self.writeFloat(uv.y);

                // Update min/max for bounds
                if (first_vertex) {
                    min_values[0] = uv.x;
                    min_values[1] = uv.y;
                    max_values[0] = uv.x;
                    max_values[1] = uv.y;
                    first_vertex = false;
                } else {
                    min_values[0] = @min(min_values[0], uv.x);
                    min_values[1] = @min(min_values[1], uv.y);
                    max_values[0] = @max(max_values[0], uv.x);
                    max_values[1] = @max(max_values[1], uv.y);
                }
            }
        } else if (std.mem.eql(u8, attribute, "JOINTS_0")) {
            // Write joint indices as unsigned short (VEC4)
            // For glTF→glTF conversion, preserve original bone indices to maintain vertex mapping
            for (mesh.vertices.items) |vertex| {
                for (vertex.bone_ids) |bone_id| {
                    const joint_id: u16 = if (bone_id >= 0)
                        @intCast(bone_id)
                    else
                        0;
                    try self.writeUInt16(joint_id);
                }
            }
        } else if (std.mem.eql(u8, attribute, "WEIGHTS_0")) {
            calculate_bounds = true;
            // Write bone weights as float (VEC4) with normalization
            for (mesh.vertices.items) |vertex| {
                // Normalize bone weights to ensure they sum to 1.0
                var normalized_weights = vertex.bone_weights;
                const weight_sum = normalized_weights[0] + normalized_weights[1] + normalized_weights[2] + normalized_weights[3];

                if (weight_sum > 0.0) {
                    // Normalize to sum to 1.0
                    normalized_weights[0] /= weight_sum;
                    normalized_weights[1] /= weight_sum;
                    normalized_weights[2] /= weight_sum;
                    normalized_weights[3] /= weight_sum;
                }

                for (normalized_weights, 0..) |weight, i| {
                    try self.writeFloat(weight);

                    // Update min/max for bounds
                    if (first_vertex) {
                        min_values[i] = weight;
                        max_values[i] = weight;
                        if (i == 3) first_vertex = false;
                    } else {
                        min_values[i] = @min(min_values[i], weight);
                        max_values[i] = @max(max_values[i], weight);
                    }
                }
            }
        }

        const byte_length: u32 = @intCast(self.binary_data.items.len - start_offset);

        // Create buffer view
        const buffer_view_idx: u32 = @intCast(buffer_views.items.len);
        try buffer_views.append(GltfBufferView{
            .buffer = 0,
            .byteOffset = start_offset,
            .byteLength = byte_length,
            .target = 34962, // ARRAY_BUFFER
        });

        // Create accessor
        const accessor_idx: u32 = @intCast(accessors.items.len);
        var min_slice: ?[]f32 = null;
        var max_slice: ?[]f32 = null;

        if (calculate_bounds) {
            // Set bounds for attributes that need them
            const component_count: usize = if (std.mem.eql(u8, attribute, "TEXCOORD_0")) 2 else if (std.mem.eql(u8, attribute, "WEIGHTS_0")) 4 else 3;
            min_slice = try self.allocator.dupe(f32, min_values[0..component_count]);
            max_slice = try self.allocator.dupe(f32, max_values[0..component_count]);
        }

        // Determine component type and vector type based on attribute
        const component_type: u32 = if (std.mem.eql(u8, attribute, "JOINTS_0"))
            5123 // UNSIGNED_SHORT
        else
            5126; // FLOAT

        const vector_type: []const u8 = if (std.mem.eql(u8, attribute, "TEXCOORD_0"))
            "VEC2"
        else if (std.mem.eql(u8, attribute, "JOINTS_0") or std.mem.eql(u8, attribute, "WEIGHTS_0"))
            "VEC4"
        else
            "VEC3";

        try accessors.append(GltfAccessor{
            .bufferView = buffer_view_idx,
            .componentType = component_type,
            .count = @intCast(mesh.vertices.items.len),
            .type = vector_type,
            .min = min_slice,
            .max = max_slice,
        });

        return accessor_idx;
    }

    fn writeIndexData(self: *GltfExporter, mesh: *const SimpleMesh, buffer_views: *ArrayList(GltfBufferView), accessors: *ArrayList(GltfAccessor)) !u32 {
        const start_offset: u32 = @intCast(self.binary_data.items.len);

        // Write index data
        for (mesh.indices.items) |index| {
            try self.writeUInt32(index);
        }

        const byte_length: u32 = @intCast(self.binary_data.items.len - start_offset);

        // Create buffer view
        const buffer_view_idx: u32 = @intCast(buffer_views.items.len);
        try buffer_views.append(GltfBufferView{
            .buffer = 0,
            .byteOffset = start_offset,
            .byteLength = byte_length,
            .target = 34963, // ELEMENT_ARRAY_BUFFER
        });

        // Create accessor
        const accessor_idx: u32 = @intCast(accessors.items.len);
        try accessors.append(GltfAccessor{
            .bufferView = buffer_view_idx,
            .componentType = 5125, // UNSIGNED_INT
            .count = @intCast(mesh.indices.items.len),
            .type = "SCALAR",
        });

        return accessor_idx;
    }

    fn writeFloat(self: *GltfExporter, value: f32) !void {
        const bytes = std.mem.asBytes(&value);
        try self.binary_data.appendSlice(bytes);
    }

    fn writeUInt32(self: *GltfExporter, value: u32) !void {
        const bytes = std.mem.asBytes(&value);
        try self.binary_data.appendSlice(bytes);
    }

    fn writeUInt16(self: *GltfExporter, value: u16) !void {
        const bytes = std.mem.asBytes(&value);
        try self.binary_data.appendSlice(bytes);
    }

    fn getBinPath(self: *GltfExporter, gltf_path: []const u8) ![]u8 {
        // Replace .gltf extension with .bin
        if (std.mem.endsWith(u8, gltf_path, ".gltf")) {
            const base = gltf_path[0 .. gltf_path.len - 5];
            return std.fmt.allocPrint(self.allocator, "{s}.bin", .{base});
        } else {
            return std.fmt.allocPrint(self.allocator, "{s}.bin", .{gltf_path});
        }
    }

    fn writeBinaryFile(self: *GltfExporter, bin_path: []const u8) !void {
        const file = try std.fs.cwd().createFile(bin_path, .{});
        defer file.close();
        try file.writeAll(self.binary_data.items);
    }

    fn writeJsonFile(self: *GltfExporter, json_path: []const u8, gltf_doc: *const GltfDocument, bin_filename: []const u8) !void {
        const file = try std.fs.cwd().createFile(json_path, .{});
        defer file.close();

        // Get just the filename from the full bin path
        const bin_name = std.fs.path.basename(bin_filename);

        // Create a modified buffer reference with just the filename
        var buffer_copy = gltf_doc.buffers[0];
        buffer_copy.uri = bin_name;

        // Write JSON with proper formatting
        try file.writeAll("{\n");
        try file.writeAll("  \"asset\": {\n");
        try std.fmt.format(file.writer(), "    \"version\": \"{s}\",\n", .{gltf_doc.asset.version});
        try std.fmt.format(file.writer(), "    \"generator\": \"{s}\"\n", .{gltf_doc.asset.generator});
        try file.writeAll("  },\n");

        try file.writeAll("  \"scene\": 0,\n");
        try file.writeAll("  \"scenes\": [\n");
        try file.writeAll("    {\n");
        try file.writeAll("      \"nodes\": [");
        for (gltf_doc.scenes[0].nodes, 0..) |node_idx, i| {
            if (i > 0) try file.writeAll(", ");
            try std.fmt.format(file.writer(), "{d}", .{node_idx});
        }
        try file.writeAll("]\n");
        try file.writeAll("    }\n");
        try file.writeAll("  ],\n");

        // Write nodes
        try file.writeAll("  \"nodes\": [\n");
        for (gltf_doc.nodes, 0..) |node, i| {
            if (i > 0) try file.writeAll(",\n");
            try file.writeAll("    {\n");

            var has_fields = false;

            if (node.mesh) |mesh_idx| {
                try std.fmt.format(file.writer(), "      \"mesh\": {d}", .{mesh_idx});
                has_fields = true;
            }

            if (node.skin) |skin_idx| {
                if (has_fields) try file.writeAll(",\n");
                try std.fmt.format(file.writer(), "      \"skin\": {d}", .{skin_idx});
                has_fields = true;
            }

            if (node.name) |name| {
                if (has_fields) try file.writeAll(",\n");
                try std.fmt.format(file.writer(), "      \"name\": \"{s}\"", .{name});
                has_fields = true;
            }

            if (node.children) |children| {
                if (has_fields) try file.writeAll(",\n");
                try file.writeAll("      \"children\": [");
                for (children, 0..) |child, idx| {
                    if (idx > 0) try file.writeAll(", ");
                    try std.fmt.format(file.writer(), "{d}", .{child});
                }
                try file.writeAll("]");
                has_fields = true;
            }

            if (node.translation) |translation| {
                if (has_fields) try file.writeAll(",\n");
                try std.fmt.format(file.writer(), "      \"translation\": [{d}, {d}, {d}]", .{ translation[0], translation[1], translation[2] });
                has_fields = true;
            }

            if (node.rotation) |rotation| {
                if (has_fields) try file.writeAll(",\n");
                try std.fmt.format(file.writer(), "      \"rotation\": [{d}, {d}, {d}, {d}]", .{ rotation[0], rotation[1], rotation[2], rotation[3] });
                has_fields = true;
            }

            if (node.scale) |scale| {
                if (has_fields) try file.writeAll(",\n");
                try std.fmt.format(file.writer(), "      \"scale\": [{d}, {d}, {d}]", .{ scale[0], scale[1], scale[2] });
                has_fields = true;
            }

            if (node.matrix) |matrix| {
                if (has_fields) try file.writeAll(",\n");
                try file.writeAll("      \"matrix\": [");
                for (matrix, 0..) |value, idx| {
                    if (idx > 0) try file.writeAll(", ");
                    try std.fmt.format(file.writer(), "{d}", .{value});
                }
                try file.writeAll("]");
                has_fields = true;
            }

            if (has_fields) try file.writeAll("\n");
            try file.writeAll("    }");
        }
        try file.writeAll("\n  ],\n");

        // Write meshes manually
        try self.writeMeshesSection(file, gltf_doc.meshes);

        // Write materials, textures, images, samplers if present
        if (gltf_doc.materials) |materials| {
            try self.writeMaterialsSection(file, materials);
        }
        if (gltf_doc.textures) |textures| {
            try self.writeTexturesSection(file, textures);
        }
        if (gltf_doc.images) |images| {
            try self.writeImagesSection(file, images);
        }
        if (gltf_doc.samplers) |samplers| {
            try self.writeSamplersSection(file, samplers);
        }

        // Write skins if present
        if (gltf_doc.skins) |skins| {
            try self.writeSkinsSection(file, skins);
        }

        // Write animations if present
        if (gltf_doc.animations) |animations| {
            try self.writeAnimationsSection(file, animations);
        }

        try self.writeBuffersSection(file, &[_]GltfBuffer{buffer_copy});
        try self.writeBufferViewsSection(file, gltf_doc.bufferViews);
        try self.writeAccessorsSection(file, gltf_doc.accessors);

        try file.writeAll("}\n");
    }

    fn writeMeshesSection(self: *GltfExporter, file: std.fs.File, meshes: []const GltfMesh) !void {
        _ = self;
        try file.writeAll("  \"meshes\": [\n");
        for (meshes, 0..) |mesh, i| {
            if (i > 0) try file.writeAll(",\n");
            try file.writeAll("    {\n");
            try std.fmt.format(file.writer(), "      \"name\": \"{s}\",\n", .{mesh.name});
            try file.writeAll("      \"primitives\": [\n");
            for (mesh.primitives, 0..) |primitive, j| {
                if (j > 0) try file.writeAll(",\n");
                try file.writeAll("        {\n");
                try file.writeAll("          \"attributes\": {\n");

                var attr_iter = primitive.attributes.iterator();
                var attr_count: u32 = 0;
                while (attr_iter.next()) |entry| {
                    if (attr_count > 0) try file.writeAll(",\n");
                    try std.fmt.format(file.writer(), "            \"{s}\": {d}", .{ entry.key_ptr.*, entry.value_ptr.* });
                    attr_count += 1;
                }
                try file.writeAll("\n          }");

                if (primitive.indices) |indices| {
                    try std.fmt.format(file.writer(), ",\n          \"indices\": {d}", .{indices});
                }
                if (primitive.material) |material| {
                    try std.fmt.format(file.writer(), ",\n          \"material\": {d}", .{material});
                }
                try std.fmt.format(file.writer(), ",\n          \"mode\": {d}", .{primitive.mode});
                try file.writeAll("\n        }");
            }
            try file.writeAll("\n      ]\n");
            try file.writeAll("    }");
        }
        try file.writeAll("\n  ],\n");
    }

    fn writeBuffersSection(self: *GltfExporter, file: std.fs.File, buffers: []const GltfBuffer) !void {
        _ = self;
        try file.writeAll("  \"buffers\": [\n");
        for (buffers, 0..) |buffer, i| {
            if (i > 0) try file.writeAll(",\n");
            try file.writeAll("    {\n");
            try std.fmt.format(file.writer(), "      \"byteLength\": {d},\n", .{buffer.byteLength});
            try std.fmt.format(file.writer(), "      \"uri\": \"{s}\"\n", .{buffer.uri});
            try file.writeAll("    }");
        }
        try file.writeAll("\n  ],\n");
    }

    fn writeBufferViewsSection(self: *GltfExporter, file: std.fs.File, buffer_views: []const GltfBufferView) !void {
        _ = self;
        try file.writeAll("  \"bufferViews\": [\n");
        for (buffer_views, 0..) |view, i| {
            if (i > 0) try file.writeAll(",\n");
            try file.writeAll("    {\n");
            try std.fmt.format(file.writer(), "      \"buffer\": {d},\n", .{view.buffer});
            try std.fmt.format(file.writer(), "      \"byteOffset\": {d},\n", .{view.byteOffset});
            try std.fmt.format(file.writer(), "      \"byteLength\": {d}", .{view.byteLength});
            if (view.target) |target| {
                try std.fmt.format(file.writer(), ",\n      \"target\": {d}", .{target});
            }
            try file.writeAll("\n    }");
        }
        try file.writeAll("\n  ],\n");
    }

    fn writeAccessorsSection(self: *GltfExporter, file: std.fs.File, accessors: []const GltfAccessor) !void {
        _ = self;
        try file.writeAll("  \"accessors\": [\n");
        for (accessors, 0..) |accessor, i| {
            if (i > 0) try file.writeAll(",\n");
            try file.writeAll("    {\n");
            try std.fmt.format(file.writer(), "      \"bufferView\": {d},\n", .{accessor.bufferView});
            try std.fmt.format(file.writer(), "      \"byteOffset\": {d},\n", .{accessor.byteOffset});
            try std.fmt.format(file.writer(), "      \"componentType\": {d},\n", .{accessor.componentType});
            try std.fmt.format(file.writer(), "      \"count\": {d},\n", .{accessor.count});
            try std.fmt.format(file.writer(), "      \"type\": \"{s}\"", .{accessor.type});

            if (accessor.min) |min| {
                try file.writeAll(",\n      \"min\": [");
                for (min, 0..) |val, j| {
                    if (j > 0) try file.writeAll(", ");
                    try std.fmt.format(file.writer(), "{d}", .{val});
                }
                try file.writeAll("]");
            }

            if (accessor.max) |max| {
                try file.writeAll(",\n      \"max\": [");
                for (max, 0..) |val, j| {
                    if (j > 0) try file.writeAll(", ");
                    try std.fmt.format(file.writer(), "{d}", .{val});
                }
                try file.writeAll("]");
            }

            try file.writeAll("\n    }");
        }
        try file.writeAll("\n  ]\n");
    }

    fn writeMaterialsSection(self: *GltfExporter, file: std.fs.File, materials: []const GltfMaterial) !void {
        _ = self;
        try file.writeAll("  \"materials\": [\n");
        for (materials, 0..) |material, i| {
            if (i > 0) try file.writeAll(",\n");
            try file.writeAll("    {\n");
            try std.fmt.format(file.writer(), "      \"name\": \"{s}\",\n", .{material.name});

            // PBR metallic roughness
            try file.writeAll("      \"pbrMetallicRoughness\": {\n");
            try std.fmt.format(file.writer(), "        \"baseColorFactor\": [{d}, {d}, {d}, {d}],\n", .{
                material.pbrMetallicRoughness.baseColorFactor[0],
                material.pbrMetallicRoughness.baseColorFactor[1],
                material.pbrMetallicRoughness.baseColorFactor[2],
                material.pbrMetallicRoughness.baseColorFactor[3],
            });
            try std.fmt.format(file.writer(), "        \"metallicFactor\": {d},\n", .{material.pbrMetallicRoughness.metallicFactor});
            try std.fmt.format(file.writer(), "        \"roughnessFactor\": {d}", .{material.pbrMetallicRoughness.roughnessFactor});

            if (material.pbrMetallicRoughness.baseColorTexture) |texture| {
                try std.fmt.format(file.writer(), ",\n        \"baseColorTexture\": {{\"index\": {d}}}", .{texture.index});
            }
            if (material.pbrMetallicRoughness.metallicRoughnessTexture) |texture| {
                try std.fmt.format(file.writer(), ",\n        \"metallicRoughnessTexture\": {{\"index\": {d}}}", .{texture.index});
            }
            try file.writeAll("\n      }");

            // Normal texture
            if (material.normalTexture) |texture| {
                try std.fmt.format(file.writer(), ",\n      \"normalTexture\": {{\"index\": {d}}}", .{texture.index});
            }

            // Emissive texture and factor
            if (material.emissiveTexture) |texture| {
                try std.fmt.format(file.writer(), ",\n      \"emissiveTexture\": {{\"index\": {d}}}", .{texture.index});
            }
            try std.fmt.format(file.writer(), ",\n      \"emissiveFactor\": [{d}, {d}, {d}]", .{
                material.emissiveFactor[0],
                material.emissiveFactor[1],
                material.emissiveFactor[2],
            });

            // Alpha mode
            try std.fmt.format(file.writer(), ",\n      \"alphaMode\": \"{s}\"", .{material.alphaMode});

            try file.writeAll("\n    }");
        }
        try file.writeAll("\n  ],\n");
    }

    fn writeTexturesSection(self: *GltfExporter, file: std.fs.File, textures: []const GltfTexture) !void {
        _ = self;
        try file.writeAll("  \"textures\": [\n");
        for (textures, 0..) |texture, i| {
            if (i > 0) try file.writeAll(",\n");
            try file.writeAll("    {\n");
            try std.fmt.format(file.writer(), "      \"source\": {d}", .{texture.source});
            if (texture.sampler) |sampler| {
                try std.fmt.format(file.writer(), ",\n      \"sampler\": {d}", .{sampler});
            }
            try file.writeAll("\n    }");
        }
        try file.writeAll("\n  ],\n");
    }

    fn writeImagesSection(self: *GltfExporter, file: std.fs.File, images: []const GltfImage) !void {
        _ = self;
        try file.writeAll("  \"images\": [\n");
        for (images, 0..) |image, i| {
            if (i > 0) try file.writeAll(",\n");
            try file.writeAll("    {\n");
            try std.fmt.format(file.writer(), "      \"uri\": \"{s}\"", .{image.uri});
            if (image.name) |name| {
                try std.fmt.format(file.writer(), ",\n      \"name\": \"{s}\"", .{name});
            }
            try file.writeAll("\n    }");
        }
        try file.writeAll("\n  ],\n");
    }

    fn writeSamplersSection(self: *GltfExporter, file: std.fs.File, samplers: []const GltfSampler) !void {
        _ = self;
        try file.writeAll("  \"samplers\": [\n");
        for (samplers, 0..) |sampler, i| {
            if (i > 0) try file.writeAll(",\n");
            try file.writeAll("    {\n");
            try std.fmt.format(file.writer(), "      \"wrapS\": {d},\n", .{sampler.wrapS});
            try std.fmt.format(file.writer(), "      \"wrapT\": {d}", .{sampler.wrapT});
            if (sampler.magFilter) |mag| {
                try std.fmt.format(file.writer(), ",\n      \"magFilter\": {d}", .{mag});
            }
            if (sampler.minFilter) |min| {
                try std.fmt.format(file.writer(), ",\n      \"minFilter\": {d}", .{min});
            }
            try file.writeAll("\n    }");
        }
        try file.writeAll("\n  ],\n");
    }

    fn writeSkinsSection(self: *GltfExporter, file: std.fs.File, skins: []const GltfSkin) !void {
        _ = self;
        try file.writeAll("  \"skins\": [\n");
        for (skins, 0..) |skin, i| {
            if (i > 0) try file.writeAll(",\n");
            try file.writeAll("    {\n");

            if (skin.inverseBindMatrices) |ibm_accessor| {
                try std.fmt.format(file.writer(), "      \"inverseBindMatrices\": {d},\n", .{ibm_accessor});
            }

            if (skin.skeleton) |skeleton_node| {
                try std.fmt.format(file.writer(), "      \"skeleton\": {d},\n", .{skeleton_node});
            }

            try file.writeAll("      \"joints\": [");
            for (skin.joints, 0..) |joint, j| {
                if (j > 0) try file.writeAll(", ");
                try std.fmt.format(file.writer(), "{d}", .{joint});
            }
            try file.writeAll("]");

            if (skin.name) |name| {
                try std.fmt.format(file.writer(), ",\n      \"name\": \"{s}\"", .{name});
            }

            try file.writeAll("\n    }");
        }
        try file.writeAll("\n  ],\n");
    }

    fn writeAnimationsSection(self: *GltfExporter, file: std.fs.File, animations: []const GltfAnimation) !void {
        _ = self;
        try file.writeAll("  \"animations\": [\n");
        for (animations, 0..) |animation, i| {
            if (i > 0) try file.writeAll(",\n");
            try file.writeAll("    {\n");
            try std.fmt.format(file.writer(), "      \"name\": \"{s}\",\n", .{animation.name});

            // Write channels
            try file.writeAll("      \"channels\": [\n");
            for (animation.channels, 0..) |channel, j| {
                if (j > 0) try file.writeAll(",\n");
                try file.writeAll("        {\n");
                try std.fmt.format(file.writer(), "          \"sampler\": {d},\n", .{channel.sampler});
                try file.writeAll("          \"target\": {\n");
                try std.fmt.format(file.writer(), "            \"node\": {d},\n", .{channel.target.node});
                try std.fmt.format(file.writer(), "            \"path\": \"{s}\"\n", .{channel.target.path});
                try file.writeAll("          }\n");
                try file.writeAll("        }");
            }
            try file.writeAll("\n      ],\n");

            // Write samplers
            try file.writeAll("      \"samplers\": [\n");
            for (animation.samplers, 0..) |sampler, k| {
                if (k > 0) try file.writeAll(",\n");
                try file.writeAll("        {\n");
                try std.fmt.format(file.writer(), "          \"input\": {d},\n", .{sampler.input});
                try std.fmt.format(file.writer(), "          \"output\": {d},\n", .{sampler.output});
                try std.fmt.format(file.writer(), "          \"interpolation\": \"{s}\"\n", .{sampler.interpolation});
                try file.writeAll("        }");
            }
            try file.writeAll("\n      ]\n");

            try file.writeAll("    }");
        }
        try file.writeAll("\n  ],\n");
    }

    fn cleanupGltfDocument(self: *GltfExporter, gltf_doc: *GltfDocument) void {
        // Clean up allocated strings and arrays
        for (gltf_doc.nodes) |node| {
            if (node.name) |name| {
                self.allocator.free(name);
            }
        }

        for (gltf_doc.meshes) |*mesh| {
            self.allocator.free(mesh.name);
            for (mesh.primitives) |*primitive| {
                primitive.attributes.deinit();
            }
            self.allocator.free(mesh.primitives);
        }

        for (gltf_doc.accessors) |accessor| {
            if (accessor.min) |min| self.allocator.free(min);
            if (accessor.max) |max| self.allocator.free(max);
        }

        self.allocator.free(gltf_doc.scenes[0].nodes); // Free scene_nodes array
        self.allocator.free(gltf_doc.scenes);
        self.allocator.free(gltf_doc.nodes);
        self.allocator.free(gltf_doc.meshes);
        self.allocator.free(gltf_doc.buffers);
        self.allocator.free(gltf_doc.bufferViews);
        self.allocator.free(gltf_doc.accessors);
    }

    // Animation processing methods
    fn processAnimations(self: *GltfExporter, ai_scene: *const assimp.aiScene, node_name_map: *const std.StringHashMap(u32), buffer_views: *ArrayList(GltfBufferView), accessors: *ArrayList(GltfAccessor)) ![]GltfAnimation {
        if (ai_scene.mNumAnimations == 0) {
            return &[_]GltfAnimation{};
        }

        if (self.verbose) {
            std.debug.print("Processing {d} animations for glTF export...\n", .{ai_scene.mNumAnimations});
        }

        var animations = ArrayList(GltfAnimation).init(self.allocator);

        for (0..ai_scene.mNumAnimations) |anim_idx| {
            const ai_anim = ai_scene.mAnimations[anim_idx];
            const animation = try self.processAnimation(ai_anim, anim_idx, node_name_map, buffer_views, accessors);
            try animations.append(animation);
        }

        return animations.toOwnedSlice();
    }

    fn processAnimation(self: *GltfExporter, ai_anim: *const assimp.aiAnimation, anim_idx: usize, node_name_map: *const std.StringHashMap(u32), buffer_views: *ArrayList(GltfBufferView), accessors: *ArrayList(GltfAccessor)) !GltfAnimation {
        const anim_name = if (ai_anim.mName.length > 0)
            try self.allocator.dupe(u8, ai_anim.mName.data[0..ai_anim.mName.length])
        else
            try std.fmt.allocPrint(self.allocator, "animation_{d}", .{anim_idx});

        if (self.verbose) {
            std.debug.print("  Animation '{s}': duration={d}, ticks_per_second={d}, channels={d}\n", .{ anim_name, ai_anim.mDuration, ai_anim.mTicksPerSecond, ai_anim.mNumChannels });
        }

        // Convert ASSIMP channels to glTF channels and samplers
        var channels = ArrayList(GltfAnimationChannel).init(self.allocator);
        var samplers = ArrayList(GltfAnimationSampler).init(self.allocator);

        for (0..ai_anim.mNumChannels) |channel_idx| {
            const ai_channel = ai_anim.mChannels[channel_idx];
            try self.processAnimationChannel(ai_channel, ai_anim, node_name_map, &channels, &samplers, buffer_views, accessors);
        }

        return GltfAnimation{
            .name = anim_name,
            .channels = try channels.toOwnedSlice(),
            .samplers = try samplers.toOwnedSlice(),
        };
    }

    fn processAnimationChannel(
        self: *GltfExporter,
        ai_channel: *const assimp.aiNodeAnim,
        ai_animation: *const assimp.aiAnimation,
        node_name_map: *const std.StringHashMap(u32),
        channels: *ArrayList(GltfAnimationChannel),
        samplers: *ArrayList(GltfAnimationSampler),
        buffer_views: *ArrayList(GltfBufferView),
        accessors: *ArrayList(GltfAccessor),
    ) !void {
        const node_name = ai_channel.mNodeName.data[0..ai_channel.mNodeName.length];
        if (self.verbose) {
            std.debug.print(
                "    Channel: node='{s}', pos_keys={d}, rot_keys={d}, scale_keys={d}\n",
                .{ node_name, ai_channel.mNumPositionKeys, ai_channel.mNumRotationKeys, ai_channel.mNumScalingKeys },
            );
        }

        // Find node index by name, default to 0 if not found
        const node_index = node_name_map.get(node_name) orelse blk: {
            std.debug.print("    Warning: Node '{s}' not found in node mapping, using index 0\n", .{node_name});
            break :blk 0;
        };

        // Translation channel
        if (ai_channel.mNumPositionKeys > 0) {
            const time_accessor = try self.writeAnimationTimeData(
                ai_channel.mPositionKeys,
                ai_channel.mNumPositionKeys,
                ai_animation.mTicksPerSecond,
                buffer_views,
                accessors,
            );
            const position_accessor = try self.writePositionKeyframes(
                ai_channel,
                buffer_views,
                accessors,
            );

            const sampler_idx: u32 = @intCast(samplers.items.len);
            try samplers.append(GltfAnimationSampler{
                .input = time_accessor,
                .output = position_accessor,
            });

            try channels.append(GltfAnimationChannel{
                .sampler = sampler_idx,
                .target = GltfAnimationChannelTarget{
                    .node = node_index,
                    .path = "translation",
                },
            });
        }

        // Rotation channel
        if (ai_channel.mNumRotationKeys > 0) {
            const time_accessor = try self.writeAnimationTimeDataRot(ai_channel.mRotationKeys, ai_channel.mNumRotationKeys, ai_animation.mTicksPerSecond, buffer_views, accessors);
            const rotation_accessor = try self.writeRotationKeyframes(ai_channel, buffer_views, accessors);

            const sampler_idx: u32 = @intCast(samplers.items.len);
            try samplers.append(GltfAnimationSampler{
                .input = time_accessor,
                .output = rotation_accessor,
            });

            try channels.append(GltfAnimationChannel{
                .sampler = sampler_idx,
                .target = GltfAnimationChannelTarget{
                    .node = node_index,
                    .path = "rotation",
                },
            });
        }

        // Scale channel
        if (ai_channel.mNumScalingKeys > 0) {
            const time_accessor = try self.writeAnimationTimeDataScale(ai_channel.mScalingKeys, ai_channel.mNumScalingKeys, ai_animation.mTicksPerSecond, buffer_views, accessors);
            const scale_accessor = try self.writeScaleKeyframes(ai_channel, buffer_views, accessors);

            const sampler_idx: u32 = @intCast(samplers.items.len);
            try samplers.append(GltfAnimationSampler{
                .input = time_accessor,
                .output = scale_accessor,
            });

            try channels.append(GltfAnimationChannel{
                .sampler = sampler_idx,
                .target = GltfAnimationChannelTarget{
                    .node = node_index,
                    .path = "scale",
                },
            });
        }
    }

    // Helper function to convert ASSIMP time to glTF time (seconds)
    fn convertTimeToSeconds(time: f64, ticks_per_second: f64) f32 {
        const tps = if (ticks_per_second == 0.0) 25.0 else ticks_per_second; // Default to 25 FPS
        return @floatCast(time / tps);
    }

    // Helper function to clean up floating-point precision errors in 4x4 matrices
    fn cleanMatrix(self: *GltfExporter, matrix: [16]f32) [16]f32 {
        _ = self; // Unused parameter
        var cleaned = matrix;

        // For affine transformation matrices, element 15 (bottom-right) should be exactly 1.0
        // Fix common floating-point precision errors
        const epsilon = 1e-6;

        // Clean up the homogeneous coordinate (should be 1.0)
        if (@abs(cleaned[15] - 1.0) < epsilon) {
            cleaned[15] = 1.0;
        }

        // Clean up the bottom row (should be [0, 0, 0, 1])
        if (@abs(cleaned[12]) < epsilon) cleaned[12] = 0.0;
        if (@abs(cleaned[13]) < epsilon) cleaned[13] = 0.0;
        if (@abs(cleaned[14]) < epsilon) cleaned[14] = 0.0;

        // Clean up very small values that should be zero
        for (&cleaned) |*value| {
            if (@abs(value.*) < epsilon) {
                value.* = 0.0;
            }
        }

        return cleaned;
    }

    // Write animation time data for position keys
    fn writeAnimationTimeData(self: *GltfExporter, keys: [*c]assimp.aiVectorKey, count: u32, ticks_per_second: f64, buffer_views: *ArrayList(GltfBufferView), accessors: *ArrayList(GltfAccessor)) !u32 {
        const start_offset: u32 = @intCast(self.binary_data.items.len);

        // Calculate min/max time values
        var min_time: f32 = undefined;
        var max_time: f32 = undefined;
        var first_time = true;

        // Write time data
        for (0..count) |i| {
            const time = GltfExporter.convertTimeToSeconds(keys[i].mTime, ticks_per_second);
            if (first_time) {
                min_time = time;
                max_time = time;
                first_time = false;
            } else {
                min_time = @min(min_time, time);
                max_time = @max(max_time, time);
            }
            try self.binary_data.writer().writeAll(std.mem.asBytes(&time));
        }

        const byte_length: u32 = @intCast(self.binary_data.items.len - start_offset);

        // Create buffer view
        const buffer_view = GltfBufferView{
            .buffer = 0,
            .byteOffset = start_offset,
            .byteLength = byte_length,
        };

        const buffer_view_idx: u32 = @intCast(buffer_views.items.len);
        try buffer_views.append(buffer_view);

        // Create accessor with required min/max for animation input
        const min_slice = try self.allocator.dupe(f32, &[_]f32{min_time});
        const max_slice = try self.allocator.dupe(f32, &[_]f32{max_time});

        const accessor = GltfAccessor{
            .bufferView = buffer_view_idx,
            .componentType = 5126, // FLOAT
            .count = count,
            .type = "SCALAR",
            .min = min_slice,
            .max = max_slice,
        };

        const accessor_idx: u32 = @intCast(accessors.items.len);
        try accessors.append(accessor);

        return accessor_idx;
    }

    // Write animation time data for rotation keys
    fn writeAnimationTimeDataRot(self: *GltfExporter, keys: [*c]assimp.aiQuatKey, count: u32, ticks_per_second: f64, buffer_views: *ArrayList(GltfBufferView), accessors: *ArrayList(GltfAccessor)) !u32 {
        const start_offset: u32 = @intCast(self.binary_data.items.len);

        // Calculate min/max time values
        var min_time: f32 = undefined;
        var max_time: f32 = undefined;
        var first_time = true;

        // Write time data
        for (0..count) |i| {
            const time = GltfExporter.convertTimeToSeconds(keys[i].mTime, ticks_per_second);
            if (first_time) {
                min_time = time;
                max_time = time;
                first_time = false;
            } else {
                min_time = @min(min_time, time);
                max_time = @max(max_time, time);
            }
            try self.binary_data.writer().writeAll(std.mem.asBytes(&time));
        }

        const byte_length: u32 = @intCast(self.binary_data.items.len - start_offset);

        // Create buffer view
        const buffer_view = GltfBufferView{
            .buffer = 0,
            .byteOffset = start_offset,
            .byteLength = byte_length,
        };

        const buffer_view_idx: u32 = @intCast(buffer_views.items.len);
        try buffer_views.append(buffer_view);

        // Create accessor with required min/max for animation input
        const min_slice = try self.allocator.dupe(f32, &[_]f32{min_time});
        const max_slice = try self.allocator.dupe(f32, &[_]f32{max_time});

        const accessor = GltfAccessor{
            .bufferView = buffer_view_idx,
            .componentType = 5126, // FLOAT
            .count = count,
            .type = "SCALAR",
            .min = min_slice,
            .max = max_slice,
        };

        const accessor_idx: u32 = @intCast(accessors.items.len);
        try accessors.append(accessor);

        return accessor_idx;
    }

    // Write animation time data for scale keys
    fn writeAnimationTimeDataScale(self: *GltfExporter, keys: [*c]assimp.aiVectorKey, count: u32, ticks_per_second: f64, buffer_views: *ArrayList(GltfBufferView), accessors: *ArrayList(GltfAccessor)) !u32 {
        const start_offset: u32 = @intCast(self.binary_data.items.len);

        // Calculate min/max time values
        var min_time: f32 = undefined;
        var max_time: f32 = undefined;
        var first_time = true;

        // Write time data
        for (0..count) |i| {
            const time = GltfExporter.convertTimeToSeconds(keys[i].mTime, ticks_per_second);
            if (first_time) {
                min_time = time;
                max_time = time;
                first_time = false;
            } else {
                min_time = @min(min_time, time);
                max_time = @max(max_time, time);
            }
            try self.binary_data.writer().writeAll(std.mem.asBytes(&time));
        }

        const byte_length: u32 = @intCast(self.binary_data.items.len - start_offset);

        // Create buffer view
        const buffer_view = GltfBufferView{
            .buffer = 0,
            .byteOffset = start_offset,
            .byteLength = byte_length,
        };

        const buffer_view_idx: u32 = @intCast(buffer_views.items.len);
        try buffer_views.append(buffer_view);

        // Create accessor with required min/max for animation input
        const min_slice = try self.allocator.dupe(f32, &[_]f32{min_time});
        const max_slice = try self.allocator.dupe(f32, &[_]f32{max_time});

        const accessor = GltfAccessor{
            .bufferView = buffer_view_idx,
            .componentType = 5126, // FLOAT
            .count = count,
            .type = "SCALAR",
            .min = min_slice,
            .max = max_slice,
        };

        const accessor_idx: u32 = @intCast(accessors.items.len);
        try accessors.append(accessor);

        return accessor_idx;
    }

    // Write position keyframe data
    fn writePositionKeyframes(self: *GltfExporter, ai_channel: *const assimp.aiNodeAnim, buffer_views: *ArrayList(GltfBufferView), accessors: *ArrayList(GltfAccessor)) !u32 {
        const start_offset: u32 = @intCast(self.binary_data.items.len);

        // Write position data
        for (0..ai_channel.mNumPositionKeys) |i| {
            const pos = ai_channel.mPositionKeys[i].mValue;
            const position = [3]f32{ pos.x, pos.y, pos.z };
            try self.binary_data.writer().writeAll(std.mem.asBytes(&position));
        }

        const byte_length: u32 = @intCast(self.binary_data.items.len - start_offset);

        // Create buffer view
        const buffer_view = GltfBufferView{
            .buffer = 0,
            .byteOffset = start_offset,
            .byteLength = byte_length,
        };

        const buffer_view_idx: u32 = @intCast(buffer_views.items.len);
        try buffer_views.append(buffer_view);

        // Create accessor
        const accessor = GltfAccessor{
            .bufferView = buffer_view_idx,
            .componentType = 5126, // FLOAT
            .count = ai_channel.mNumPositionKeys,
            .type = "VEC3",
        };

        const accessor_idx: u32 = @intCast(accessors.items.len);
        try accessors.append(accessor);

        return accessor_idx;
    }

    // Write rotation keyframe data
    fn writeRotationKeyframes(self: *GltfExporter, ai_channel: *const assimp.aiNodeAnim, buffer_views: *ArrayList(GltfBufferView), accessors: *ArrayList(GltfAccessor)) !u32 {
        const start_offset: u32 = @intCast(self.binary_data.items.len);

        // Write quaternion data (x, y, z, w)
        for (0..ai_channel.mNumRotationKeys) |i| {
            const rot = ai_channel.mRotationKeys[i].mValue;
            const quaternion = [4]f32{ rot.x, rot.y, rot.z, rot.w };
            try self.binary_data.writer().writeAll(std.mem.asBytes(&quaternion));
        }

        const byte_length: u32 = @intCast(self.binary_data.items.len - start_offset);

        // Create buffer view
        const buffer_view = GltfBufferView{
            .buffer = 0,
            .byteOffset = start_offset,
            .byteLength = byte_length,
        };

        const buffer_view_idx: u32 = @intCast(buffer_views.items.len);
        try buffer_views.append(buffer_view);

        // Create accessor
        const accessor = GltfAccessor{
            .bufferView = buffer_view_idx,
            .componentType = 5126, // FLOAT
            .count = ai_channel.mNumRotationKeys,
            .type = "VEC4",
        };

        const accessor_idx: u32 = @intCast(accessors.items.len);
        try accessors.append(accessor);

        return accessor_idx;
    }

    // Write scale keyframe data
    fn writeScaleKeyframes(self: *GltfExporter, ai_channel: *const assimp.aiNodeAnim, buffer_views: *ArrayList(GltfBufferView), accessors: *ArrayList(GltfAccessor)) !u32 {
        const start_offset: u32 = @intCast(self.binary_data.items.len);

        // Write scale data
        for (0..ai_channel.mNumScalingKeys) |i| {
            const scale = ai_channel.mScalingKeys[i].mValue;
            const scale_data = [3]f32{ scale.x, scale.y, scale.z };
            try self.binary_data.writer().writeAll(std.mem.asBytes(&scale_data));
        }

        const byte_length: u32 = @intCast(self.binary_data.items.len - start_offset);

        // Create buffer view
        const buffer_view = GltfBufferView{
            .buffer = 0,
            .byteOffset = start_offset,
            .byteLength = byte_length,
        };

        const buffer_view_idx: u32 = @intCast(buffer_views.items.len);
        try buffer_views.append(buffer_view);

        // Create accessor
        const accessor = GltfAccessor{
            .bufferView = buffer_view_idx,
            .componentType = 5126, // FLOAT
            .count = ai_channel.mNumScalingKeys,
            .type = "VEC3",
        };

        const accessor_idx: u32 = @intCast(accessors.items.len);
        try accessors.append(accessor);

        return accessor_idx;
    }
};
