const std = @import("std");
const containers = @import("containers");

const asset_loader = @import("asset_loader.zig");
const texture_mod = @import("texture.zig");
const shapes = @import("shapes/root.zig");
const shader_mod = @import("shader.zig");
const model_mod = @import("model.zig");

const Io = std.Io;
const Allocator = std.mem.Allocator;
const ManagedArrayList = containers.ManagedArrayList;

const GltfAsset = asset_loader.GltfAsset;
const Texture = texture_mod.Texture;
const TextureConfig = texture_mod.TextureConfig;
const Shader = shader_mod.Shader;
const Model = model_mod.Model;
const Shape = shapes.Shape;

pub const ResourceManager = struct {
    io: Io,
    allocator: Allocator,

    // Typed resource storage
    shaders: ManagedArrayList(*Shader),
    textures: ManagedArrayList(*Texture),
    models: ManagedArrayList(*Model),
    obj_shapes: ManagedArrayList(*Shape),

    const Self = @This();

    pub fn init(io: Io, allocator: Allocator) !*Self {
        const rm = try allocator.create(Self);
        rm.* = .{
            .io = io,
            .allocator = allocator,
            .shaders = ManagedArrayList(*Shader).init(allocator),
            .textures = ManagedArrayList(*Texture).init(allocator),
            .models = ManagedArrayList(*Model).init(allocator),
            .obj_shapes = ManagedArrayList(*Shape).init(allocator),
        };
        return rm;
    }

    // --- Shader Factory ---

    pub fn createShader(
        self: *Self,
        vert_path: []const u8,
        frag_path: []const u8,
    ) !*Shader {
        const shader = try Shader.init(self.io, self.allocator, vert_path, frag_path);
        try self.shaders.append(shader);
        return shader;
    }

    pub fn createShaderWithGeom(
        self: *Self,
        vert_path: []const u8,
        frag_path: []const u8,
        geom_path: ?[]const u8,
    ) !*Shader {
        const shader = try Shader.initWithGeom(self.io, self.allocator, vert_path, frag_path, geom_path);
        try self.shaders.append(shader);
        return shader;
    }

    // --- Texture Factory ---

    pub fn createTexture(
        self: *Self,
        path: [:0]const u8,
        config: TextureConfig,
    ) !*Texture {
        const tex = try Texture.initFromFile(self.io, self.allocator, path, config);
        try self.textures.append(tex);
        return tex;
    }

    // --- Model Factory ---

    /// Load a glTF asset for manual configuration before building.
    /// Call buildModel() after configuring the asset.
    pub fn loadGltfAsset(
        self: *Self,
        name: []const u8,
        path: []const u8,
    ) !*GltfAsset {
        return try GltfAsset.init(self.allocator, name, path);
    }

    /// Build a model from a pre-configured GltfAsset and track it.
    pub fn buildModel(self: *Self, gltf_asset: *GltfAsset) !*Model {
        const model = try gltf_asset.buildModel();
        try self.models.append(model);
        return model;
    }

    /// Load a glTF model in one step (no pre-build configuration).
    pub fn loadModel(
        self: *Self,
        name: []const u8,
        path: []const u8,
    ) !*Model {
        var gltf_asset = try GltfAsset.init(self.io, self.allocator, name, path);
        const model = try gltf_asset.buildModel();
        try self.models.append(model);
        return model;
    }

    // --- Shape Factory ---

    pub fn loadOBJ(self: *Self, filepath: []const u8) !*Shape {
        const shape = try shapes.loadOBJ(self.io, self.allocator, filepath);
        try self.obj_shapes.append(shape);
        return shape;
    }

    pub fn createCube(self: *Self, config: shapes.CubeConfig) !*Shape {
        const shape = try shapes.createCube(self.allocator, config);
        try self.obj_shapes.append(shape);
        return shape;
    }

    pub fn createSphere(self: *Self, radius: f32, poly_count_x: u32, poly_count_y: u32) !*Shape {
        const shape = try shapes.createSphere(self.allocator, radius, poly_count_x, poly_count_y);
        try self.obj_shapes.append(shape);
        return shape;
    }

    pub fn createCylinder(self: *Self, radius: f32, height: f32, sides: u32) !*Shape {
        const shape = try shapes.createCylinder(self.allocator, radius, height, sides);
        try self.obj_shapes.append(shape);
        return shape;
    }

    // --- Cleanup ---

    /// Delete all tracked GL resources in the correct order.
    /// Models first (they reference shaders), then shapes, textures, shaders.
    pub fn deleteAll(self: *Self) void {
        // Models own their arenas and internal textures
        for (self.models.items()) |model| {
            model.deinit();
        }

        // Standalone shapes
        for (self.obj_shapes.items()) |shape| {
            shape.deinit();
        }

        // Standalone textures (not owned by models)
        for (self.textures.items()) |tex| {
            tex.deleteGlObjects();
        }

        // Shaders last
        for (self.shaders.items()) |shader| {
            shader.deinit();
        }

        // Clear the lists
        self.models.list.clearRetainingCapacity();
        self.textures.list.clearRetainingCapacity();
        self.obj_shapes.list.clearRetainingCapacity();
        self.shaders.list.clearRetainingCapacity();
    }

    pub fn deinit(self: *Self) void {
        self.deleteAll();
        self.models.deinit();
        self.textures.deinit();
        self.obj_shapes.deinit();
        self.shaders.deinit();
        self.allocator.destroy(self);
    }
};
