const std = @import("std");
const glfw = @import("zglfw");
const zopengl = @import("zopengl");
const zstbi = @import("zstbi");
const core = @import("core");
const math = @import("math");
const assets_list = @import("assets_list.zig");
const ui_display = @import("ui_display.zig");
const screenshot = @import("screenshot.zig");

const Camera = core.Camera;
const asset_loader = core.asset_loader;

const gl = zopengl.bindings;

const Model = core.Model;
const ModelBuilder = core.ModelBuilder;
const String = core.string.String;
const FrameCounter = core.FrameCounter;
const Animator = core.Animator;
// const AnimationClip = core.AnimationClip;
const AnimationRepeatMode = core.AnimationRepeatMode;

const Shader = core.Shader;

const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const vec2 = math.vec2;
const vec3 = math.vec3;
const Mat4 = math.Mat4;
const Quat = math.Quat;

const Window = glfw.Window;

// Lighting
const LIGHT_FACTOR: f32 = 1.0;
const NON_BLUE: f32 = 0.9;

const FLOOR_LIGHT_FACTOR: f32 = 0.35;
const FLOOR_NON_BLUE: f32 = 0.7;

const content_dir = "assets";

const state_ = @import("state.zig");
const State = state_.State;
const AABB = core.AABB;

var buf1: [1024]u8 = undefined;
var buf2: [1024]u8 = undefined;

// Shader debug buffers
var debug_dump_buffer: [4096]u8 = undefined;

// Model loading helper function
fn loadModel(allocator: std.mem.Allocator, model_info: assets_list.DemoModel, state: *state_.State) !*Model {
    // const path = try std.fs.path.join(allocator, &[_][]const u8{ assets_list.root, model_info.path });
    // defer allocator.free(path);
    const path = model_info.path;

    std.debug.print("\nLoading model: {s} ({s}) - {s}\n", .{ model_info.name, model_info.format, model_info.description });
    std.debug.print("Path: {s}\n", .{path});

    var gltf_asset = try asset_loader.GltfAsset.init(allocator, model_info.name, path);

    // Set normal generation mode for models that need it
    gltf_asset.setNormalGenerationMode(.accurate);

    try gltf_asset.load();
    const model = try gltf_asset.buildModel();

    // Check if model has animations and start appropriate animation(s)
    if (gltf_asset.gltf.animations) |animations| {
        if (animations.len > 0) {
            // Check if this model should play all animations simultaneously
            if (model_info.play_all_animations) {
                std.debug.print("Model configured for multi-animation - playing all {d} animations simultaneously\n", .{animations.len});
                try model.playAllAnimations();
                state.animation_id = -1; // Use -1 to indicate "all animations" mode
            } else {
                std.debug.print("Model has {d} animations, playing first animation\n", .{animations.len});
                try model.animator.playAnimationById(0);
                state.animation_id = 0;
            }
        } else {
            std.debug.print("Model has no animations\n", .{});
            state.animation_id = -1;
        }
    } else {
        std.debug.print("Model has no animations\n", .{});
        state.animation_id = -1;
    }

    return model;
}

// Camera positioning helper function
fn positionCameraForModel(model: *Model, camera: *Camera) void {
    const bbox = model.calculateBoundingBox();

    // Calculate the center and size of the bounding box
    const center = vec3(
        (bbox.min.x + bbox.max.x) * 0.5,
        (bbox.min.y + bbox.max.y) * 0.5,
        (bbox.min.z + bbox.max.z) * 0.5,
    );

    const size = vec3(
        bbox.max.x - bbox.min.x,
        bbox.max.y - bbox.min.y,
        bbox.max.z - bbox.min.z,
    );

    // Calculate the maximum extent
    const max_extent = @max(@max(size.x, size.y), size.z);

    // Position camera at a reasonable distance
    const distance = max_extent * 2.5; // Factor to ensure model fits in view
    const camera_pos = vec3(center.x, center.y + max_extent * 0.3, center.z + distance);

    // Update camera position and target with proper orientation vectors
    camera.movement.reset(camera_pos, center);

    outputPositions(model, camera);
}

fn outputPositions(model: *Model, camera: *Camera) void {
    const bbox = model.calculateBoundingBox();
    std.debug.print("Model bounds - min: {s}  max: {s}\n", .{
        bbox.min.asString(&buf1),
        bbox.max.asString(&buf2),
    });
    std.debug.print("Camera positioned at: {s}  looking at: {s}\n", .{
        camera.movement.position.asString(&buf1),
        camera.movement.target.asString(&buf2),
    });
}

const camera_position = vec3(0.0, 12.0, 40.0);
const camera_target = vec3(0.0, 12.0, 0.0);

