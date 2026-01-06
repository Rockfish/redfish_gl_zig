const std = @import("std");
const math = @import("math");
const containers = @import("containers");
const gltf_types = @import("gltf/gltf.zig");
const parser = @import("gltf/parser.zig");
const texture = @import("texture.zig");
const utils = @import("utils/main.zig");
const Model = @import("model.zig").Model;
const Mesh = @import("mesh.zig").Mesh;
const Animator = @import("animator.zig").Animator;

const Vec3 = math.Vec3;

// Normal generation options for asset loading
pub const NormalGenerationMode = enum {
    skip, // Don't generate normals, use shader fallback
    simple, // Generate simple upward-facing normals
    accurate, // Calculate normals from triangle geometry
};

const Allocator = std.mem.Allocator;
const ManagedArrayList = containers.ManagedArrayList;
const ArenaAllocator = std.heap.ArenaAllocator;
const Path = std.fs.path;

const GLTF = gltf_types.GLTF;

// Custom texture assignment for meshes without material definitions
const CustomTexture = struct {
    mesh_name: []const u8,
    uniform_name: [:0]const u8,
    texture_path: []const u8,
    config: texture.TextureConfig,
    texture: ?*texture.Texture = null, // Loaded texture cache
};

// GLB Format Constants
const GLB_MAGIC: u32 = 0x46546C67; // "glTF" in little-endian
const GLB_VERSION: u32 = 2;
const GLB_JSON_CHUNK_TYPE: u32 = 0x4E4F534A; // "JSON"
const GLB_BIN_CHUNK_TYPE: u32 = 0x004E4942; // "BIN\0"

// GLB Structures
const GlbHeader = struct {
    magic: u32,
    version: u32,
    length: u32,
};

const GlbChunkHeader = struct {
    length: u32,
    chunk_type: u32,
};

// GLB Errors
const GlbError = error{
    InvalidMagic,
    UnsupportedVersion,
    InvalidChunkType,
    TruncatedFile,
    MissingJsonChunk,
};

