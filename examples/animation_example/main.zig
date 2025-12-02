const std = @import("std");
const glfw = @import("zglfw");
const zopengl = @import("zopengl");
const zstbi = @import("zstbi");
const core = @import("core");
const math = @import("math");
const containers = @import("containers");

const gl = zopengl.bindings;

const Model = core.Model;
const GltfAsset = core.asset_loader.GltfAsset;
const TextureConfig = core.texture.TextureConfig;
const animation = core.animation;
const Camera = core.Camera;
const Shader = core.Shader;
const String = core.string.String;
const FrameCounter = core.FrameCounter;

const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const vec2 = math.vec2;
const vec3 = math.vec3;
const Mat4 = math.Mat4;
const Quat = math.Quat;

const Texture = core.texture.Texture;
const Animator = animation.Animator;
const AnimationClip = animation.AnimationClip;
const AnimationRepeat = animation.AnimationRepeatMode;

const Window = glfw.Window;

const SCR_WIDTH: f32 = 800.0;
const SCR_HEIGHT: f32 = 800.0;

// Model selection for testing
const ModelChoice = enum {
    cesium_man,
    player,
    spacesuit,
    securitybot,
    interpolation_test,
};

// Report dumping configuration
const DUMP_REPORT: bool = true; // Set to true to generate model report
const REPORT_PATH: []const u8 = "model_report.md"; // Output file path

// Lighting
const LIGHT_FACTOR: f32 = 1.0;
const NON_BLUE: f32 = 0.9;

const FLOOR_LIGHT_FACTOR: f32 = 0.35;
const FLOOR_NON_BLUE: f32 = 0.7;

// Struct for passing state between the window loop and the event handler.
const State = struct {
    camera: *Camera,
    light_postion: Vec3,
    delta_time: f32,
    last_frame: f32,
    first_mouse: bool,
    last_x: f32,
    last_y: f32,
    scr_width: f32 = SCR_WIDTH,
    scr_height: f32 = SCR_HEIGHT,
    current_action: u8 = 0, // 0=idle, 1=forward, 2=backwards, 3=right, 4=left, 5=dying
    current_clip_index: usize = 0, // Index into player_clips array
    model: ?*Model = null, // Reference to the model for animation updates
};

const content_dir = "assets";

var state: State = undefined;

const V4 = struct {
    x: f32,
    y: f32,
    z: f32,
    w: f32,

    pub fn new(x: f32, y: f32, z: f32, w: f32) V4 {
        return .{ .x = x, .y = y, .z = z, .w = w };
    }
};

const TexConfigs = struct { mesh_name: []const u8, uniform_name: []const u8, texture_path: []const u8, config: TextureConfig };

const CameraPosition = struct {
    position: Vec3,
    target: Vec3,
};

const PlayerClip = struct {
    name: []const u8,
    clip: AnimationClip,
};

const fps: f32 = 30.0;

// Player animation clips from game_angrybot/player.zig
const player_clips = [_]PlayerClip{
    .{ .name = "idle", .clip = AnimationClip.init(0, 55.0 / fps, 130.0 / fps, AnimationRepeat.Forever) },
    .{ .name = "right", .clip = AnimationClip.init(0, 184.0 / fps, 204.0 / fps, AnimationRepeat.Forever) },
    .{ .name = "forward", .clip = AnimationClip.init(0, 134.0 / fps, 154.0 / fps, AnimationRepeat.Forever) },
    .{ .name = "back", .clip = AnimationClip.init(0, 159.0 / fps, 179.0 / fps, AnimationRepeat.Forever) },
    .{ .name = "left", .clip = AnimationClip.init(0, 209.0 / fps, 229.0 / fps, AnimationRepeat.Forever) },
    .{ .name = "dead", .clip = AnimationClip.init(0, 234.0 / fps, 293.0 / fps, AnimationRepeat.Once) },
};

const ModelConfig = struct {
    choice: ModelChoice,
    path: []const u8,
    name: []const u8,
    transform: Mat4,
    addTextures: []const TexConfigs,
    animationClip: ?AnimationClip = null,
    animationPlayAll: bool = false, // If true, play all animations in the model
    cameraPosition: ?CameraPosition = null,
};

