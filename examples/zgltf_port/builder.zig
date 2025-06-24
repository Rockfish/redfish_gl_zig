const std = @import("std");
const gl = @import("zopengl").bindings;
const panic = @import("std").debug.panic;
const core = @import("core");
const math = @import("math");
const utils = @import("utils.zig");

const Gltf = @import("zgltf/src/main.zig");
const Model = @import("model.zig").Model;
const Mesh = @import("mesh.zig").Mesh;
const MeshPrimitive = @import("mesh.zig").MeshPrimitive;
const PrimitiveVertex = @import("mesh.zig").PrimitiveVertex;
const Animator = @import("animator.zig").Animator;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;
const Path = std.fs.path;

const Transform = core.Transform;
const String = core.String;

const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;

pub const GltfBuilder = struct {
    name: []const u8,
    meshes: *ArrayList(*Mesh),
    bone_count: u32,
    filepath: [:0]const u8,
    directory: []const u8,
    gamma_correction: bool,
    flip_v: bool,
    flip_h: bool,
    load_textures: bool,
    mesh_count: i32,
    allocator: Allocator,

    const Self = @This();

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.name);
        self.allocator.free(self.filepath);
        self.allocator.free(self.directory);
        self.allocator.destroy(self);
    }

    pub fn init(allocator: Allocator, name: []const u8, path: []const u8) !*Self {
        const meshes = try allocator.create(ArrayList(*Mesh));
        meshes.* = ArrayList(*Mesh).init(allocator);

        const builder = try allocator.create(Self);
        builder.* = GltfBuilder{
            .name = try allocator.dupe(u8, name),
            .filepath = try allocator.dupeZ(u8, path),
            .directory = try allocator.dupe(u8, Path.dirname(path) orelse ""),
            .meshes = meshes,
            .mesh_count = 0,
            .bone_count = 0,
            .gamma_correction = false,
            .flip_v = false,
            .flip_h = false,
            .load_textures = true,
            .allocator = allocator,
        };

        return builder;
    }

    pub fn flipv(self: *Self) *Self {
        self.*.flip_v = true;
        return self;
    }

    pub fn skipModelTextures(self: *Self) void {
        self.load_textures = false;
    }

    // TODO: the transform of the skinned mesh node MUST be ignored

    pub fn build(self: *Self) !*Model {

        // TODO: check file extension for glb or gltf

        const file_contents = std.fs.cwd().readFileAllocOptions(
            self.allocator,
            self.filepath,
            4_512_000,
            null,
            4,
            null,
        ) catch |err| std.debug.panic("error: {any}\n", .{err});

        defer self.allocator.free(file_contents);

        var gltf = Gltf.init(self.allocator);
        //defer gltf.deinit();

        try gltf.parse(file_contents);

        try self.loadBufferData(&gltf);
        try self.loadMeshes(&gltf);

        const animator = try Animator.init(self.allocator);

        const model = try self.allocator.create(Model);
        model.* = Model{
            .allocator = self.allocator,
            .scene = 0,
            .name = try self.allocator.dupe(u8, self.name),
            .meshes = self.meshes,
            .animator = animator,
            .gltf = gltf,
        };

        return model;
    }

    // Uri patterns found in the Khonos examples.
    // data:application/gltf-buffer;base64
    // data:application/octet-stream;base64
    // data:image/jpeg;base64
    // data:image/png;base64

    // TODO: Note this could be done on demand when required by a mesh
    // because its is possible that are multiple scences with different meshes
    // and not all meshes will be loaded depending on the selected scene.
    pub fn loadBufferData(self: *Self, gltf: *Gltf) !void {
        const alloc = gltf.arena.allocator();
        for (gltf.data.buffers.items, 0..) |buffer, i| {
            if (buffer.uri) |uri| {
                if (std.mem.eql(u8, "data:", uri[0..5])) {
                    const comma = utils.strchr(uri, ',');
                    if (comma) |idx| {
                        // "uri" : "data:application/octet-stream;base64,
                        std.debug.print("uri: {s}  first 10 of data: {s}\n", .{uri[0..idx+1], uri[idx+1..idx+1+10]});
                        const decoder = std.base64.standard_no_pad.Decoder;
                        const decoded_length = decoder.calcSizeForSlice(uri[idx+1..uri.len]) catch |err| {
                            std.debug.panic("decoder calcSizeForSlice error: {any}\n", .{ err });
                        };
                        std.debug.print("calcSizeForSlice for decode: {d}\n", .{decoded_length});
                        const decoded_buffer: []align(4) u8 = try alloc.allocWithOptions(u8, decoded_length, 4, null);
                        decoder.decode(decoded_buffer, uri[idx..uri.len]) catch |err| {
                            std.debug.panic("decoder decode error: {any}\n", .{ err });
                        };

                        try gltf.buffer_data.append(decoded_buffer);
                    }
                } else if (!std.mem.eql(u8, "://", uri)) {
                    const directory = Path.dirname(self.filepath);
                    const path = try std.fs.path.join(self.allocator, &[_][]const u8{ directory.?, uri });
                    defer self.allocator.free(path);

                    std.debug.print("position buffer file path: {s}\n", .{path});

                    const glb_buf = std.fs.cwd().readFileAllocOptions(
                        alloc,
                        path,
                        4_512_000,
                        null,
                        4,
                        null,
                    ) catch |err| {
                        std.debug.panic("readFile error: {any}  path: {s}\n", .{err, path});
                    };

                    std.debug.print("buffer: {d} length: {d}\n", .{ i, glb_buf.len });
                    try gltf.buffer_data.append(glb_buf);
                } else {
                    std.debug.panic("Unknown buffer type.", .{});
                }
            }
        }
    }

    pub fn loadMeshes(self: *Self, gltf: *Gltf) !void {
        for (gltf.data.meshes.items) |gltf_mesh| {
            const mesh = try Mesh.init(self.allocator, gltf, self.directory, gltf_mesh);
            try self.meshes.append(mesh);
        }
    }
};

// fn getBufferSlice(comptime T: type, gltf: *Gltf, accessor_id: usize) []T {
//     const accessor = gltf.data.accessors.items[accessor_id];
//     if (@sizeOf(T) != accessor.stride) {
//         std.debug.panic("sizeOf(T) : {d} does not equal accessor.stride: {d}", .{ @sizeOf(T), accessor.stride });
//     }
//     const buffer_view = gltf.data.buffer_views.items[accessor.buffer_view.?];
//     const glb_buf = gltf.buffer_data.items[buffer_view.buffer];
//     const start = accessor.byte_offset + buffer_view.byte_offset;
//     const end = start + buffer_view.byte_length;
//     const slice = glb_buf[start..end];
//     const data = @as([*]T, @ptrCast(@alignCast(@constCast(slice))))[0..accessor.count];
//     return data;
// }

