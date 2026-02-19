const std = @import("std");
const glfw = @import("zglfw");
const zopengl = @import("zopengl");
const gl = @import("zopengl").bindings;
const core = @import("core");
const math = @import("math");
const nodes_ = @import("nodes_interfaces.zig");

const State = @import("main.zig").State;
const main = @import("main.zig");
const shapes = core.shapes;

const Cylinder = core.shapes.Cylinder;

const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const vec3 = math.vec3;
const vec4 = math.vec4;
const Mat4 = math.Mat4;
const Quat = math.Quat;
const Ray = core.Ray;

const Allocator = std.mem.Allocator;
const EnumSet = std.EnumSet;

const Model = core.Model;
const GltfAsset = core.asset_loader.GltfAsset;
const Shader = core.Shader;
const Texture = core.texture.Texture;
const TextureConfig = core.texture.TextureConfig;
const TextureFilter = core.texture.TextureFilter;
const TextureWrap = core.texture.TextureWrap;
const Node = nodes_.Node;
const Transform = core.Transform;
const Camera = core.Camera;

const Window = glfw.Window;

const SCR_WIDTH: f32 = 1000.0;
const SCR_HEIGHT: f32 = 1000.0;

const SIZE_OF_FLOAT = @sizeOf(f32);
const SIZE_OF_VEC3 = @sizeOf(Vec3);
const SIZE_OF_VEC4 = @sizeOf(Vec4);
const SIZE_OF_QUAT = @sizeOf(Quat);

