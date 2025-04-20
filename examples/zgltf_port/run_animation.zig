const std = @import("std");
const glfw = @import("zglfw");
const zopengl = @import("zopengl");
const zstbi = @import("zstbi");
const core = @import("core");
const math = @import("math");

const Camera = core.Camera;
const Builder = @import("builder.zig").GltfBuilder;

const gl = zopengl.bindings;

const Model = core.Model;
const ModelBuilder = core.ModelBuilder;
const animation = core.animation;
const String = core.string.String;
const FrameCount = core.FrameCount;

const Shader = @import("shader.zig").Shader;

const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const vec2 = math.vec2;
const vec3 = math.vec3;
const Mat4 = math.Mat4;
const Quat = math.Quat;

const Texture = core.texture.Texture;
const TextureType = core.texture.TextureType;
const Animator = animation.Animator;
const AnimationClip = animation.AnimationClip;
const AnimationRepeat = animation.AnimationRepeatMode;

const Window = glfw.Window;

const SCR_WIDTH: f32 = 800.0;
const SCR_HEIGHT: f32 = 800.0;

// Lighting
const LIGHT_FACTOR: f32 = 1.0;
const NON_BLUE: f32 = 0.9;

const FLOOR_LIGHT_FACTOR: f32 = 0.35;
const FLOOR_NON_BLUE: f32 = 0.7;

const content_dir = "assets";

const state_ = @import("state.zig");
const State = state_.State;

const camera_position = vec3(0.0, 12.0, -40.0);
const camera_target = vec3(0.0, 12.0, 0.0);

