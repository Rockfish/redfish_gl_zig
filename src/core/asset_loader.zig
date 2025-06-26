const std = @import("std");
const gltf_types = @import("gltf/gltf.zig");
const parser = @import("gltf/parser.zig");
const texture = @import("texture.zig");
const utils = @import("utils/main.zig");
const Model = @import("model.zig").Model;
const Mesh = @import("mesh.zig").Mesh;
const Animator = @import("animator.zig").Animator;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const ArenaAllocator = std.heap.ArenaAllocator;
const Path = std.fs.path;

const GLTF = gltf_types.GLTF;

// GLB Format Constants
const GLB_MAGIC: u32 = 0x46546C67; // "glTF" in little-endian
const GLB_VERSION: u32 = 2;
const GLB_JSON_CHUNK_TYPE: u32 = 0x4E4F534A; // "JSON" 
const GLB_BIN_CHUNK_TYPE: u32 = 0x004E4942;  // "BIN\0"

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
    buffer_data: ArrayList([]align(4) const u8),
    loaded_textures: std.AutoHashMap(u32, *texture.Texture),
    directory: []const u8,
    name: []const u8,
    filepath: [:0]const u8,

    // Configuration
    gamma_correction: bool,
    flip_v: bool,
    flip_h: bool,
    load_textures: bool,

    const Self = @This();

    pub fn init(allocator: Allocator, name: []const u8, path: []const u8) !*Self {
        const arena = try allocator.create(ArenaAllocator);
        arena.* = ArenaAllocator.init(allocator);

        const alloc = arena.allocator();
        const asset = try allocator.create(Self);

        asset.* = GltfAsset{
            .arena = arena,
            .gltf = undefined, // Will be set during load
            .buffer_data = ArrayList([]align(4) const u8).init(alloc),
            .loaded_textures = std.AutoHashMap(u32, *texture.Texture).init(alloc),
            .directory = try alloc.dupe(u8, Path.dirname(path) orelse ""),
            .name = try alloc.dupe(u8, name),
            .filepath = try alloc.dupeZ(u8, path),
            .gamma_correction = false,
            .flip_v = false,
            .flip_h = false,
            .load_textures = true,
        };

        return asset;
    }

    pub fn deinit(self: *Self) void {
        // Free loaded textures
        var texture_iterator = self.loaded_textures.valueIterator();
        while (texture_iterator.next()) |tex| {
            tex.*.deinit();
        }

        // Clean up arena and main allocator
        const parent_allocator = self.arena.child_allocator;
        self.arena.deinit();
        parent_allocator.destroy(self.arena);
        parent_allocator.destroy(self);
    }

    pub fn flipv(self: *Self) *Self {
        self.flip_v = true;
        return self;
    }

    pub fn skipModelTextures(self: *Self) void {
        self.load_textures = false;
    }

    pub fn load(self: *Self) !void {
        const file_contents = std.fs.cwd().readFileAllocOptions(
            self.arena.allocator(),
            self.filepath,
            4_512_000,
            null,
            4,
            null,
        ) catch |err| std.debug.panic("error reading file: {any}\n", .{err});

        if (isGlbFile(self.filepath)) {
            // GLB format: parse binary format and extract JSON + binary chunks
            const glb_data = try parseGlbFile(self.arena.allocator(), file_contents);
            self.gltf = try parser.parseGltfJson(self.arena.allocator(), glb_data.json_data);
            
            // Pre-populate buffer_data with GLB binary chunk if present
            if (glb_data.binary_data) |bin_data| {
                // Create aligned copy of binary data
                const aligned_data = try self.arena.allocator().alignedAlloc(u8, 4, bin_data.len);
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

    pub fn buildModel(self: *Self) Model {

        // Create meshes
        const meshes = try self.arena.allocator().create(ArrayList(*Mesh));
        meshes.* = ArrayList(*Mesh).init(self.arena.allocator());

        if (self.gltf.meshes) |gltf_meshes| {
            for (gltf_meshes) |gltf_mesh| {
                const mesh = try Mesh.init(self.arena.allocator(), self, gltf_mesh);
                try meshes.append(mesh);
            }
        }

        // Create animator
        const animator = try Animator.init(self.arena.allocator());

        // Create model
        const model = try Model.init(
            self.arena.allocator(),
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
        const tex = try texture.Texture.init(
            self.arena.allocator(),
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
                    if (self.buffer_data.items.len == 0) {
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
                            const decoded_buffer: []align(4) u8 = try alloc.allocWithOptions(u8, decoded_length, 4, null);
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
                            4,
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
        const chunk_header = std.mem.bytesToValue(GlbChunkHeader, file_data[offset..offset + @sizeOf(GlbChunkHeader)]);
        offset += @sizeOf(GlbChunkHeader);
        
        // Check if we have enough data for chunk content
        if (offset + chunk_header.length > file_data.len) {
            return GlbError.TruncatedFile;
        }
        
        // Extract chunk data
        const chunk_data = file_data[offset..offset + chunk_header.length];
        
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