pub fn run(window: *glfw.Window) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();

    gl.enable(gl.DEPTH_TEST);

    const window_scale = window.getContentScale();

    const viewport_width = SCR_WIDTH * window_scale[0];
    const viewport_height = SCR_HEIGHT * window_scale[1];
    const scaled_width = viewport_width / window_scale[0];
    const scaled_height = viewport_height / window_scale[1];

    const camera = try Camera.init(
        allocator,
        .{
            .position = vec3(0.0, 2.0, 14.0),
            .target = vec3(0.0, 2.0, 0.0),
            .scr_width = scaled_width,
            .scr_height = scaled_height,
        },
    );
    defer camera.deinit();

    main.state = State{
        .viewport_width = viewport_width,
        .viewport_height = viewport_height,
        .scaled_width = scaled_width,
        .scaled_height = scaled_height,
        .window_scale = window_scale,
        .camera = camera,
        .projection = camera.getProjectionWithType(.Perspective),
        .projection_type = .Perspective,
        .light_postion = vec3(1.2, 1.0, 2.0),
        .delta_time = 0.0,
        .total_time = 0.0,
        .world_point = null,
        .current_position = vec3(0.0, 0.0, 0.0),
        .target_position = vec3(0.0, 0.0, 0.0),
        .input = core.Input.init(window),
    };

    const basic_model_shader = try Shader.init(
        allocator,
        "examples/scene_tree/basic_model.vert",
        "examples/scene_tree/basic_model.frag",
    );
    defer basic_model_shader.deinit();

    const cubeboid = try shapes.createCube(
        allocator,
        .{
            .width = 1.0,
            .height = 1.0,
            .depth = 2.0,
        },
    );
    defer allocator.destroy(cubeboid);
    defer cubeboid.deinit();

    const plane = try shapes.createCube(
        allocator,
        .{
            .width = 100.0,
            .height = 2.0,
            .depth = 100.0,
            .num_tiles_x = 50.0,
            .num_tiles_y = 1.0,
            .num_tiles_z = 50.0,
        },
    );
    defer allocator.destroy(plane);
    defer plane.deinit();

    const cylinder = try shapes.createCylinder(
        allocator,
        1.0,
        4.0,
        20.0,
    );
    defer allocator.destroy(cylinder);
    defer cylinder.deinit();

    var texture_diffuse = TextureConfig{
        .filter = .Linear,
        .flip_v = false,
        .gamma_correction = false,
        .wrap = TextureWrap.Repeat,
    };

    const cube_texture = try Texture.initFromFile(
        allocator,
        "assets/textures/container.jpg",
        texture_diffuse,
    );

    texture_diffuse.wrap = TextureWrap.Repeat;
    const surface_texture = try Texture.initFromFile(
        allocator,
        "assets/Textures/Floor/Floor D.png",
        texture_diffuse,
    );

    // const model_path = ""/Users/john/Dev/Repos/Egregoria/assets/models/pedestrian.glb"";
    const model_path = "glTF-Sample-Models/CesiumMan/glTF-Binary/CesiumMan.glb";
    var gltf_asset = try GltfAsset.init(allocator, "alien", model_path);
    try gltf_asset.load();

    const model = try gltf_asset.buildModel();

    // Simple placeholder object for root node (no update or draw methods)
    const RootPlaceholder = struct {
        pub fn draw(self: *@This(), shader: *Shader) void {
            _ = self;
            _ = shader;
        }
    };
    var root_placeholder = RootPlaceholder{};

    const root_node = try Node.init(allocator, "root_node", &root_placeholder, &main.state);

    const node_model = try Node.init(allocator, "node_model", model, &main.state);
    defer node_model.deinit();

    node_model.transform.translation = vec3(0.0, 0.0, 2.0);
    node_model.transform.rotation = Quat.fromAxisAngle(vec3(1.0, 0.0, 0.0), math.degreesToRadians(-90.0));

    const node_cylinder = try Node.init(allocator, "shape_cylinder", cylinder, &main.state);
    defer node_cylinder.deinit();

    root_node.addChild(node_model);
    root_node.addChild(node_cylinder);

    const cube_positions = [_]Vec3{
        vec3(3.0, 0.5, 0.0),
        vec3(1.5, 0.5, 0.0),
        vec3(0.0, 0.5, 0.0),
        vec3(-1.5, 0.5, 0.0),
        vec3(-3.0, 0.5, 0.0),
    };

    for (cube_positions) |position| {
        const cube = try Node.init(
            allocator,
            "shape_cubeboid",
            cubeboid,
            &main.state,
        );
        cube.transform.translation = position;
        root_node.addChild(cube);
    }

    const node_cube_spin = try Node.init(
        allocator,
        "shape_cubeboid",
        cubeboid,
        &main.state,
    );
    defer node_cube_spin.deinit();
    node_cube_spin.transform.translation = vec3(0.0, 4.0, 0.0);

    node_cylinder.addChild(node_cube_spin);

    const node_cube = try Node.init(
        allocator,
        "shape_cubeboid",
        cubeboid,
        &main.state,
    );
    defer node_cube.deinit();

    const cube_transforms = [_]Mat4{
        Mat4.fromTranslation(vec3(3.0, 0.5, 0.0)),
        Mat4.fromTranslation(vec3(1.5, 0.5, 0.0)),
        Mat4.fromTranslation(vec3(0.0, 0.5, 0.0)),
        Mat4.fromTranslation(vec3(-1.5, 0.5, 0.0)),
        Mat4.fromTranslation(vec3(-3.0, 0.5, 0.0)),
    };

    const xz_plane_point = vec3(0.0, 0.0, 0.0);
    const xz_plane_normal = vec3(0.0, 1.0, 0.0);

    // draw loop
    // -----------
    while (!window.shouldClose()) {
        const current_time: f32 = @floatCast(glfw.getTime());
        main.state.delta_time = current_time - main.state.total_time;
        main.state.total_time = current_time;

        // main.state.view = switch (main.state.view_type) {
        //     .LookAt => camera.getLookAtView(),
        //     .LookTo => camera.getLookToView(),
        // };

        gl.clearColor(0.1, 0.3, 0.1, 1.0);
        gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

        main.processKeys();

        const world_ray = math.getWorldRayFromMouse(
            main.state.scaled_width,
            main.state.scaled_height,
            &main.state.projection,
            &main.state.camera.getView(),
            main.state.input.mouse_x,
            main.state.input.mouse_y,
        );

        main.state.world_point = math.getRayPlaneIntersection(
            main.state.camera.getPosition(),
            world_ray, // direction
            xz_plane_point,
            xz_plane_normal,
        );

        const ray = Ray{
            .origin = main.state.camera.getPosition(),
            .direction = world_ray,
        };

        basic_model_shader.useShader();
        basic_model_shader.setMat4("matProjection", &main.state.camera.getProjection());
        basic_model_shader.setMat4("matView", &main.state.camera.getView());

        basic_model_shader.setVec3("ambient_color", vec3(1.0, 0.6, 0.6));
        basic_model_shader.setVec3("light_color", vec3(0.35, 0.4, 0.5));
        basic_model_shader.setVec3("light_dir", vec3(3.0, 3.0, 3.0));

        basic_model_shader.setBool("hasTexture", true);
        basic_model_shader.bindTextureAuto("textureDiffuse", cube_texture.gl_texture_id);

        var model_transform = Mat4.Identity;
        model_transform.translate(vec3(1.0, 0.0, 5.0));
        model_transform.scale(vec3(1.5, 1.5, 1.5));

        basic_model_shader.setMat4("matModel", &model_transform);

        const Picked = struct {
            id: ?u32,
            distance: f32,
        };

        var picked = Picked{
            .id = null,
            .distance = 10000.0,
        };

        for (cube_transforms, 0..) |t, id| {
            basic_model_shader.setMat4("matModel", &t);
            const aabb = cubeboid.aabb.transform(&t);
            const distance = aabb.rayIntersects(ray);
            if (distance) |d| {
                if (picked.id != null) {
                    if (d < picked.distance) {
                        picked.id = @intCast(id);
                        picked.distance = d;
                    }
                } else {
                    picked.id = @intCast(id);
                    picked.distance = d;
                }
            }
        }

        for (cube_positions, 0..) |t, i| {
            if (picked.id != null and picked.id == @as(u32, @intCast(i))) {
                basic_model_shader.setVec4("hit_color", vec4(1.0, 0.0, 0.0, 0.0));
            }

            node_cube.transform.translation = t;
            node_cube.updateTransform(null);
            node_cube.draw(basic_model_shader);

            basic_model_shader.setVec4("hit_color", vec4(0.0, 0.0, 0.0, 0.0));
        }

        if (main.state.input.mouse_left_button and main.state.world_point != null) {
            main.state.target_position = main.state.world_point.?;
        }

        updateSpin(node_cylinder, &main.state);

        root_node.transform.translation = main.state.target_position;
        root_node.updateTransform(null);
        root_node.draw(basic_model_shader);

        const plane_transform = Mat4.fromTranslation(vec3(0.0, -1.0, 0.0));
        basic_model_shader.setMat4("matModel", &plane_transform);
        basic_model_shader.bindTextureAuto("textureDiffuse", surface_texture.gl_texture_id);
        plane.draw(basic_model_shader);

        if (main.state.spin) {
            main.state.camera.movement.processMovement(.orbit_right, main.state.delta_time * 1.0);
        }

        window.swapBuffers();
        glfw.pollEvents();
    }

    glfw.terminate();
}

pub fn updateSpin(node: *Node, st: *State) void {
    const up = vec3(0.0, 1.0, 0.0);
    const velocity: f32 = 5.0 * st.delta_time;
    const angle = math.degreesToRadians(velocity);
    const turn_rotation = Quat.fromAxisAngle(up, angle);
    node.transform.rotation = node.transform.rotation.mulQuat(turn_rotation);
}