pub const GltfAsset = struct {
    arena: *ArenaAllocator,

    // Pure GLTF specification data
    gltf: GLTF,

    // Runtime support data
    buffer_data: ManagedArrayList([]align(4) const u8),
    loaded_textures: std.AutoHashMap(u32, *texture.Texture),
    generated_normals: std.AutoHashMap(u64, []Vec3), // Key: mesh_index << 32 | primitive_index
    custom_textures: ManagedArrayList(CustomTexture), // Manual texture assignments
    directory: []const u8,
    name: []const u8,
    filepath: [:0]const u8,

    // Configuration
    gamma_correction: bool,
    flip_v: bool,
    flip_h: bool,
    load_textures: bool,
    normal_generation_mode: NormalGenerationMode,

    const Self = @This();

    pub fn init(allocator: Allocator, name: []const u8, path: []const u8) !*Self {

        // will be owned by the model
        const arena = try allocator.create(ArenaAllocator);
        arena.* = ArenaAllocator.init(allocator);

        const local_alloc = arena.allocator();

        const asset: *GltfAsset = try local_alloc.create(Self);
        asset.* = GltfAsset{
            .arena = arena, // will be owned by the model
            .gltf = undefined, // Will be set during load
            .buffer_data = ManagedArrayList([]align(4) const u8).init(local_alloc),
            .loaded_textures = std.AutoHashMap(u32, *texture.Texture).init(local_alloc),
            .generated_normals = std.AutoHashMap(u64, []Vec3).init(local_alloc),
            .custom_textures = ManagedArrayList(CustomTexture).init(local_alloc),
            .directory = try local_alloc.dupe(u8, Path.dirname(path) orelse ""),
            .name = try local_alloc.dupe(u8, name),
            .filepath = try local_alloc.dupeZ(u8, path),
            .gamma_correction = false,
            .flip_v = false,
            .flip_h = false,
            .load_textures = true,
            .normal_generation_mode = .skip, // Default to skip generation
        };

        return asset;
    }

    pub fn deinit(self: *Self) void {
        // Free loaded textures
        var texture_iterator = self.loaded_textures.valueIterator();
        while (texture_iterator.next()) |tex| {
            tex.*.deleteGlTexture();
        }

        // Free custom textures
        for (self.custom_textures.list.items) |*custom_tex| {
            if (custom_tex.texture) |tex| {
                tex.deleteGlTexture();
            }
        }
    }

    pub fn flipv(self: *Self) *Self {
        self.flip_v = true;
        return self;
    }

    pub fn skipModelTextures(self: *Self) void {
        self.load_textures = false;
    }

    pub fn setNormalGenerationMode(self: *Self, mode: NormalGenerationMode) void {
        self.normal_generation_mode = mode;
    }

    // Add custom texture assignment for models without material definitions
    pub fn addTexture(self: *Self, mesh_name: []const u8, uniform_name: []const u8, texture_path: []const u8, config: texture.TextureConfig) !void {
        const allocator = self.arena.allocator();

        const custom_texture = CustomTexture{
            .mesh_name = try allocator.dupe(u8, mesh_name),
            .uniform_name = try allocator.dupeZ(u8, uniform_name),
            .texture_path = try allocator.dupe(u8, texture_path),
            .config = config,
            .texture = null, // Will be loaded on demand
        };

        try self.custom_textures.append(custom_texture);
    }

    // Get custom textures for a specific mesh
    pub fn getCustomTextures(self: *Self, mesh_name: []const u8) []CustomTexture {
        const allocator = self.arena.allocator();
        var matching_textures = ManagedArrayList(CustomTexture).init(allocator);

        for (self.custom_textures.list.items) |*custom_tex| {
            if (std.mem.eql(u8, custom_tex.mesh_name, mesh_name)) {
                matching_textures.append(custom_tex.*) catch continue;
            }
        }

        return matching_textures.toOwnedSlice() catch &[_]CustomTexture{};
    }

    // Load custom texture on demand with caching
    pub fn loadCustomTexture(self: *Self, custom_tex: *CustomTexture) !*texture.Texture {
        if (custom_tex.texture) |tex| {
            return tex; // Already loaded
        }

        // Load texture using custom configuration
        const tex = try self.loadCustomTextureFromFile(custom_tex.texture_path, custom_tex.config);
        custom_tex.texture = tex;
        return tex;
    }

    // Load custom texture from file with configuration
    fn loadCustomTextureFromFile(self: *Self, texture_path: []const u8, config: texture.TextureConfig) !*texture.Texture {
        const allocator = self.arena.allocator();

        // Create full path
        const full_path = try std.fs.path.joinZ(allocator, &[_][]const u8{ self.directory, texture_path });
        defer allocator.free(full_path);

        // Load texture manually (similar to ASSIMP system)
        const tex = try texture.Texture.initFromFile(
            allocator,
            full_path,
            config,
        );

        return tex;
    }

    // Get pre-generated normals for a specific mesh primitive
    pub fn getGeneratedNormals(self: *Self, mesh_index: u32, primitive_index: u32) ?[]Vec3 {
        const key = (@as(u64, mesh_index) << 32) | primitive_index;
        return self.generated_normals.get(key);
    }

    // Generate missing normals for all mesh primitives based on configuration
    fn generateMissingNormals(self: *Self) !void {
        // Skip generation if mode is set to skip
        if (self.normal_generation_mode == .skip) {
            return;
        }

        if (self.gltf.meshes) |gltf_meshes| {
            for (gltf_meshes, 0..) |gltf_mesh, mesh_index| {
                for (gltf_mesh.primitives, 0..) |primitive, primitive_index| {
                    // Skip if this primitive already has normals
                    if (primitive.attributes.normal != null) {
                        continue;
                    }

                    // Get vertex count from position accessor
                    const position_accessor_id = primitive.attributes.position orelse {
                        std.debug.print("Primitive {d}.{d} has no position data, skipping normal generation\n", .{ mesh_index, primitive_index });
                        continue;
                    };

                    const position_accessor = self.gltf.accessors.?[position_accessor_id];
                    const vertex_count: u32 = @intCast(position_accessor.count);

                    // Generate normals based on mode
                    const normals = switch (self.normal_generation_mode) {
                        .skip => unreachable, // Already handled above
                        .simple => generateSimpleNormals(self, vertex_count),
                        .accurate => generateAccurateNormals(self, primitive, vertex_count),
                    };

                    // Store generated normals in the map
                    const key = (@as(u64, @intCast(mesh_index)) << 32) | @as(u64, @intCast(primitive_index));
                    try self.generated_normals.put(key, normals);

                    std.debug.print("Generated {s} normals for mesh {d} primitive {d} ({d} vertices)\n", .{ @tagName(self.normal_generation_mode), mesh_index, primitive_index, vertex_count });
                }
            }
        }
    }

    pub fn load(self: *Self) !void {
        const file_contents = std.fs.cwd().readFileAllocOptions(
            self.arena.allocator(),
            self.filepath,
            500_000_000,
            null,
            .@"4",
            null,
        ) catch |err| std.debug.panic("Error reading file. error: '{any}'  file: '{s}'\n", .{ err, self.filepath });

        if (isGlbFile(self.filepath)) {
            // GLB format: parse binary format and extract JSON + binary chunks
            const glb_data = try parseGlbFile(self.arena.allocator(), file_contents);
            self.gltf = try parser.parseGltfJson(self.arena.allocator(), glb_data.json_data);

            // Pre-populate buffer_data with GLB binary chunk if present
            if (glb_data.binary_data) |bin_data| {
                // Create aligned copy of binary data
                const aligned_data = try self.arena.allocator().alignedAlloc(u8, .@"4", bin_data.len);
                @memcpy(aligned_data, bin_data);
                try self.buffer_data.append(aligned_data);
            }
        } else {
            // GLTF format: parse JSON directly
            self.gltf = try parser.parseGltfJson(self.arena.allocator(), file_contents);

            // Load external buffer data from URIs
            try self.loadBufferData();
        }
    }

    pub fn buildModel(self: *Self) !*Model {
        const allocator = self.arena.allocator();

        // Generate normals for missing ones based on configuration
        try self.generateMissingNormals();

        // Create meshes
        const meshes = try allocator.create(ManagedArrayList(*Mesh));
        meshes.* = ManagedArrayList(*Mesh).init(allocator);

        if (self.gltf.meshes) |gltf_meshes| {
            for (gltf_meshes, 0..) |gltf_mesh, mesh_index| {
                const mesh = try Mesh.init(self.arena, self, gltf_mesh, mesh_index);
                try meshes.append(mesh);
            }
        }

        // Find the skin used by a mesh with skinning data
        var skin_index: ?u32 = null;
        if (self.gltf.skins) |skins| {
            if (skins.len > 0) {
                // Find which skin is actually used by checking scene nodes
                if (self.gltf.nodes) |nodes| {
                    for (nodes, 0..) |node, node_idx| {
                        if (node.mesh != null and node.skin != null) {
                            skin_index = node.skin.?;
                            std.debug.print("Found {d} skins, using skin {d} with {d} joints (from node {d})\n", .{ skins.len, skin_index.?, skins[skin_index.?].joints.len, node_idx });
                            break;
                        }
                    }
                }

                // Fallback to first skin if no node with both mesh and skin found
                if (skin_index == null) {
                    skin_index = 0;
                    std.debug.print("Found {d} skins, using fallback skin 0 with {d} joints\n", .{ skins.len, skins[0].joints.len });
                }
            }
        } else {
            std.debug.print("No skins found in model\n", .{});
        }

        // Create animator
        const animator = try Animator.init(self.arena, self, skin_index);

        // Create model
        const model = try Model.init(
            self.arena, // model now owns arena
            self.name,
            meshes,
            animator,
            self,
        );

        return model;
    }

    pub fn getTexture(self: *Self, texture_index: u32) !*texture.Texture {
        if (self.loaded_textures.get(texture_index)) |tex| {
            return tex;
        }

        // Load texture on demand
        const tex = try texture.Texture.initFromGltf(
            self.arena,
            self,
            self.directory,
            texture_index,
        );

        try self.loaded_textures.put(texture_index, tex);
        return tex;
    }

    // Load buffer data from URIs or embedded data
    fn loadBufferData(self: *Self) !void {
        const alloc = self.arena.allocator();

        if (self.gltf.buffers) |buffers| {
            for (buffers, 0..) |buffer, buffer_index| {
                // For GLB files, buffer index 0 is typically the embedded binary chunk
                if (isGlbFile(self.filepath) and buffer_index == 0 and buffer.uri == null) {
                    // GLB embedded buffer - should already be loaded in buffer_data
                    // Verify we have the binary data
                    if (self.buffer_data.list.items.len == 0) {
                        std.debug.panic("GLB file missing binary chunk for buffer {d}\n", .{buffer_index});
                    }
                    continue; // Skip loading - already have the data
                }

                if (buffer.uri) |uri| {
                    if (std.mem.eql(u8, "data:", uri[0..5])) {
                        // Handle base64 data URIs
                        const comma = utils.strchr(uri, ',');
                        if (comma) |idx| {
                            const decoder = std.base64.standard.Decoder;
                            const decoded_length = decoder.calcSizeForSlice(uri[idx + 1 .. uri.len]) catch |err| {
                                std.debug.panic("decoder calcSizeForSlice error: {any}\n", .{err});
                            };
                            const decoded_buffer: []align(4) u8 = try alloc.allocWithOptions(u8, decoded_length, .@"4", null);
                            decoder.decode(decoded_buffer, uri[idx + 1 .. uri.len]) catch |err| {
                                std.debug.panic("decoder decode error: {any}\n", .{err});
                            };
                            try self.buffer_data.append(decoded_buffer);
                        }
                    } else {
                        // Handle external file URIs
                        const path = try std.fs.path.join(alloc, &[_][]const u8{ self.directory, uri });
                        defer alloc.free(path);

                        const buffer_file = std.fs.cwd().readFileAllocOptions(
                            alloc,
                            path,
                            4_512_000,
                            null,
                            .@"4",
                            null,
                        ) catch |err| {
                            std.debug.panic("readFile error: {any} path: {s}\n", .{ err, path });
                        };
                        try self.buffer_data.append(buffer_file);
                    }
                } else {
                    // Buffer with no URI - should only happen for GLB buffer 0
                    if (!isGlbFile(self.filepath) or buffer_index != 0) {
                        std.debug.panic("Buffer {d} has no URI and is not GLB embedded buffer\n", .{buffer_index});
                    }
                }
            }
        }
    }
};