// Define texture configuration (same settings as ASSIMP version)
const texture_config = TextureConfig{ .filter = .Linear, .flip_v = true, .gamma_correction = false, .wrap = .Clamp };

// Model configurations - consolidated from all switch statements
const model_configs = [_]ModelConfig{
    // CesiumMan configuration
    .{
        .choice = .cesium_man,
        .path = "BrainStem_converted.gltf",
        .name = "CesiumMan",
        .transform = blk: {
            var transform = Mat4.identity();
            transform.translate(&vec3(0.0, 0.0, -1.0));
            transform.scale(&vec3(1.0, 1.0, 1.0));
            break :blk transform;
        },
        .addTextures = &[_]TexConfigs{
            .{ .mesh_name = "Cesium_Man", .uniform_name = "texture_diffuse", .texture_path = "CesiumMan_img0.jpg", .config = texture_config },
        },
        .animationClip = AnimationClip.init(0, 0.042, 2.0, AnimationRepeat.Forever),
        .cameraPosition = null,
    },
    // Player configuration
    .{
        .choice = .player,
        .path = "angrybots_assets/Models/Player/Player.gltf",
        .name = "Player",
        .transform = blk: {
            var transform = Mat4.identity();
            transform.scale(&vec3(0.1, 0.1, 0.1));
            break :blk transform;
        },
        .addTextures = &[_]TexConfigs{
            .{ .mesh_name = "Player", .uniform_name = "texture_diffuse", .texture_path = "Textures/Player_D.tga", .config = texture_config },
            .{ .mesh_name = "Player", .uniform_name = "texture_specular", .texture_path = "Textures/Player_M.tga", .config = texture_config },
            .{ .mesh_name = "Player", .uniform_name = "texture_emissive", .texture_path = "Textures/Player_E.tga", .config = texture_config },
            .{ .mesh_name = "Player", .uniform_name = "texture_normal", .texture_path = "Textures/Player_NRM.tga", .config = texture_config },
            .{ .mesh_name = "Gun", .uniform_name = "texture_diffuse", .texture_path = "Textures/Gun_D.tga", .config = texture_config },
            .{ .mesh_name = "Gun", .uniform_name = "texture_specular", .texture_path = "Textures/Gun_M.tga", .config = texture_config },
            .{ .mesh_name = "Gun", .uniform_name = "texture_emissive", .texture_path = "Textures/Gun_E.tga", .config = texture_config },
            .{ .mesh_name = "Gun", .uniform_name = "texture_normal", .texture_path = "Textures/Gun_NRM.tga", .config = texture_config },
        },
        .animationClip = AnimationClip.init(0, 0.0, 294.0 / 30.0, AnimationRepeat.Forever),
        .cameraPosition = CameraPosition{ .position = vec3(0.0, 10.0, 30.0), .target = vec3(0.0, 10.0, 0.0) },
    },
    // Spacesuit configuration
    .{
        .choice = .spacesuit,
        .path = "angrybots_assets/Models/Player/Spacesuit.gltf",
        .name = "Spacesuit",
        .transform = blk: {
            var transform = Mat4.identity();
            transform.scale(&vec3(0.5, 0.5, 0.5));
            break :blk transform;
        },
        .addTextures = &[_]TexConfigs{},
        .animationClip = AnimationClip.init(13, 0.0, 32.0 / 30.0, AnimationRepeat.Forever),
        .cameraPosition = CameraPosition{ .position = vec3(0.0, 20.0, 80.0), .target = vec3(0.0, 10.0, 0.0) },
    },
    // Security Bot configuration
    .{
        .choice = .securitybot,
        .path = "angrybots_assets/security_bot_7/scene.gltf",
        .name = "Security_Bot",
        .transform = Mat4.identity(),
        .addTextures = &[_]TexConfigs{},
        .animationClip = null,
        .cameraPosition = null,
    },
    // InterpolationTest configuration
    .{
        .choice = .interpolation_test,
        .path = "glTF-Sample-Models/InterpolationTest/glTF/InterpolationTest.gltf",
        .name = "InterpolationTest",
        .transform = Mat4.identity(),
        .addTextures = &[_]TexConfigs{},
        .animationClip = AnimationClip.init(0, 0.0, 5.0, AnimationRepeat.Forever),
        .animationPlayAll = true,
        .cameraPosition = null,
    },
};

