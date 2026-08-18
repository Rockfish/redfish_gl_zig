const std = @import("std");
const glfw = @import("zglfw");
const zopengl = @import("zopengl");
const core = @import("core");
const math = @import("math");
const assets_list = @import("assets_list.zig");
const ui_display = @import("ui_display.zig");
const screenshot = @import("screenshot.zig");

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

const Arenas = core.Arenas;
const Context = core.Context;
const constants = core.constants;
const Camera = core.Camera;
const asset_loader = core.asset_loader;
const gl_debug = core.gl_debug;

const gl = zopengl.bindings;

const Model = core.Model;

const Shader = core.Shader;

const Vec3 = math.Vec3;
const vec3 = math.vec3;
const Mat4 = math.Mat4;

// Lighting
const NON_BLUE: f32 = 0.9;

const state_ = @import("state.zig");

var buf1: [1024]u8 = undefined;
var buf2: [1024]u8 = undefined;

// Shader debug buffers
var debug_dump_buffer: [4096]u8 = undefined;

const ModelScope = struct {
    allocator: Allocator,
    arenas: *Arenas,
    context: Context,
    model: ?*Model = null,

    pub fn init(gpa: Allocator, io: std.Io) !*ModelScope {
        const arenas = try Arenas.init(gpa);
        const context = arenas.context(io);
        const model_scope = try gpa.create(ModelScope);
        model_scope.* = ModelScope{
            .allocator = gpa,
            .arenas = arenas,
            .context = context,
            .model = null,
        };
        return model_scope;
    }

    pub fn setModel(self: *ModelScope, model: *Model) void {
        self.model = model;
    }

    pub fn getModel(self: *ModelScope) *Model {
        if (self.model) |m| {
            return m;
        }
        std.debug.panic("Model not initialized", .{});
    }

    pub fn cleanUp(self: *ModelScope) void {
        self.deleteGlObjects();
        self.model = null;
        self.arenas.resetAll();
    }

    pub fn deleteGlObjects(self: *ModelScope) void {
        if (self.model) |m| {
            m.deleteGlObjects();
        }
    }

    pub fn deinit(self: *ModelScope) void {
        self.arenas.deinit();
        self.allocator.destroy(self);
    }
};

fn swapScope(current: **ModelScope, next: **ModelScope) void {
    std.mem.swap(*ModelScope, current, next);
    next.*.cleanUp();
}

// Model loading helper function
fn loadModel(context: Context, model_info: assets_list.ModelInfo, state: *state_.State) !*Model {
    const path = model_info.path;

    std.debug.print("\nLoading model: {s} ({s}) - {s}\n", .{ model_info.name, model_info.format, model_info.description });
    std.debug.print("Path: {s}\n", .{path});

    var gltf_asset = try asset_loader.GltfAsset.init(context, model_info.name, path);

    // Set normal generation mode for models that need it
    gltf_asset.setNormalGenerationMode(.accurate);

    try gltf_asset.load();
    const model = try gltf_asset.buildModel();
    errdefer gltf_asset.deleteGlObjects();

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
        camera.movement.transform.translation.asString(&buf1),
        camera.movement.target.asString(&buf2),
    });
}

fn switchModel(state: *state_.State, current_scope: **ModelScope, next_scope: **ModelScope) !void {
    const initial_model_index = state.current_model_index;
    var next_model_index = @mod((state.current_model_index + state.model_index_increment), @as(i32, assets_list.model_infos.len));

    while (next_model_index != initial_model_index) {
        const model_info = assets_list.model_infos[@intCast(next_model_index)];

        const next_model: ?*Model = loadModel(next_scope.*.context, model_info, state) catch null;
        if (next_model) |model| {
            next_scope.*.setModel(model);
            swapScope(current_scope, next_scope);
            state.current_model_index = next_model_index;
            state.camera_reposition_requested = true;
            break;
        } else {
            std.debug.print("Failed to load model: {s}\n", .{model_info.path});
            next_scope.*.cleanUp();
            next_model_index = @mod((next_model_index + state.model_index_increment), @as(i32, assets_list.model_infos.len));
        }
    } else {
        std.debug.print("No valid model found.\n", .{});
    }
    state.model_reload_requested = false;
}

const camera_position = vec3(0.0, 12.0, 40.0);
const camera_target = vec3(0.0, 12.0, 0.0);

