const std = @import("std");
const containers = @import("containers");

const Context = @import("context.zig").Context;
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
    context: Context,

    // Typed resource storage
    shaders: ManagedArrayList(*Shader),
    textures: ManagedArrayList(*Texture),
    models: ManagedArrayList(*Model),
    obj_shapes: ManagedArrayList(*Shape),

    const Self = @This();

    pub fn init(context: Context) !*Self {
        const rm = try context.alloc.create(Self);
        rm.* = .{
            .context = context,
            .shaders = ManagedArrayList(*Shader).init(context.alloc),
            .textures = ManagedArrayList(*Texture).init(context.alloc),
            .models = ManagedArrayList(*Model).init(context.alloc),
            .obj_shapes = ManagedArrayList(*Shape).init(context.alloc),
        };
        return rm;
    }

    // --- Shader Factory ---

    pub fn createShader(
        self: *Self,
        vert_path: []const u8,
        frag_path: []const u8,
    ) !*Shader {
        const shader = try Shader.init(self.context.io, self.context.alloc, vert_path, frag_path);
        try self.shaders.append(shader);
        return shader;
    }

    pub fn createShaderWithGeom(
        self: *Self,
        vert_path: []const u8,
        frag_path: []const u8,
        geom_path: ?[]const u8,
    ) !*Shader {
        const shader = try Shader.initWithGeom(self.context.io, self.context.alloc, vert_path, frag_path, geom_path);
        try self.shaders.append(shader);
        return shader;
    }

    // --- Texture Factory ---

    pub fn createTexture(
        self: *Self,
        path: [:0]const u8,
        config: TextureConfig,
    ) !*Texture {
        const tex = try Texture.initFromFile(self.context, path, config);
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
        return try GltfAsset.init(self.context.io, self.context.alloc, name, path);
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
        var gltf_asset = try GltfAsset.init(self.context, name, path);
        const model = try gltf_asset.buildModel();
        try self.models.append(model);
        return model;
    }

    // --- Shape Factory ---

    pub fn loadOBJ(self: *Self, filepath: []const u8) !*Shape {
        const shape = try shapes.loadOBJ(self.context.io, self.context.alloc, filepath);
        try self.obj_shapes.append(shape);
        return shape;
    }

    pub fn createCube(self: *Self, config: shapes.CubeConfig) !*Shape {
        const shape = try shapes.createCube(self.context.alloc, config);
        try self.obj_shapes.append(shape);
        return shape;
    }

    pub fn createSphere(self: *Self, radius: f32, poly_count_x: u32, poly_count_y: u32) !*Shape {
        const shape = try shapes.createSphere(self.context.alloc, radius, poly_count_x, poly_count_y);
        try self.obj_shapes.append(shape);
        return shape;
    }

    pub fn createCylinder(self: *Self, radius: f32, height: f32, sides: u32) !*Shape {
        const shape = try shapes.createCylinder(self.context.alloc, radius, height, sides);
        try self.obj_shapes.append(shape);
        return shape;
    }

    /// Delete all tracked GL resources in the correct order.
    pub fn cleanUp(self: *Self) void {
        // Models own their arenas and internal textures
        for (self.models.items()) |model| {
            model.deleteGlObjects();
        }

        // Standalone shapes
        for (self.obj_shapes.items()) |shape| {
            shape.deleteGlObjects();
        }

        // Standalone textures (not owned by models)
        for (self.textures.items()) |tex| {
            tex.deleteGlObjects();
        }

        // Shaders last
        for (self.shaders.items()) |shader| {
            shader.deleteGlObjects();
        }
    }
};
