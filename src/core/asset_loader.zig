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

        // Parse GLTF
        self.gltf = try parser.parseGltfFile(self.arena.allocator(), file_contents);

        // Load buffer data
        try self.loadBufferData();
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
            for (buffers) |buffer| {
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
                }
            }
        }
    }
};
