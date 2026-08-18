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
const Shape = core.shapes.Shape;
const uniforms = core.constants.Uniforms;
const RenderContext = core.RenderContext;

const gallery_lights = scene_lights.gallery_lights;

const obj_dir = "assets/modular_ruins/OBJ/";

const obj_files = [_][]const u8{
    "Arch_Gothic.obj",
    "Arch_Gothic_RoundColumn.obj",
    "Arch_Round.obj",
    "Arch_Round_RoundColumn.obj",
    "Barrel.obj",
    "BearTrap_Closed.obj",
    "BearTrap_Open.obj",
    "Bookcase_Empty.obj",
    "Bookcase_Full.obj",
    "Brick.obj",
    "Bricks.obj",
    "BridgeSection.obj",
    "Bush_1x1.obj",
    "Bush_2x1.obj",
    "Bush_2x2.obj",
    "Bush_Large.obj",
    "Bush_Round.obj",
    "Candles_1.obj",
    "Candles_2.obj",
    "Cart.obj",
    "Character_Animated.obj",
    "Chest.obj",
    "Chest_Gold.obj",
    "Column_BridgeSupport.obj",
    "Column_Round.obj",
    "Column_Round_Short.obj",
    "Column_Square.obj",
    "Crate.obj",
    "Curve_1.obj",
    "Curve_1_Overgrown.obj",
    "Curve_2.obj",
    "Curve_2_Overgrown.obj",
    "DeadTree_1.obj",
    "DeadTree_2.obj",
    "DeadTree_3.obj",
    "Doors_GothicArch.obj",
    "Doors_GothicArch_Covered.obj",
    "Doors_RoundArch.obj",
    "Doors_RoundArch_Covered.obj",
    "Flag_GothicArch.obj",
    "Flag_RoundArch.obj",
    "Flag_Wall.obj",
    "Flag_Wall2.obj",
    "Floor_Diamond.obj",
    "Floor_Hole_Corner.obj",
    "Floor_Hole_Straight.obj",
    "Floor_SquareLarge.obj",
    "Floor_Squares.obj",
    "Floor_Standard.obj",
    "Floor_Standard_Half.obj",
    "Floor_Tree.obj",
    "Grass.obj",
    "Pot1.obj",
    "Pot1_Broken.obj",
    "Pot2.obj",
    "Pot2_Broken.obj",
    "Pot3.obj",
    "Pot3_Broken.obj",
    "Rail_Corner.obj",
    "Rail_Divider.obj",
    "Rail_Straight.obj",
    "Skull.obj",
    "Stairs.obj",
    "Stairs_2.obj",
    "Statue_Fox.obj",
    "Statue_Stag.obj",
    "Support_Center.obj",
    "Support_Left.obj",
    "Support_Right.obj",
    "Support_Tall.obj",
    "Torch.obj",
    "Trapdoor.obj",
    "Tree_1.obj",
    "Tree_2.obj",
    "Tree_3.obj",
    "Wall.obj",
    "Wall_ArchGothic.obj",
    "Wall_ArchRound.obj",
    "Wall_ArchRound_Broken.obj",
    "Wall_ArchRound_Overgrown.obj",
    "Wall_ArchRound_Overgrown_Broken.obj",
    "Wall_Broken.obj",
    "Wall_Double_Broken.obj",
    "Wall_Double_Hole.obj",
    "Wall_Half.obj",
    "Wall_Hole.obj",
    "Wall_Overgrown.obj",
    "Window_Bars.obj",
    "Window_Bars_Double_Overgrown.obj",
    "Window_Bars_Overgrown.obj",
    "Window_Open.obj",
    "Window_Open_Double.obj",
};

const grid_spacing: f32 = 4.0;
const grid_cols: usize = 10;

pub const RuinsGalleryScene = struct {
    resource_manager: *ResourceManager,
    scene_camera: *SceneCamera,
    floor: Floor,
    shapes: [obj_files.len]*Shape,
    model_matrices: [obj_files.len]Mat4,
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
            "examples/bullets/shaders/basic_model.vert",
            "examples/bullets/shaders/basic_model.frag",
        );

        gallery_lights.apply(shader);
        shader.setBool("hasColor", true);
        shader.setVec4("diffuseColor", math.vec4(0.25, 0.25, 0.25, 1.0));

        var shapes: [obj_files.len]*Shape = undefined;
        var model_matrices: [obj_files.len]Mat4 = undefined;

        for (obj_files, 0..) |file, i| {
            var path_buf: [256]u8 = undefined;
            const full_path = std.fmt.bufPrint(&path_buf, "{s}{s}", .{ obj_dir, file }) catch unreachable;
            shapes[i] = try rm.loadOBJ(full_path);

            const col: f32 = @floatFromInt(i % grid_cols);
            const row: f32 = @floatFromInt(i / grid_cols);
            const x = (col - @as(f32, @floatFromInt(grid_cols)) / 2.0) * grid_spacing;
            const z = (row - @as(f32, @floatFromInt(obj_files.len / grid_cols)) / 2.0) * grid_spacing;
            model_matrices[i] = Mat4.fromTranslation(vec3(x, 0.0, z));
        }

        const floor = try Floor.init(rm);

        const scene = try context.alloc.create(Self);
        scene.* = .{
            .resource_manager = rm,
            .scene_camera = camera,
            .floor = floor,
            .shapes = shapes,
            .model_matrices = model_matrices,
            .shader = shader,
        };

        scene.floor.update_lights(gallery_lights);
        scene.floor.plane.shape.is_visible = true;

        return try Scene.init(context.alloc, "RuinsGallery", scene, input);
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

        // Draw all OBJ shapes
        self.shader.setMat4(uniforms.Projection_View, &ctx.projection_view);
        for (self.shapes, 0..) |shape, i| {
            self.shader.setMat4(uniforms.Mat_Model, &self.model_matrices[i]);
            shape.draw(self.shader, 1);
        }

        self.floor.draw(ctx);
    }
};
