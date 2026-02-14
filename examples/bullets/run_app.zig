const std = @import("std");
const glfw = @import("zglfw");
const zopengl = @import("zopengl");
const core = @import("core");
const math = @import("math");
const world_module = @import("world.zig");

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

const World = world_module.World;

const log = std.log.scoped(.BulletsApp);

pub fn run_app(window: *glfw.Window, max_duration: ?f32) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();

    log.info("Starting simple bullets test app", .{});
    const input = Input.init(window);

    var world = try World.init(allocator, input);

    gl.enable(gl.DEPTH_TEST);
    gl.enable(gl.BLEND);

    log.info("Starting main loop", .{});

    while (!window.shouldClose()) {
        input.update();
        glfw.pollEvents();

        if (max_duration) |duration| {
            if (input.total_time >= duration) {
                log.info("Reached maximum duration of {d} seconds, exiting", .{duration});
                break;
            }
        }

        clearWindow();

        try world.scene.update(input);

        world.scene.draw();

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
