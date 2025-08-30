const std = @import("std");
const glfw = @import("zglfw");
const zopengl = @import("zopengl");
const core = @import("core");
const math = @import("math");
const state_mod = @import("state.zig");
const simple_bullets = @import("simple_bullets.zig");

const gl = zopengl.bindings;
const Camera = core.Camera;
const Shader = core.Shader;

const Vec3 = math.Vec3;
const vec3 = math.vec3;
const Mat4 = math.Mat4;

const State = state_mod.State;
const SimpleBulletStore = simple_bullets.SimpleBulletStore;

const log = std.log.scoped(.BulletsApp);

var state: State = undefined;

pub fn run_simple(window: *glfw.Window, max_duration: ?f32) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    log.info("Starting simple bullets test app", .{});

    const window_size = window.getSize();
    const window_scale = window.getContentScale();
    const viewport_width = @as(f32, @floatFromInt(window_size[0])) * window_scale[0];
    const viewport_height = @as(f32, @floatFromInt(window_size[1])) * window_scale[1];
    const scaled_width = viewport_width / window_scale[0];
    const scaled_height = viewport_height / window_scale[1];

    // Initialize camera
    const camera = try Camera.init(
        allocator,
        .{
            .position = vec3(0.0, 5.0, 15.0),
            .target = vec3(0.0, 0.0, 0.0),
            .scr_width = scaled_width,
            .scr_height = scaled_height,
        },
    );
    defer camera.deinit();

    state = State{
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
        .camera_initial_position = vec3(0.0, 5.0, 15.0),
        .camera_initial_target = vec3(0.0, 0.0, 0.0),
        .input = .{
            .first_mouse = true,
            .mouse_x = scaled_width / 2.0,
            .mouse_y = scaled_height / 2.0,
            .key_presses = std.EnumSet(glfw.Key).initEmpty(),
            .key_processed = std.EnumSet(glfw.Key).initEmpty(),
        },
        .animation_id = -1,
        .current_model_index = 0,
    };

    state_mod.initWindowHandlers(window);

    const bullet_shader = try Shader.init(
        allocator,
        "examples/bullets/shaders/instanced_matrix.vert",
        "examples/bullets/shaders/basic_texture.frag",
    );
    defer bullet_shader.deinit();

    var bullet_store = SimpleBulletStore.init(allocator);
    defer bullet_store.deinit();

    const start_time: f32 = @floatCast(glfw.getTime());
    var last_bullet_time: f32 = 0.0;
    const bullet_fire_interval: f32 = 2.0; // Fire bullets every 2 seconds

    gl.enable(gl.DEPTH_TEST);

    log.info("Starting main loop", .{});

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
        state_mod.processKeys();

        if (current_time - last_bullet_time >= bullet_fire_interval) {
            const test_directions = [_]f32{ 0.0, math.pi / 4.0, math.pi / 2.0, 3.0 * math.pi / 4.0, math.pi };
            const direction_index = @mod(@as(usize, @intFromFloat(current_time)), test_directions.len);
            const aim_angle = test_directions[direction_index];

            try bullet_store.fireBulletPattern(vec3(0.0, 0.0, 0.0), aim_angle, 5);

            log.info("Fired bullet pattern at angle: {d:.2} radians ({d:.1} degrees)", .{ aim_angle, math.radiansToDegrees(aim_angle) });

            last_bullet_time = current_time;
        }

        bullet_store.update(state.delta_time);

        gl.clearColor(0.1, 0.1, 0.1, 1.0);
        gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

        state.view = state.camera.getViewMatrix();
        const projection_view = state.projection.mulMat4(&state.view);

        bullet_store.render(bullet_shader, &projection_view);

        window.swapBuffers();

        // Print bullet count for debugging
        if (@mod(@as(i32, @intFromFloat(current_time * 10)), 30) == 0) {
            log.info("Active bullets: {d}", .{bullet_store.bullets.items.len});
        }
    }

    log.info("Simple bullets test app completed", .{});
}