// GLB Helper Functions

fn isGlbFile(filepath: []const u8) bool {
    return std.mem.endsWith(u8, filepath, ".glb");
}

const GlbData = struct {
    json_data: []const u8,
    binary_data: ?[]const u8,
};

fn parseGlbFile(allocator: Allocator, file_data: []const u8) !GlbData {
    _ = allocator; // Currently unused, may need for future validation

    // Validate minimum file size (12 bytes for GLB header)
    if (file_data.len < @sizeOf(GlbHeader)) {
        return GlbError.TruncatedFile;
    }

    // Read GLB header
    const header = std.mem.bytesToValue(GlbHeader, file_data[0..@sizeOf(GlbHeader)]);

    // Validate magic number
    if (header.magic != GLB_MAGIC) {
        return GlbError.InvalidMagic;
    }

    // Validate version
    if (header.version != GLB_VERSION) {
        return GlbError.UnsupportedVersion;
    }

    // Validate file length
    if (header.length != file_data.len) {
        return GlbError.TruncatedFile;
    }

    var offset: usize = @sizeOf(GlbHeader);
    var json_data: ?[]const u8 = null;
    var binary_data: ?[]const u8 = null;

    // Parse chunks
    while (offset < file_data.len) {
        // Check if we have enough data for chunk header
        if (offset + @sizeOf(GlbChunkHeader) > file_data.len) {
            return GlbError.TruncatedFile;
        }

        // Read chunk header
        const chunk_header = std.mem.bytesToValue(GlbChunkHeader, file_data[offset .. offset + @sizeOf(GlbChunkHeader)]);
        offset += @sizeOf(GlbChunkHeader);

        // Check if we have enough data for chunk content
        if (offset + chunk_header.length > file_data.len) {
            return GlbError.TruncatedFile;
        }

        // Extract chunk data
        const chunk_data = file_data[offset .. offset + chunk_header.length];

        // Process chunk based on type
        switch (chunk_header.chunk_type) {
            GLB_JSON_CHUNK_TYPE => {
                json_data = chunk_data;
            },
            GLB_BIN_CHUNK_TYPE => {
                binary_data = chunk_data;
            },
            else => {
                // Unknown chunk type - skip it (per glTF spec)
            },
        }

        // Move to next chunk (handle 4-byte alignment padding)
        offset += chunk_header.length;
        // Align to 4-byte boundary
        offset = (offset + 3) & ~@as(usize, 3);
    }

    // Ensure we found JSON chunk
    if (json_data == null) {
        return GlbError.MissingJsonChunk;
    }

    return GlbData{
        .json_data = json_data.?,
        .binary_data = binary_data,
    };
}

