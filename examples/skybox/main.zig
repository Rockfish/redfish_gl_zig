const std = @import("std");
const glfw = @import("zglfw");
const zopengl = @import("zopengl");
const gl = @import("zopengl").bindings;
const core = @import("core");
const math = @import("math");
// const cube = @import("cube.zig");
const Skybox = @import("skybox.zig").Skybox;

const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const vec3 = math.vec3;
const vec4 = math.vec4;
const Mat4 = math.Mat4;
const Quat = math.Quat;

const Allocator = std.mem.Allocator;

const Input = core.Input;
const Camera = core.Camera;
const Shader = core.Shader;
const Texture = core.texture.Texture;
const TextureConfig = core.texture.TextureConfig;
const TextureFilter = core.texture.TextureFilter;
const TextureWrap = core.texture.TextureWrap;

const Window = glfw.Window;

const SCR_WIDTH: f32 = 1000.0;
const SCR_HEIGHT: f32 = 1000.0;

const SIZE_OF_FLOAT = @sizeOf(f32);
const SIZE_OF_VEC3 = @sizeOf(Vec3);
const SIZE_OF_VEC4 = @sizeOf(Vec4);
const SIZE_OF_QUAT = @sizeOf(Quat);

const State = struct {
    camera: *Camera,
    input: *Input,
    light_postion: Vec3,
    delta_time: f32,
    last_frame: f32,
    first_mouse: bool,
    last_x: f32,
    last_y: f32,
    scr_width: f32 = SCR_WIDTH,
    scr_height: f32 = SCR_HEIGHT,
};

var state: State = undefined;

pub fn main() !void {
    try glfw.init();
    defer glfw.terminate();

    const gl_major = 4;
    const gl_minor = 0;
    glfw.windowHint(.context_version_major, gl_major);
    glfw.windowHint(.context_version_minor, gl_minor);
    glfw.windowHint(.opengl_profile, .opengl_core_profile);
    glfw.windowHint(.client_api, .opengl_api);
    glfw.windowHint(.doublebuffer, true);
    glfw.windowHint(.opengl_forward_compat, true);

    const window = try glfw.Window.create(
        SCR_WIDTH,
        SCR_HEIGHT,
        "Skybox",
        null,
    );
    defer window.destroy();

    _ = window.setKeyCallback(keyHandler);
    _ = window.setFramebufferSizeCallback(framebufferSizeHandler);
    _ = window.setCursorPosCallback(cursorPositionHandler);
    _ = window.setScrollCallback(scrollHandler);

    glfw.makeContextCurrent(window);
    glfw.swapInterval(1);

    // tell GLFW to capture our mouse
    // glfw.setInputMode(window, .cursor, .cursor_disabled); // ?

    try zopengl.loadCoreProfile(glfw.getProcAddress, gl_major, gl_minor);

    try run(window);
}