pub fn run(init: std.process.Init, window: *glfw.Window, initial_model_index: i32, max_duration: ?f32) !void {
    std.debug.print("running app\n", .{});

    var common_arenas = try Arenas.init(init.gpa);
    const context = common_arenas.context(init.io);

    var model_scope_a = try ModelScope.init(init.gpa, init.io);
    var model_scope_b = try ModelScope.init(init.gpa, init.io);

    var current_scope = model_scope_a;
    var next_scope = model_scope_b;

    core.string.init(context.alloc);

    const window_size = window.getSize();
    const window_scale = window.getContentScale();
    const viewport_width = @as(f32, @floatFromInt(window_size[0])) * window_scale[0];
    const viewport_height = @as(f32, @floatFromInt(window_size[1])) * window_scale[1];
    const scaled_width = viewport_width / window_scale[0];
    const scaled_height = viewport_height / window_scale[1];

    const camera = try Camera.init(
        context.alloc,
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
    var ui_state = ui_display.UIState.init(context.io, context.alloc, window);
    // defer ui_state.deinit();

    // Initialize screenshot system
    var screenshot_mgr = screenshot.ScreenshotManager.init(context.io, context.alloc);
    // defer screenshot_mgr.deinit();

    const shader = try Shader.init(
        context.io,
        context.alloc,
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
    current_scope.model = try loadModel(
        current_scope.context,
        state_.getCurrentModelInfo(),
        state,
    );

    // Position camera for initial model
    positionCameraForModel(current_scope.getModel(), camera);

    std.debug.print("\n----------------------\n", .{});

    // --- event loop
    const start_time: f32 = @floatCast(glfw.getTime());
    state.total_time = start_time;
    // var frame_counter = FrameCounter.new();

    gl.enable(gl.DEPTH_TEST);

    shader.useShader();

    // Drain setup-time errors (asset load, texture upload, shader link) so they
    // are not attributed to the first frame.
    gl_debug.check("setup");

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
            std.debug.print("Loading next model...\n", .{});
            // const next_model: ?*Model = loadModel(next_scope.context, state_.getCurrentModelInfo(), state) catch null;
            // if (next_model) |model| {
            //     next_scope.setModel(model);
            //     swapScope(&current_scope, &next_scope);
            // } else {
            //     std.debug.print("Failed to load model: {s}\n", .{state_.getCurrentModelInfo().path});
            // }
            try switchModel(state, &current_scope, &next_scope);
            state.model_reload_requested = false;
        }

        // Check if camera repositioning is requested
        if (state.camera_reposition_requested) {
            std.debug.print("Repositioning camera for current model...\n", .{});
            positionCameraForModel(current_scope.getModel(), camera);
            state.camera_reposition_requested = false;
        }

        if (state.output_position_requested) {
            outputPositions(current_scope.getModel(), state.camera);
            state.output_position_requested = false;
        }

        // Handle animation control requests
        if (state.animation_reset_requested) {
            if (state.animation_id >= 0) {
                try current_scope.getModel().animator.playAnimationById(@intCast(state.animation_id));
                std.debug.print("Reset animation to {d}\n", .{state.animation_id});
            }
            state.animation_reset_requested = false;
        }

        if (state.animation_next_requested) {
            if (current_scope.getModel().gltf_asset.gltf.animations) |animations| {
                if (animations.len > 0) {
                    state.animation_id = @mod(state.animation_id + 1, @as(i32, @intCast(animations.len)));
                    try current_scope.getModel().animator.playAnimationById(@intCast(state.animation_id));
                    std.debug.print("Next animation: {d}/{d}\n", .{ state.animation_id + 1, animations.len });
                }
            }
            state.animation_next_requested = false;
        }

        if (state.animation_prev_requested) {
            if (current_scope.getModel().gltf_asset.gltf.animations) |animations| {
                if (animations.len > 0) {
                    state.animation_id -= 1;
                    if (state.animation_id < 0) {
                        state.animation_id = @as(i32, @intCast(animations.len)) - 1;
                    }
                    try current_scope.getModel().animator.playAnimationById(@intCast(state.animation_id));
                    std.debug.print("Previous animation: {d}/{d}\n", .{ state.animation_id + 1, animations.len });
                }
            }
            state.animation_prev_requested = false;
        }

        // Update animation
        if (state.run_animation) {
            try current_scope.getModel().animator.updateAnimation(state.delta_time);
        }

        // frame_counter.update();

        glfw.pollEvents();
        gl.clearColor(0.5, 0.5, 0.5, 1.0);
        gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

        const ctx = state.camera.getRenderContext(state.total_time);
        shader.setMat4(constants.Uniforms.Projection_View, &ctx.projection_view);

        var model_transform = Mat4.Identity;
        shader.setMat4(constants.Uniforms.Mat_Model, &model_transform);

        // Basic shader
        shader.setBool("useLight", true);
        shader.setVec3("ambient", ambientColor);
        shader.setVec3("ambient_light", vec3(1.0, 0.8, 0.8));
        shader.setVec3("light_color", vec3(0.1, 0.1, 0.1));
        shader.setVec3("light_dir", vec3(10.0, 10.0, 2.0));

        // PBR shader
        shader.setVec3("lightPosition", vec3(state.camera.movement.transform.translation.x + 50.0, state.camera.movement.transform.translation.y + 50.0, state.camera.movement.transform.translation.z + 50.0));
        shader.setVec3("lightColor", vec3(1.0, 1.0, 1.0));
        shader.setFloat("lightIntensity", 100.0);

        shader.setVec3("viewPosition", state.camera.movement.transform.translation);

        // Add custom debug values when debug is enabled (for both regular debug and screenshot)
        if (state.shader_debug_enabled or capture_screenshot) {
            var buf_temp: [64]u8 = undefined;
            shader.addDebugValue("camera_position", std.fmt.bufPrint(&buf_temp, "Vec3({d:.3}, {d:.3}, {d:.3})", .{ state.camera.movement.transform.translation.x, state.camera.movement.transform.translation.y, state.camera.movement.transform.translation.z }) catch "error");
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

        // model.draw(shader);
        current_scope.getModel().draw(shader, 1);
        gl_debug.check("model pass");

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

        // Draw UI overlay
        ui_state.draw(current_scope.getModel());
        gl_debug.check("ui pass");

        //try core.dumpModelNodes(model);
        window.swapBuffers();

        //break;
    }

    std.debug.print("\nRun completed.\n\n", .{});

    shader.deleteGlObjects();
    ui_state.deinit();
    common_arenas.deinit();
    model_scope_a.deinit();
    model_scope_b.deinit();
}
