const std = @import("std");
const glfw = @import("zglfw");
const zopengl = @import("zopengl");
const core = @import("core");
const math = @import("math");
const state_mod = @import("state.zig");
const input_handler = @import("scene/input_handler.zig");

const Scene = @import("scene/scene.zig").Scene;

const Vec3 = math.Vec3;
const vec3 = math.vec3;
const Vec4 = math.Vec4;
const Mat4 = math.Mat4;
const Quat = math.Quat;
const quat = math.quat;

const gl = zopengl.bindings;
const Input = core.Input;
const Camera = core.CameraGimbal;
const Shader = core.Shader;
const Skybox = core.shapes.Skybox;
const Transform = core.Transform;

const State = state_mod.State;

const log = std.log.scoped(.BulletsApp);

pub fn run_app(window: *glfw.Window, max_duration: ?f32) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    // const allocator = arena.allocator();

    log.info("Starting simple bullets test app", .{});

    const window_size = window.getSize();
    const window_scale = window.getContentScale();
    const viewport_width = @as(f32, @floatFromInt(window_size[0])) * window_scale[0];
    const viewport_height = @as(f32, @floatFromInt(window_size[1])) * window_scale[1];
    const scaled_width = viewport_width / window_scale[0];
    const scaled_height = viewport_height / window_scale[1];

    var state = State{
        .viewport_width = viewport_width,
        .viewport_height = viewport_height,
        .scaled_width = scaled_width,
        .scaled_height = scaled_height,
        .window_scale = window_scale,
        // .light_position = vec3(10.0, 10.0, -30.0),
        .delta_time = 0.0,
        .total_time = 0.0,
        .world_point = null,
        .input = Input.init(scaled_width, scaled_height),
        .scene = try Scene.init(&arena, scaled_width, scaled_height),
    };

    input_handler._state = &state;
    input_handler.initWindowHandlers(window);

    const start_time: f32 = @floatCast(glfw.getTime());

    gl.enable(gl.DEPTH_TEST);
    gl.enable(gl.BLEND);

    log.info("Starting main loop", .{});

    var scene = &state.scene;

    std.debug.print("scene address: {X}\n", .{@intFromPtr(scene)});

    while (!window.shouldClose()) {
        const current_time: f32 = @floatCast(glfw.getTime());
        state.delta_time = current_time - state.total_time;
        state.total_time = current_time;

        if (max_duration) |duration| {
            if (current_time - start_time >= duration) {
                log.info("Reached maximum duration of {d} seconds, exiting", .{duration});
                break;
            }
        }

        glfw.pollEvents();
        input_handler.processInput();

        if (state.reset == true) {
            try scene.bullet_system.resetBullets(
                vec3(0.0, 0.0, 0.0),
                vec3(0.0, 1.0, 0.0),
                1.0,
                -55.0,
                -55.0,
            );
            state.reset = false;
        }

        if (state.run_animation == true) {
            scene.bullet_system.update(state.delta_time);
        }

        var camera = scene.getCamera();
        const projection = camera.getProjection();
        const view = camera.getView();

        clearWindow();

        // scene.drawCube(&projection, &view);

        scene.drawAxis(&projection, &view);

        scene.drawBullets(&projection, &view);

        // scene.drawSkybox(&projection, &view);

        scene.drawFloor(&projection, &view);

        window.swapBuffers();
    }

    log.info("Simple bullets test app completed", .{});
}

pub fn clearWindow() void {
    gl.clearColor(0.0, 0.0, 0.0, 1.0);
    gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
    gl.disable(gl.BLEND);
    gl.enable(gl.CULL_FACE);
}
