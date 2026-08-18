const std = @import("std");
const core = @import("core");
const math = @import("math");

const Context = core.Context;
const Scene = @import("scene.zig").Scene;
const SceneCamera = @import("scene_camera.zig").SceneCamera;
const FreeCamera = @import("scene/free_camera.zig").FreeCamera;
const scene_lights = @import("scene/lights.zig");
const Floor = @import("scene/floor.zig").Floor;

const Vec3 = math.Vec3;
const vec3 = math.vec3;
const Mat4 = math.Mat4;

const Allocator = std.mem.Allocator;
const ResourceManager = core.ResourceManager;
const Shader = core.Shader;
const Model = core.Model;
const uniforms = core.constants.Uniforms;
const RenderContext = core.RenderContext;

const gallery_lights = scene_lights.gallery_lights;

const gltf_dir = "assets/toon_shooter_kit/Environment/glTF/";

const gltf_files = [_][]const u8{
    "Barrier_Fixed.gltf",
    "Barrier_Large.gltf",
    "Barrier_Single.gltf",
    "Barrier_Trash.gltf",
    "BearTrap_Closed.gltf",
    "BearTrap_Open.gltf",
    "BrickWall_1.gltf",
    "BrickWall_2.gltf",
    "CardboardBoxes_1.gltf",
    "CardboardBoxes_2.gltf",
    "CardboardBoxes_3.gltf",
    "CardboardBoxes_4.gltf",
    "Container_Long.gltf",
    "Container_Small.gltf",
    "Crate.gltf",
    "Debris_BrokenCar.gltf",
    "Debris_Papers_1.gltf",
    "Debris_Papers_2.gltf",
    "Debris_Papers_3.gltf",
    "Debris_Pile.gltf",
    "Debris_Tires.gltf",
    "ExplodingBarrel.gltf",
    "ExplodingBarrel_Spilled.gltf",
    "Fence.gltf",
    "Fence_Long.gltf",
    "GasCan.gltf",
    "GasTank.gltf",
    "Health.gltf",
    "Key.gltf",
    "Landmine.gltf",
    "MetalFence.gltf",
    "Pallet.gltf",
    "Pallet_Broken.gltf",
    "Pipes.gltf",
    "SackTrench.gltf",
    "SackTrench_Small.gltf",
    "Sign.gltf",
    "Sofa.gltf",
    "Sofa_Small.gltf",
    "StreetLight.gltf",
    "Structure_1.gltf",
    "Structure_2.gltf",
    "Structure_3.gltf",
    "Structure_4.gltf",
    "Tank.gltf",
    "TrafficCone.gltf",
    "TrashContainer.gltf",
    "TrashContainer_Open.gltf",
    "Tree_1.gltf",
    "Tree_2.gltf",
    "Tree_3.gltf",
    "Tree_4.gltf",
    "WaterTank_Floor.gltf",
    "WaterTank_Platform.gltf",
    "WoodPlanks.gltf",
};

const grid_spacing: f32 = 5.0;
const grid_cols: usize = 8;

pub const ToonGalleryScene = struct {
    resource_manager: *ResourceManager,
    scene_camera: *SceneCamera,
    floor: Floor,
    models: [gltf_files.len]*Model,
    model_matrices: [gltf_files.len]Mat4,
    shader: *Shader,

    const Self = @This();

    pub fn init(context: Context, input: *core.Input) !*Scene {
        const camera = try FreeCamera.init(
            context.alloc,
            input.framebuffer_width,
            input.framebuffer_height,
        );

        const rm = try ResourceManager.init(context);

        const shader = try rm.createShader(
            "games/level_01/shaders/animated_pbr.vert",
            "games/level_01/shaders/animated_pbr.frag",
        );

        // Set PBR lighting - bright overhead light with fill
        shader.setVec3("lightPosition", vec3(10.0, 20.0, 10.0));
        shader.setVec3("lightColor", vec3(1.0, 0.95, 0.9));
        shader.setFloat("lightIntensity", 2.5);

        var models: [gltf_files.len]*Model = undefined;
        var model_matrices: [gltf_files.len]Mat4 = undefined;

        for (gltf_files, 0..) |file, i| {
            var path_buf: [256]u8 = undefined;
            const full_path = std.fmt.bufPrint(&path_buf, "{s}{s}", .{ gltf_dir, file }) catch unreachable;

            // Strip .gltf extension for the name
            const name = file[0 .. file.len - 5];
            models[i] = try rm.loadModel(name, full_path);

            const col: f32 = @floatFromInt(i % grid_cols);
            const row: f32 = @floatFromInt(i / grid_cols);
            const x = (col - @as(f32, @floatFromInt(grid_cols)) / 2.0) * grid_spacing;
            const z = (row - @as(f32, @floatFromInt(gltf_files.len / grid_cols)) / 2.0) * grid_spacing;
            model_matrices[i] = Mat4.fromTranslation(vec3(x, 0.0, z));
        }

        const floor = try Floor.init(rm);

        const scene = try context.alloc.create(Self);
        scene.* = .{
            .resource_manager = rm,
            .scene_camera = camera,
            .floor = floor,
            .models = models,
            .model_matrices = model_matrices,
            .shader = shader,
        };

        scene.floor.update_lights(gallery_lights);
        scene.floor.plane.shape.is_visible = true;

        return try Scene.init(context.alloc, "ToonGallery", scene, input);
    }

    pub fn cleanUp(self: *Self) void {
        self.resource_manager.cleanUp();
    }

    pub fn getSceneCamera(self: *Self) *SceneCamera {
        return self.scene_camera;
    }

    pub fn update(self: *Self, input: *core.Input) !void {
        try self.scene_camera.update(input);
        try self.scene_camera.processInput(input);
    }

    pub fn draw(self: *Self, time: f32) void {
        var camera = self.getSceneCamera().getCamera();
        const ctx = camera.getRenderContext(time);

        // Draw all glTF models
        self.shader.setMat4(uniforms.Projection_View, &ctx.projection_view);
        for (self.models, 0..) |model, i| {
            self.shader.setMat4(uniforms.Mat_Model, &self.model_matrices[i]);
            model.draw(self.shader, 1);
        }

        self.floor.draw(ctx);
    }
};
