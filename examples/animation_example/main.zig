const std = @import("std");
const glfw = @import("zglfw");
const zopengl = @import("zopengl");
const zstbi = @import("zstbi");
const core = @import("core");
const math = @import("math");

const gl = zopengl.bindings;

const Model = core.Model;
const GltfAsset = core.asset_loader.GltfAsset;
const TextureConfig = core.asset_loader.TextureConfig;
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

// Model selection flag for testing
const USE_CESIUM_MAN: bool = true; // Set to true to test CesiumMan.gltf, false for Player.gltf

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

pub fn main() !void {
    var buf: [512]u8 = undefined;
    const cwd = try std.fs.selfExeDirPath(&buf);
    std.debug.print("Running sample_animation. cwd = {s}\n", .{cwd});

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

    try run(allocator, window);
}

pub fn run(allocator: std.mem.Allocator, window: *glfw.Window) !void {
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
    );

    std.debug.print("Shader id: {d}\n", .{shader.id});

    // const lightDir: Vec3 = vec3(-0.8, 0.0, -1.0).normalize_or_zero();
    // const playerLightDir: Vec3 = vec3(-1.0, -1.0, -1.0).normalize_or_zero();

    // const lightColor: Vec3 = LIGHT_FACTOR * 1.0 * vec3(NON_BLUE * 0.406, NON_BLUE * 0.723, 1.0);
    // const lightColor: Vec3 = LIGHT_FACTOR * 1.0 * vec3(0.406, 0.723, 1.0);

    // const floorLightColor: Vec3 = FLOOR_LIGHT_FACTOR * 1.0 * vec3(FLOOR_NON_BLUE * 0.406, FLOOR_NON_BLUE * 0.723, 1.0);
    // const floorAmbientColor: Vec3 = FLOOR_LIGHT_FACTOR * 0.50 * vec3(FLOOR_NON_BLUE * 0.7, FLOOR_NON_BLUE * 0.7, 0.7);

    const ambientColor: Vec3 = vec3(NON_BLUE * 0.7, NON_BLUE * 0.7, 0.7);

    // Select model based on flag
    const model_path = if (USE_CESIUM_MAN) "glTF-Sample-Models/CesiumMan/glTF/CesiumMan.gltf" else "angrybots_assets/Models/Player/Player.gltf";
    const model_name = if (USE_CESIUM_MAN) "CesiumMan" else "Player";

    std.debug.print("Main: loading model: {s}\n", .{model_path});

    // Create glTF asset and load model
    var gltf_asset = try GltfAsset.init(allocator, model_name, model_path);
    try gltf_asset.load();

    // Define texture configuration (same settings as ASSIMP version)
    const texture_config = TextureConfig{ .filter = .Linear, .flip_v = true, .gamma_correction = false, .wrap = .Clamp };

    std.debug.print("Main: adding custom textures\n", .{});
    if (USE_CESIUM_MAN) {
        // Add test textures for CesiumMan to test custom texture system
        try gltf_asset.addTexture("Cesium_Man", "texture_diffuse", "Textures/Player_D.tga", texture_config);
        try gltf_asset.addTexture("Cesium_Man", "texture_specular", "Textures/Player_M.tga", texture_config);
        try gltf_asset.addTexture("Cesium_Man", "texture_emissive", "Textures/Player_E.tga", texture_config);
        try gltf_asset.addTexture("Cesium_Man", "texture_normal", "Textures/Player_NRM.tga", texture_config);
    } else {
        // Player model custom textures
        try gltf_asset.addTexture("Player", "texture_diffuse", "Textures/Player_D.tga", texture_config);
        try gltf_asset.addTexture("Player", "texture_specular", "Textures/Player_M.tga", texture_config);
        try gltf_asset.addTexture("Player", "texture_emissive", "Textures/Player_E.tga", texture_config);
        try gltf_asset.addTexture("Player", "texture_normal", "Textures/Player_NRM.tga", texture_config);
        try gltf_asset.addTexture("Gun", "texture_diffuse", "Textures/Gun_D.tga", texture_config);
        try gltf_asset.addTexture("Gun", "texture_specular", "Textures/Gun_M.tga", texture_config);
        try gltf_asset.addTexture("Gun", "texture_emissive", "Textures/Gun_E.tga", texture_config);
        try gltf_asset.addTexture("Gun", "texture_normal", "Textures/Gun_NRM.tga", texture_config);
    }

    std.debug.print("Main: building model: {s}\n", .{model_path});
    var model = try gltf_asset.buildModel();

    // Generate report if enabled
    if (DUMP_REPORT) {
        std.debug.print("Generating glTF report to: {s}\n", .{REPORT_PATH});
        const GltfReport = core.gltf_report.GltfReport;
        try GltfReport.writeDetailedReportToFile(allocator, gltf_asset, REPORT_PATH, 5, 5);
        std.debug.print("Report generated successfully\n", .{});
    }

    const bullet_model_path = "angrybots_assets/Models/Bullet/Bullet.gltf";
    var bullet_gltf_asset = try GltfAsset.init(allocator, "bullet", bullet_model_path);
    try bullet_gltf_asset.load();
    bullet_gltf_asset.skipModelTextures();

    // Add custom texture for bullet
    try bullet_gltf_asset.addTexture("Plane001", "texture_diffuse", "Floor D.png", texture_config);
    var bullet_model = try bullet_gltf_asset.buildModel();

    defer {
        bullet_model.deinit();
        // gltf_asset.cleanUp();
        // bullet_gltf_asset.cleanUp();
    }

    // const idle = AnimationClip.new(55.0, 130.0, AnimationRepeat.Forever);
    // const forward = AnimationClip.new(134.0, 154.0, AnimationRepeat.Forever);
    // const backwards = AnimationClip.new(159.0, 179.0, AnimationRepeat.Forever);
    // const right = AnimationClip.new(184.0, 204.0, AnimationRepeat.Forever);
    // const left = AnimationClip.new(209.0, 229.0, AnimationRepeat.Forever);
    // const dying = AnimationClip.new(234.0, 293.0, AnimationRepeat.Once);

    std.debug.print("Main: playClip\n", .{});
    // try model.playClip(idle);
    // try model.play_clip_with_transition(forward, 6);
    // try model.playClip(forward);
    std.debug.print("animation state: {any}\n", .{model.animator.current_animation});

    // --- event loop
    state.last_frame = @floatCast(glfw.getTime());
    var frame_counter = FrameCounter.new();

    _ = window.setKeyCallback(keyHandler);
    _ = window.setFramebufferSizeCallback(framebufferSizeHandler);
    _ = window.setCursorPosCallback(cursorPositionHandler);
    _ = window.setScrollCallback(scrollHandler);

    while (!window.shouldClose()) {
        const currentFrame: f32 = @floatCast(glfw.getTime());
        state.delta_time = currentFrame - state.last_frame;
        state.last_frame = currentFrame;

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

        var model_transform = Mat4.identity();
        model_transform.translate(&vec3(0.0, 1.0, -2.0));
        model_transform.scale(&vec3(1.0, 1.0, 1.0));

        shader.setMat4("projection", &projection);
        shader.setMat4("view", &view);
        shader.setMat4("model", &model_transform);

        shader.setBool("useLight", true);
        shader.setVec3("ambient", &ambientColor);

        const identity = Mat4.identity();
        shader.setMat4("aimRot", &identity);
        shader.setMat4("lightSpaceMatrix", &identity);

        // std.debug.print("Main: render\n", .{});
        try model.update_animation(state.delta_time);
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

fn keyHandler(window: *glfw.Window, key: glfw.Key, scancode: i32, action: glfw.Action, mods: glfw.Mods) callconv(.C) void {
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
            state.camera.movement.processMovement(.Forward, state.delta_time);
        },
        .s => {
            state.camera.movement.processMovement(.Backward, state.delta_time);
        },
        .a => {
            state.camera.movement.processMovement(.CircleLeft, state.delta_time);
        },
        .d => {
            state.camera.movement.processMovement(.CircleRight, state.delta_time);
        },
        else => {},
    }
}

fn framebufferSizeHandler(window: *glfw.Window, width: i32, height: i32) callconv(.C) void {
    _ = window;
    gl.viewport(0, 0, width, height);
}

fn mouseHander(window: *glfw.Window, button: glfw.MouseButton, action: glfw.Action, mods: glfw.Mods) callconv(.C) void {
    _ = window;
    _ = button;
    _ = action;
    _ = mods;
}

fn cursorPositionHandler(window: *glfw.Window, xposIn: f64, yposIn: f64) callconv(.C) void {
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

fn scrollHandler(window: *Window, xoffset: f64, yoffset: f64) callconv(.C) void {
    _ = window;
    _ = xoffset;
    state.camera.adjustFov(@floatCast(yoffset));
}