// glTF-Sample-Models/InterpolationTest/glTF/InterpolationTest.gltf

// Select model based on enum
const SELECTED_MODEL: ModelChoice = .player;

pub fn main() !void {
    var buf: [512]u8 = undefined;
    const cwd = try std.fs.selfExeDirPath(&buf);
    std.debug.print("Running sample_animation. cwd = {s}\n", .{cwd});

    // Parse command line arguments
    var args = std.process.args();
    _ = args.skip(); // Skip program name
    var runtime_duration: ?f32 = null;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--duration") or std.mem.eql(u8, arg, "-d")) {
            if (args.next()) |duration_str| {
                runtime_duration = std.fmt.parseFloat(f32, duration_str) catch |err| {
                    std.debug.print("Invalid duration: {s}, error: {}\n", .{ duration_str, err });
                    std.process.exit(1);
                };
                std.debug.print("Runtime duration set to: {d} seconds\n", .{runtime_duration.?});
            } else {
                std.debug.print("Error: --duration requires a value\n", .{});
                std.process.exit(1);
            }
        }
    }

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    core.string.init(allocator);

    try glfw.init();
    defer glfw.terminate();

    const gl_major = 4;
    const gl_minor = 0;
    glfw.windowHint(.context_version_major, gl_major);
    glfw.windowHint(.context_version_minor, gl_minor);
    glfw.windowHint(.opengl_profile, .opengl_core_profile);
    glfw.windowHint(.client_api, .opengl_api);
    glfw.windowHint(.doublebuffer, true);
    // For MacOS
    glfw.windowHint(.opengl_forward_compat, true);

    const window = try glfw.Window.create(600, 600, "Angry ", null);
    defer window.destroy();

    glfw.makeContextCurrent(window);
    glfw.swapInterval(1);

    try zopengl.loadCoreProfile(glfw.getProcAddress, gl_major, gl_minor);

    try run(allocator, window, runtime_duration);
}