pub fn run(window: *glfw.Window, initial_model_index: usize, max_duration: ?f32) !void {
    std.debug.print("running app\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    core.string.init(allocator);

    const window_size = window.getSize();
    const window_scale = window.getContentScale();
    const viewport_width = @as(f32, @floatFromInt(window_size[0])) * window_scale[0];
    const viewport_height = @as(f32, @floatFromInt(window_size[1])) * window_scale[1];
    const scaled_width = viewport_width / window_scale[0];
    const scaled_height = viewport_height / window_scale[1];

    const camera = try Camera.init(
        allocator,
        .{
            .position = camera_position,
            .target = camera_target,
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
        .projection = camera.getProjectionMatrix(),
        .light_position = vec3(10.0, 10.0, -30.0),
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
            .key_processed = std.EnumSet(glfw.Key).initEmpty(),
        },
        .animation_id = 0,
        .current_model_index = initial_model_index,
    };

    const state = &state_.state;
    state_.initWindowHandlers(window);

    // Initialize UI system
    var ui_state = try ui_display.UIState.init(allocator, window);
    defer ui_state.deinit();

    // Initialize screenshot system
    var screenshot_mgr = screenshot.ScreenshotManager.init(allocator);
    defer screenshot_mgr.deinit();

    const shader = try Shader.init(
        allocator,
        // "examples/demo_app/shaders/player_shader.vert",
        // "examples/demo_app/shaders/basic_model.frag",
        "examples/demo_app/shaders/pbr.vert",
        "examples/demo_app/shaders/pbr.frag",
    );

    std.debug.print("Shader id: {d}\n", .{shader.id});

    const ambientColor: Vec3 = vec3(NON_BLUE * 0.7, NON_BLUE * 0.7, 0.7);
    // var texture_cache = std.ArrayList(*Texture).init(allocator);

    std.debug.print("\n--- Build gltf model ----------------------\n\n", .{});

    // Load initial model from demo list
    var current_model = try loadModel(allocator, state_.getCurrentModel(), state);

    // Position camera for initial model
    positionCameraForModel(current_model, camera);

    std.debug.print("\n----------------------\n", .{});

    // --- event loop
    const start_time = @as(f32, @floatCast(glfw.getTime()));
    state.total_time = start_time;
    // var frame_counter = FrameCounter.new();

    gl.enable(gl.DEPTH_TEST);

    shader.useShader();

    // gl.enable(gl.CULL_FACE); // Temporarily disabled to fix Fox lighting issue

    var buf: [1024]u8 = undefined;
    std.debug.print("{s}\n", .{camera.asString(&buf)});

    while (!window.shouldClose()) {
        const current_time: f32 = @floatCast(glfw.getTime());
        state.delta_time = current_time - state.total_time;
        state.total_time = current_time;

        // Check if we've exceeded the maximum duration
        if (max_duration) |duration| {
            if (current_time - start_time >= duration) {
                std.debug.print("Reached maximum duration of {d} seconds, exiting\n", .{duration});
                break;
            }
        }

        state_.processKeys();

        // Ensure screenshot framebuffer matches current viewport
        try screenshot_mgr.ensureFramebuffer(@intFromFloat(state.viewport_width), @intFromFloat(state.viewport_height));

        // One-shot screenshot capture: enable debug mode only when screenshot is requested
        var capture_screenshot = false;
        if (state.screenshot_requested) {
            capture_screenshot = true;
            shader.enableDebug();
            shader.clearDebugUniforms();
            // Bind screenshot framebuffer for capture
            screenshot_mgr.capture.bindForCapture();
        }

        // Handle regular shader debug state (separate from screenshot)
        if (state.shader_debug_enabled and !capture_screenshot) {
            shader.enableDebug();
            shader.clearDebugUniforms();
        } else if (!capture_screenshot) {
            shader.disableDebug();
        }

        // Update UI system
        ui_state.update(window);

        // Check if model reload is requested
        if (state.model_reload_requested) {
            std.debug.print("Reloading model...\n", .{});
            current_model.deinit();
            current_model = loadModel(allocator, state_.getCurrentModel(), state) catch |err| {
                std.debug.panic("Failed to load model: {}\n", .{err});
                // Keep the old model if loading fails
                // current_model = try loadModel(allocator, assets_list.demo_models[0]);
            };
            state.model_reload_requested = false;
        }

        // Check if camera repositioning is requested
        if (state.camera_reposition_requested) {
            std.debug.print("Repositioning camera for current model...\n", .{});
            positionCameraForModel(current_model, camera);
            state.camera_reposition_requested = false;
        }

        if (state.output_position_requested) {
            outputPositions(current_model, state.camera);
            state.output_position_requested = false;
        }

        // Handle animation control requests
        if (state.animation_reset_requested) {
            if (state.animation_id >= 0) {
                try current_model.animator.playAnimationById(@intCast(state.animation_id));
                std.debug.print("Reset animation to {d}\n", .{state.animation_id});
            }
            state.animation_reset_requested = false;
        }

        if (state.animation_next_requested) {
            if (current_model.gltf_asset.gltf.animations) |animations| {
                if (animations.len > 0) {
                    state.animation_id = @mod(state.animation_id + 1, @as(i32, @intCast(animations.len)));
                    try current_model.animator.playAnimationById(@intCast(state.animation_id));
                    std.debug.print("Next animation: {d}/{d}\n", .{ state.animation_id + 1, animations.len });
                }
            }
            state.animation_next_requested = false;
        }

        if (state.animation_prev_requested) {
            if (current_model.gltf_asset.gltf.animations) |animations| {
                if (animations.len > 0) {
                    state.animation_id -= 1;
                    if (state.animation_id < 0) {
                        state.animation_id = @as(i32, @intCast(animations.len)) - 1;
                    }
                    try current_model.animator.playAnimationById(@intCast(state.animation_id));
                    std.debug.print("Previous animation: {d}/{d}\n", .{ state.animation_id + 1, animations.len });
                }
            }
            state.animation_prev_requested = false;
        }

        // Update animation
        try current_model.animator.updateAnimation(state.delta_time);

        // frame_counter.update();

        glfw.pollEvents();
        gl.clearColor(0.5, 0.5, 0.5, 1.0);
        gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

        shader.setMat4("matProjection", &state.projection);
        shader.setMat4("matView", &state.camera.getViewMatrix());

        var model_transform = Mat4.identity();
        shader.setMat4("matModel", &model_transform);

        // Basic shader
        shader.setBool("useLight", true);
        shader.setVec3("ambient", &ambientColor);
        shader.setVec3("ambient_light", &vec3(1.0, 0.8, 0.8));
        shader.setVec3("light_color", &vec3(0.1, 0.1, 0.1));
        shader.setVec3("light_dir", &vec3(10.0, 10.0, 2.0));

        // PBR shader
        shader.setVec3("lightPosition", &vec3(state.camera.movement.position.x + 50.0, state.camera.movement.position.y + 50.0, state.camera.movement.position.z + 50.0));
        shader.setVec3("lightColor", &vec3(1.0, 1.0, 1.0));
        shader.setFloat("lightIntensity", 100.0);

        shader.setVec3("viewPosition", &state.camera.movement.position);

        // Add custom debug values when debug is enabled (for both regular debug and screenshot)
        if (state.shader_debug_enabled or capture_screenshot) {
            var buf_temp: [64]u8 = undefined;
            shader.addDebugValue("camera_position", std.fmt.bufPrint(&buf_temp, "Vec3({d:.3}, {d:.3}, {d:.3})", .{ state.camera.movement.position.x, state.camera.movement.position.y, state.camera.movement.position.z }) catch "error");
            shader.addDebugValue("camera_target", std.fmt.bufPrint(buf1[0..64], "Vec3({d:.3}, {d:.3}, {d:.3})", .{ state.camera.movement.target.x, state.camera.movement.target.y, state.camera.movement.target.z }) catch "error");
            shader.addDebugValue("light_position", std.fmt.bufPrint(buf2[0..64], "Vec3({d:.3}, {d:.3}, {d:.3})", .{ state.light_position.x, state.light_position.y, state.light_position.z }) catch "error");
            shader.addDebugValue("frame_time", std.fmt.bufPrint(&buf_temp, "{d:.6}s", .{state.delta_time}) catch "error");
        }

        // Handle debug dump request
        if (state.shader_debug_dump_requested) {
            const dump_result = shader.dumpDebugUniforms(&debug_dump_buffer) catch "Failed to dump uniforms";
            std.debug.print("\n{s}\n", .{dump_result});
            state.shader_debug_dump_requested = false;
        }

        // model.render(shader);
        current_model.render(shader);

        // One-shot screenshot completion: dump data and clear flag
        if (capture_screenshot) {
            // Restore default framebuffer
            screenshot_mgr.capture.restoreDefault();
            gl.viewport(0, 0, @intFromFloat(state.viewport_width), @intFromFloat(state.viewport_height));

            // Save screenshot and uniforms using the simplified manager
            // (debug values were already added earlier in the loop)
            screenshot_mgr.takeScreenshot(shader) catch |err| {
                std.debug.print("Screenshot failed: {any}\n", .{err});
            };

            // Clean up: disable debug and clear flag
            shader.disableDebug();
            state.screenshot_requested = false;
            std.debug.print("Screenshot completed!\n", .{});
        }

        // Render UI overlay
        ui_state.render(current_model);

        //try core.dumpModelNodes(model);
        window.swapBuffers();

        //break;
    }

    std.debug.print("\nRun completed.\n\n", .{});

    shader.deinit();
    camera.deinit();
    current_model.deinit();
}