pub fn run(window: *glfw.Window) !void {
    const window_size = window.getSize();
    const window_scale = window.getContentScale();
    const viewport_width = @as(f32, @floatFromInt(window_size[0])) * window_scale[0];
    const viewport_height = @as(f32, @floatFromInt(window_size[1])) * window_scale[1];
    const scaled_width = viewport_width / window_scale[0];
    const scaled_height = viewport_height / window_scale[1];

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();

    const allocator = arena.allocator();
    core.string.init(allocator);

    gl.enable(gl.DEPTH_TEST);

    const camera = try Camera.init(
        allocator,
        .{
            .position = vec3(0.0, 0.0, 3.0),
            .target = vec3(0.0, 0.0, 0.0),
            .scr_width = scaled_width,
            .scr_height = scaled_height,
        },
    );
    defer camera.deinit();

    state = State{
        .camera = camera,
        .input = Input.init(window),
        .light_postion = vec3(1.2, 1.0, 2.0),
        .delta_time = 0.0,
        .last_frame = 0.0,
        .first_mouse = true,
        .last_x = scaled_width / 2.0,
        .last_y = scaled_height / 2.0,
    };

    const basic_shader = try Shader.init(
        allocator,
        "examples/skybox/basic.vert",
        "examples/skybox/basic.frag",
    );
    defer basic_shader.deinit();

    const skybox_shader = try Shader.init(
        allocator,
        "examples/skybox/skybox.vert",
        "examples/skybox/skybox.frag",
    );
    defer skybox_shader.deinit();

    // const cubeVAO = cube.initCube();
    //
    // const cube_texture = try Texture.initFromFile(
    //     &arena,
    //     "assets/textures/container.jpg",
    //     .{
    //         .filter = .Linear,
    //         .flip_v = true,
    //         .gamma_correction = false,
    //         .wrap = .Clamp,
    //     },
    // );
    // defer cube_texture.deleteGlTexture();

    const cubemap_texture = try core.texture.Texture.initFromFile(
        allocator,
        "assets/Textures/cubemap_template_2x3.png",
        .{
            .flip_v = false,
            .gamma_correction = false,
            .filter = .Linear,
            .wrap = .Clamp,
        },
    );

    const cube = try core.shapes.createCube(allocator, .{
        .width = 1.0,
        .height = 1.0,
        .depth = 1.0,
        .num_tiles_x = 1.0,
        .num_tiles_y = 1.0,
        .num_tiles_z = 1.0,
        .texture_mapping = .Cubemap2x3,
    });
    defer allocator.destroy(cube);
    defer cube.deinit();

    const skybox = Skybox.init(allocator, .{
        .right = "assets/textures/skybox/right.jpg",
        .left = "assets/textures/skybox/left.jpg",
        .top = "assets/textures/skybox/top.jpg",
        .bottom = "assets/textures/skybox/bottom.jpg",
        .front = "assets/textures/skybox/front.jpg",
        .back = "assets/textures/skybox/back.jpg",
    });
    defer skybox.deinit();

    skybox_shader.setInt("skybox", 0);

    const projection = state.camera.getProjection();
    basic_shader.setMat4("projection", &projection);
    skybox_shader.setMat4("projection", &projection);

    // draw loop
    // -----------
    while (!window.shouldClose()) {
        const currentFrame: f32 = @floatCast(glfw.getTime());
        state.delta_time = currentFrame - state.last_frame;
        state.last_frame = currentFrame;

        processKeys();

        gl.clearColor(0.1, 0.1, 0.1, 1.0);
        gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

        const model = Mat4.Identity;
        const view = camera.getView();

        basic_shader.setMat4("model", &model);
        basic_shader.setMat4("view", &view);
        basic_shader.bindTextureAuto("textureDiffuse", cubemap_texture.gl_texture_id);

        cube.draw(basic_shader);

        skybox_shader.setMat4("view", &view.removeTranslation());
        skybox.draw();

        window.swapBuffers();
        glfw.pollEvents();
    }

    glfw.terminate();
}

pub fn keyHandler(window: *glfw.Window, key: glfw.Key, scancode: i32, action: glfw.Action, mods: glfw.Mods) callconv(.c) void {
    _ = scancode;

    state.input.handleKey(@enumFromInt(@intFromEnum(key)), @enumFromInt(@intFromEnum(action)), @bitCast(mods));

    if (key == .escape) {
        window.setShouldClose(true);
    }
}

pub fn processKeys() void {
    var iterator = state.input.key_presses.iterator();
    while (iterator.next()) |k| {
        switch (k) {
            .t => std.debug.print("time: {d}\n", .{state.delta_time}),
            .w => state.camera.movement.processMovement(.forward, state.delta_time),
            .s => state.camera.movement.processMovement(.backward, state.delta_time),
            .a => state.camera.movement.processMovement(.left, state.delta_time),
            .d => state.camera.movement.processMovement(.right, state.delta_time),
            .up => state.camera.movement.processMovement(.circle_up, state.delta_time),
            .down => state.camera.movement.processMovement(.circle_down, state.delta_time),
            .left => state.camera.movement.processMovement(.circle_left, state.delta_time),
            .right => state.camera.movement.processMovement(.circle_right, state.delta_time),
            else => {},
        }
    }
}

fn framebufferSizeHandler(window: *glfw.Window, width: i32, height: i32) callconv(.c) void {
    _ = window;
    gl.viewport(0, 0, width, height);
}

fn mouseHander(window: *glfw.Window, button: glfw.MouseButton, action: glfw.Action, mods: glfw.Mods) callconv(.c) void {
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

    const xoffset = xpos - state.last_x;
    const yoffset = state.last_y - ypos; // reversed since y-coordinates go from bottom to top

    state.last_x = xpos;
    state.last_y = ypos;

    state.camera.movement.processMouseMovement(xoffset, yoffset, true);
}

fn scrollHandler(window: *Window, xoffset: f64, yoffset: f64) callconv(.c) void {
    _ = window;
    _ = xoffset;
    state.camera.adjustFov(@floatCast(yoffset));
}