pub fn run(allocator: std.mem.Allocator, window: *glfw.Window, max_duration: ?f32) !void {
    //var buffer: [1024]u8 = undefined;
    //const root_path = std.fs.selfExeDirPath(buffer[0..]) catch ".";
    //_ = root_path;

    const camera = try Camera.init(
        allocator,
        .{
            .position = vec3(0.0, 0.0, 5.0),
            .target = vec3(0.0, 0.0, 0.0),
            .scr_width = SCR_WIDTH,
            .scr_height = SCR_HEIGHT,
        },
    );

    // const debug_camera = try Camera.camera_vec3(allocator, vec3(0.0, 40.0, 120.0));
    // defer debug_camera.deinit();

    // Initialize the world state
    state = State{
        .camera = camera,
        .light_postion = vec3(1.2, 1.0, 2.0),
        .delta_time = 0.0,
        .last_frame = 0.0,
        .first_mouse = true,
        .last_x = SCR_WIDTH / 2.0,
        .last_y = SCR_HEIGHT / 2.0,
    };

    gl.enable(gl.DEPTH_TEST);

    const shader = try Shader.init(
        allocator,
        "examples/animation_example/player_shader.vert",
        "examples/animation_example/player_shader.frag",
        // "examples/animation_example/pbr.vert",
        // "examples/animation_example/pbr.frag",
    );

    std.debug.print("Shader id: {d}\n", .{shader.id});

    // const lightDir: Vec3 = vec3(-0.8, 0.0, -1.0).normalize_or_zero();
    // const playerLightDir: Vec3 = vec3(-1.0, -1.0, -1.0).normalize_or_zero();

    // const lightColor: Vec3 = LIGHT_FACTOR * 1.0 * vec3(NON_BLUE * 0.406, NON_BLUE * 0.723, 1.0);
    // const lightColor: Vec3 = LIGHT_FACTOR * 1.0 * vec3(0.406, 0.723, 1.0);

    // const floorLightColor: Vec3 = FLOOR_LIGHT_FACTOR * 1.0 * vec3(FLOOR_NON_BLUE * 0.406, FLOOR_NON_BLUE * 0.723, 1.0);
    // const floorAmbientColor: Vec3 = FLOOR_LIGHT_FACTOR * 0.50 * vec3(FLOOR_NON_BLUE * 0.7, FLOOR_NON_BLUE * 0.7, 0.7);

    const ambientColor: Vec3 = vec3(NON_BLUE * 0.7, NON_BLUE * 0.7, 0.7);

    // Find the configuration for the selected model
    const model_config = blk: {
        for (model_configs) |config| {
            if (config.choice == SELECTED_MODEL) {
                break :blk config;
            }
        }
        @panic("No configuration found for selected model");
    };

    const model_path = model_config.path;
    const model_name = model_config.name;

    std.debug.print("Main: loading model: {s}\n", .{model_path});

    // Create glTF asset and load model
    var gltf_asset = try GltfAsset.init(allocator, model_name, model_path);
    try gltf_asset.load();

    // Apply model configuration
    const model_transform = model_config.transform;

    // Apply camera position if specified
    if (model_config.cameraPosition) |cam_pos| {
        state.camera.movement.reset(cam_pos.position, cam_pos.target);
    }

    std.debug.print("Main: adding custom textures\n", .{});
    // Apply textures from configuration
    for (model_config.addTextures) |texture_config_item| {
        try gltf_asset.addTexture(
            texture_config_item.mesh_name,
            texture_config_item.uniform_name,
            texture_config_item.texture_path,
            texture_config_item.config,
        );
    }

    std.debug.print("Main: building model: {s}\n", .{model_path});
    var model = try gltf_asset.buildModel();

    // Generate report if enabled
    if (DUMP_REPORT) {
        std.debug.print("Generating glTF report to: {s}\n", .{REPORT_PATH});
        const GltfReport = core.gltf_report.GltfReport;
        try GltfReport.writeDetailedReportToFile(
            allocator,
            gltf_asset,
            REPORT_PATH,
            5,
            5,
        );
        std.debug.print("Report generated successfully\n", .{});
    }

    const bullet_model_path = "angrybots_assets/Models/Bullet/Bullet.gltf";

    var bullet_gltf_asset = try GltfAsset.init(allocator, "bullet", bullet_model_path);
    try bullet_gltf_asset.load();

    bullet_gltf_asset.skipModelTextures();

    // Add custom texture for bullet
    try bullet_gltf_asset.addTexture(
        "Plane001",
        "texture_diffuse",
        "Floor D.png",
        texture_config,
    );
    var bullet_model = try bullet_gltf_asset.buildModel();

    defer {
        bullet_model.deinit();
    }

    std.debug.print("Main: configuring animation\n", .{});

    // Store model reference for key handler
    state.model = model;

    // Apply animation from configuration
    if (model_config.animationPlayAll) {
        std.debug.print("Model configured for multi-animation - playing all animations simultaneously\n", .{});
        try model.playAllAnimations();
    } else if (SELECTED_MODEL == .player) {
        // For player model, use the first clip from our array
        const initial_clip = player_clips[state.current_clip_index];
        std.debug.print("Playing player animation clip: {s} (start: {d:.3}, end: {d:.3})\n", .{ initial_clip.name, initial_clip.clip.start_time, initial_clip.clip.end_time });
        try model.animator.playClip(initial_clip.clip);
    } else if (model_config.animationClip) |animation_clip| {
        std.debug.print("Playing single animation clip\n", .{});
        try model.animator.playClip(animation_clip);
    }

    std.debug.print(
        "animation state: active_animations={d}\n",
        .{model.animator.active_animations.list.items.len},
    );

    // --- event loop
    state.last_frame = @floatCast(glfw.getTime());
    var frame_counter = FrameCounter.new();

    _ = window.setKeyCallback(keyHandler);
    _ = window.setFramebufferSizeCallback(framebufferSizeHandler);
    _ = window.setCursorPosCallback(cursorPositionHandler);
    _ = window.setScrollCallback(scrollHandler);

    const start_time = state.last_frame;

    while (!window.shouldClose()) {
        const currentFrame: f32 = @floatCast(glfw.getTime());
        state.delta_time = currentFrame - state.last_frame;
        state.last_frame = currentFrame;

        // Check if we've exceeded the maximum duration
        if (max_duration) |duration| {
            if (currentFrame - start_time >= duration) {
                std.debug.print("Reached maximum duration of {d} seconds, exiting\n", .{duration});
                break;
            }
        }

        frame_counter.update();

        glfw.pollEvents();

        gl.clearColor(0.05, 0.1, 0.05, 1.0);
        gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

        const projection = Mat4.perspectiveRhGl(
            std.math.degreesToRadians(camera.fov),
            SCR_WIDTH / SCR_HEIGHT,
            0.1,
            1000.0,
        );
        const view = state.camera.getLookToView();

        shader.setMat4("matProjection", &projection);
        shader.setMat4("matView", &view);
        shader.setMat4("matModel", &model_transform);

        shader.setBool("useLight", true);
        shader.setVec3("ambient", &ambientColor);

        const identity = Mat4.identity();
        shader.setMat4("aimRot", &identity);
        shader.setMat4("matLightSpace", &identity);

        // std.debug.print("Main: render\n", .{});
        try model.updateAnimation(state.delta_time);
        // try model.playTick(140.0);
        model.render(shader);
        // try core.dumpModelNodes(model);

        // const bulletTransform = Mat4.fromScale(&vec3(2.0, 2.0, 2.0));
        //
        // shader.setMat4("model", &bulletTransform);
        // bullet_model.render(shader);

        window.swapBuffers();

        //break;
    }

    std.debug.print("\nRun completed.\n\n", .{});

    shader.deinit();
    camera.deinit();
    model.deinit();
    // Texture cleanup is handled by GltfAsset.cleanUp() in defer block
}