// Helper functions for accessor component and type sizes
fn getComponentSize(component_type: gltf_types.ComponentType) usize {
    return switch (component_type) {
        .byte, .unsigned_byte => 1,
        .short, .unsigned_short => 2,
        .unsigned_int, .float => 4,
    };
}

fn getTypeSize(accessor_type: gltf_types.AccessorType) usize {
    return switch (accessor_type) {
        .scalar => 1,
        .vec2 => 2,
        .vec3 => 3,
        .vec4 => 4,
        .mat2 => 4,
        .mat3 => 9,
        .mat4 => 16,
    };
}

// Generate simple upward-facing normals for models that don't have them
pub fn generateSimpleNormals(gltf_asset: *GltfAsset, vertex_count: u32) []Vec3 {
    const allocator = gltf_asset.arena.allocator();

    const normals = allocator.alloc(Vec3, vertex_count) catch |err| {
        std.debug.panic("Failed to allocate normals: {any}", .{err});
    };

    // Generate simple upward normals (0, 1, 0) for all vertices
    for (normals) |*normal| {
        normal.* = Vec3{ .x = 0.0, .y = 1.0, .z = 0.0 };
    }

    return normals;
}

// Generate accurate normals calculated from triangle geometry
pub fn generateAccurateNormals(gltf_asset: *GltfAsset, primitive: gltf_types.MeshPrimitive, vertex_count: u32) []Vec3 {
    const allocator = gltf_asset.arena.allocator();

    // Get position data
    const position_accessor_id = primitive.attributes.position orelse {
        std.debug.panic("Cannot generate normals without positions", .{});
    };

    const position_accessor = gltf_asset.gltf.accessors.?[position_accessor_id];
    const position_buffer_view = gltf_asset.gltf.buffer_views.?[position_accessor.buffer_view.?];
    const position_buffer_data = gltf_asset.buffer_data.list.items[position_buffer_view.buffer];

    const position_start = position_accessor.byte_offset + position_buffer_view.byte_offset;
    const position_data_size = getComponentSize(position_accessor.component_type) * getTypeSize(position_accessor.type_) * position_accessor.count;
    const position_data = position_buffer_data[position_start .. position_start + position_data_size];
    const positions = @as([*]Vec3, @ptrCast(@alignCast(@constCast(position_data))))[0..vertex_count];

    // Initialize normals to zero
    const normals = allocator.alloc(Vec3, vertex_count) catch |err| {
        std.debug.panic("Failed to allocate normals: {any}", .{err});
    };
    for (normals) |*normal| {
        normal.* = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 };
    }

    // Calculate normals from triangle faces
    if (primitive.indices) |indices_accessor_id| {
        // Indexed geometry - calculate normals from triangles
        const indices_accessor = gltf_asset.gltf.accessors.?[indices_accessor_id];
        const indices_buffer_view = gltf_asset.gltf.buffer_views.?[indices_accessor.buffer_view.?];
        const indices_buffer_data = gltf_asset.buffer_data.list.items[indices_buffer_view.buffer];

        const indices_start = indices_accessor.byte_offset + indices_buffer_view.byte_offset;
        const indices_data_size = getComponentSize(indices_accessor.component_type) * getTypeSize(indices_accessor.type_) * indices_accessor.count;
        const indices_data = indices_buffer_data[indices_start .. indices_start + indices_data_size];

        // Handle different index types
        switch (indices_accessor.component_type) {
            .unsigned_short => {
                const indices = @as([*]u16, @ptrCast(@alignCast(@constCast(indices_data))))[0..indices_accessor.count];
                var i: usize = 0;
                while (i + 2 < indices.len) : (i += 3) {
                    const idx0 = indices[i];
                    const idx1 = indices[i + 1];
                    const idx2 = indices[i + 2];

                    if (idx0 < vertex_count and idx1 < vertex_count and idx2 < vertex_count) {
                        const v0 = positions[idx0];
                        const v1 = positions[idx1];
                        const v2 = positions[idx2];

                        // Calculate face normal using cross product
                        const edge1 = v1.sub(&v0);
                        const edge2 = v2.sub(&v0);
                        const face_normal = edge1.crossNormalized(&edge2);

                        // Add to vertex normals
                        normals[idx0] = normals[idx0].add(&face_normal);
                        normals[idx1] = normals[idx1].add(&face_normal);
                        normals[idx2] = normals[idx2].add(&face_normal);
                    }
                }
            },
            .unsigned_int => {
                const indices = @as([*]u32, @ptrCast(@alignCast(@constCast(indices_data))))[0..indices_accessor.count];
                var i: usize = 0;
                while (i + 2 < indices.len) : (i += 3) {
                    const idx0 = indices[i];
                    const idx1 = indices[i + 1];
                    const idx2 = indices[i + 2];

                    if (idx0 < vertex_count and idx1 < vertex_count and idx2 < vertex_count) {
                        const v0 = positions[idx0];
                        const v1 = positions[idx1];
                        const v2 = positions[idx2];

                        // Calculate face normal using cross product
                        const edge1 = v1.sub(&v0);
                        const edge2 = v2.sub(&v0);
                        const face_normal = edge1.crossNormalized(&edge2);

                        // Add to vertex normals
                        normals[idx0] = normals[idx0].add(&face_normal);
                        normals[idx1] = normals[idx1].add(&face_normal);
                        normals[idx2] = normals[idx2].add(&face_normal);
                    }
                }
            },
            else => {
                std.debug.print("Unsupported index type for normal generation: {s}\n", .{@tagName(indices_accessor.component_type)});
                // Fallback to upward normals
                for (normals) |*normal| {
                    normal.* = Vec3{ .x = 0.0, .y = 1.0, .z = 0.0 };
                }
            },
        }
    } else {
        // Non-indexed geometry - assume triangles in order
        var i: usize = 0;
        while (i + 2 < vertex_count) : (i += 3) {
            const v0 = positions[i];
            const v1 = positions[i + 1];
            const v2 = positions[i + 2];

            // Calculate face normal using cross product
            const edge1 = v1.sub(&v0);
            const edge2 = v2.sub(&v0);
            const face_normal = edge1.crossNormalized(&edge2);

            // Set vertex normals to face normal
            normals[i] = face_normal;
            normals[i + 1] = face_normal;
            normals[i + 2] = face_normal;
        }
    }

    // Normalize all accumulated normals
    for (normals) |*normal| {
        if (normal.length() > 0.0) {
            normal.* = normal.toNormalized();
        } else {
            // Fallback to upward normal if no accumulated normal
            normal.* = Vec3{ .x = 0.0, .y = 1.0, .z = 0.0 };
        }
    }

    return normals;
}