pub fn run(allocator: std.mem.Allocator, window: *glfw.Window, model_path: []const u8) !void {
    std.debug.print("running test_animation\n", .{});

    const window_scale = window.getContentScale();

    const viewport_width = SCR_WIDTH * window_scale[0];
    const viewport_height = SCR_HEIGHT * window_scale[1];
    const scaled_width = viewport_width / window_scale[0];
    const scaled_height = viewport_height / window_scale[1];

    const camera = try Camera.init(
        allocator,
        .{
            .position = camera_position,
            .target = camera_target,
            .rotation = 0.0,
            .scr_width = scaled_width,
            .scr_height = scaled_height,
        },
    );

    state_.state = state_.State{
        .viewport_width = viewport_width,
        .viewport_height = viewport_height,
        .scaled_width = scaled_width,
        .scaled_height = scaled_height,
        .window_scale = window_scale,
        .camera = camera,
        .projection = camera.getProjectionMatrix(.Perspective),
        .projection_type = .Perspective,
        .view_type = .LookAt,
        .light_postion = vec3(10.0, 10.0, -30.0),
        .delta_time = 0.0,
        .total_time = 0.0,
        .world_point = null,
        .camera_initial_position = camera_position,
        .camera_initial_target = camera_target,
        .input = .{
            .first_mouse = true,
            .mouse_x = scaled_width / 2.0,
            .mouse_y = scaled_height / 2.0,
            .key_presses = std.EnumSet(glfw.Key).initEmpty(),
        },
        .animation_id = 0,
    };

    const state = &state_.state;
    state_.initWindowHandlers(window);

    const shader = try Shader.init(
        allocator,
        "examples/zgltf_port/shaders/player_shader.vert",
        "examples/zgltf_port/shaders/basic_model.frag",
        // "examples/zgltf_port/shaders/pbr.vert",
        // "examples/zgltf_port/shaders/pbr.frag",
    );

    std.debug.print("Shader id: {d}\n", .{shader.id});

    const ambientColor: Vec3 = vec3(NON_BLUE * 0.7, NON_BLUE * 0.7, 0.7);
    var texture_cache = std.ArrayList(*Texture).init(allocator);

    std.debug.print("\n--- Build gltf model ----------------------\n\n", .{});
    const gltf_model = blk: {
        std.debug.print("Main: loading model: {s}\n", .{model_path});
        var builder = try Builder.init(allocator, &texture_cache, "Spacesuit", model_path);
        const gltfmodel = try builder.build();
        builder.deinit();
        break :blk gltfmodel;
    };

    std.debug.print("\n----------------------\n", .{});

    // --- event loop
    state.total_time = @floatCast(glfw.getTime());
    // var frame_counter = FrameCount.new();

    gl.enable(gl.DEPTH_TEST);

    // state.single_mesh_id = 2;
    // var last_animation: i32 = 0;

    shader.useShader();
    // shader.set_bool("has_color", false);
    // shader.set_vec3("diffuse_color", &vec3(0.0, 0.0, 0.0));
    // shader.set_vec3("ambient_color", &vec3(0.0, 0.0, 0.0));
    // shader.set_vec3("specular_color", &vec3(0.0, 0.0, 0.0));
    // shader.set_vec3("emissive_color", &vec3(0.0, 0.0, 0.0));
    // shader.set_vec3("hit_color", &vec3(0.0, 0.0, 0.0));

    // GLTL to openGL
    // const conversion_matrix = Mat4{ .data = .{
    //         .{ 1.0, 0.0, 0.0, 0.0 },
    //         .{ 0.0, 1.0, 0.0, 0.0 },
    //         .{ 0.0, 0.0, -1.0, 0.0 },
    //         .{ 0.0, 0.0, 0.0, 1.0 },
    //     } };
    // gl.frontFace(gl.CW); // Adjust front-face culling
    // Rotation matrix to convert glTF coordinate system to OpenGL
    const gltf_to_openGL_coordinates = Mat4{ .data = .{
        .{1.0, 0.0, 0.0, 0.0}, 
        .{0.0, math.cos(-math.pi/2), -math.sin(-math.pi/2), 0.0 },
        .{0.0, math.sin(-math.pi/2), math.cos(-math.pi/2), 0.0, },
        .{0.0, 0.0, 0.0, 1.0},
    } };
    _ = gltf_to_openGL_coordinates;

    gl.enable(gl.CULL_FACE);

    // camera.position = vec3(0.0, 8.0, 10.0);
    // camera.target = vec3(0.0, 8.0, 0.0);
    // camera.forward = vec3(-4.0, 2.0, 0.0);
    // camera.target_pans = true;

    var buf: [1024]u8 = undefined;
    std.debug.print("{s}\n", .{ camera.asString(&buf) });

    while (!window.shouldClose()) {
        const current_time: f32 = @floatCast(glfw.getTime());
        state.delta_time = current_time - state.total_time;
        state.total_time = current_time;

        state_.processKeys();

        // frame_counter.update();

        glfw.pollEvents();
        gl.clearColor(0.5, 0.5, 0.5, 1.0);
        gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

        shader.setMat4("matProjection", &state.projection);
        shader.setMat4("matView", &state.camera.getViewMatrix());

        // _ = conversion_matrix;
        var model_transform = Mat4.identity();
        // model_transform.rotateByDegrees(&vec3(0.0, 1.0, 0.0), 180.0);
        // var model_transform = gltf_to_openGL_coordinates;
        // var model_transform = conversion_matrix;
        // model_transform.translate(&vec3(0.0, -10.4, -400.0));
        //model_transform.scale(&vec3(1.0, 1.0, 1.0));
        ////model_transform.translation(&vec3(0.0, 0.0, 0.0));
        // model_transform.rotateByDegrees(&vec3(0.0, 1.0, 0.0), 180.0);
        model_transform.scale(&vec3(3.0, 3.0, 3.0));
        // model_transform.scale(&vec3(0.02, 0.02, 0.02));
        shader.setMat4("matModel", &model_transform);

        // Basic shader
        shader.setBool("useLight", true);
        shader.setVec3("ambient", &ambientColor);
        shader.setVec3("ambient_light", &vec3(1.0, 0.8, 0.8));
        shader.setVec3("light_color", &vec3(0.1, 0.1, 0.1));
        shader.setVec3("light_dir", &vec3(10.0, 10.0, 2.0));

        // PBR shader
        shader.setVec3("lightPosition", &vec3(0.0, 20.0, 5.0));
        shader.setVec3("lightColor", &vec3(1.0, 1.0, 1.0));
        shader.setFloat("lightIntensity", 1500.0);

        shader.setVec3("viewPosition", &state.camera.movement.position);

        // shader.set_mat4("aimRot", &identity);
        // lightSpaceMatrix is a view * ortho projection matrix for shadows
        // shader.set_mat4("lightSpaceMatrix", &identity);

        // model.render(shader);
        gltf_model.render(shader);

        //try core.dumpModelNodes(model);
        window.swapBuffers();

        //break;
    }

    // try core.dumpModelNodes(model);
    // model.meshes.items[2].printMeshVertices();

    std.debug.print("\nRun completed.\n\n", .{});

    shader.deinit();
    camera.deinit();
    // model.deinit();
    gltf_model.deinit();

    for (texture_cache.items) |_texture| {
        _texture.deinit();
    }
    texture_cache.deinit();
}