fn keyHandler(
    window: *glfw.Window,
    key: glfw.Key,
    scancode: i32,
    action: glfw.Action,
    mods: glfw.Mods,
) callconv(.c) void {
    _ = scancode;
    _ = mods;
    switch (key) {
        .escape => {
            window.setShouldClose(true);
        },
        .t => {
            if (action == glfw.Action.press) {
                std.debug.print("time: {d}\n", .{state.delta_time});
            }
        },
        .w => {
            state.camera.movement.processMovement(.forward, state.delta_time);
        },
        .s => {
            state.camera.movement.processMovement(.backward, state.delta_time);
        },
        .a => {
            state.camera.movement.processMovement(.circle_left, state.delta_time);
        },
        .d => {
            state.camera.movement.processMovement(.circle_right, state.delta_time);
        },
        .n => {
            if (action == glfw.Action.press) {
                if (SELECTED_MODEL == .player and state.model != null) {
                    state.current_clip_index = (state.current_clip_index + 1) % player_clips.len;
                    const current_clip = player_clips[state.current_clip_index];
                    std.debug.print("Switching to animation clip: {s} (start: {d:.3}, end: {d:.3})\n", .{ current_clip.name, current_clip.clip.start_time, current_clip.clip.end_time });
                    state.model.?.animator.playClip(current_clip.clip) catch |err| {
                        std.debug.print("Failed to play animation clip: {}\n", .{err});
                    };
                }
            }
        },
        else => {},
    }
}

fn framebufferSizeHandler(window: *glfw.Window, width: i32, height: i32) callconv(.c) void {
    _ = window;
    gl.viewport(0, 0, width, height);
}

fn mouseHander(
    window: *glfw.Window,
    button: glfw.MouseButton,
    action: glfw.Action,
    mods: glfw.Mods,
) callconv(.c) void {
    _ = window;
    _ = button;
    _ = action;
    _ = mods;
}

fn cursorPositionHandler(window: *glfw.Window, xposIn: f64, yposIn: f64) callconv(.c) void {
    _ = window;
    var xpos: f32 = @floatCast(xposIn);
    var ypos: f32 = @floatCast(yposIn);

    xpos = if (xpos < 0) 0 else if (xpos < state.scr_width) xpos else state.scr_width;
    ypos = if (ypos < 0) 0 else if (ypos < state.scr_height) ypos else state.scr_height;

    if (state.first_mouse) {
        state.last_x = xpos;
        state.last_y = ypos;
        state.first_mouse = false;
    }

    // const xoffset = xpos - state.last_x;
    // const yoffset = state.last_y - ypos; // reversed since y-coordinates go from bottom to top

    state.last_x = xpos;
    state.last_y = ypos;

    // Mouse movement disabled for now
}

fn scrollHandler(window: *Window, xoffset: f64, yoffset: f64) callconv(.c) void {
    _ = window;
    _ = xoffset;
    state.camera.adjustFov(@floatCast(yoffset));
}
