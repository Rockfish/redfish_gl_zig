const std = @import("std");
const glfw = @import("zglfw");
const zopengl = @import("zopengl");
const core = @import("core");
const world_module = @import("world.zig");

const gl = zopengl.bindings;
const Input = core.Input;
const World = world_module.World;

const log = std.log.scoped(.BulletsApp);

pub fn run_app(window: *glfw.Window, max_duration: ?f32) !void {
    var root_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = root_allocator.deinit();

    log.info("Starting simple bullets test app", .{});
    const input = Input.init(window);

    const world = try World.init(root_allocator.allocator(), input);
    defer world.deinit();

    gl.enable(gl.DEPTH_TEST);
    gl.enable(gl.BLEND);

    log.info("Starting main loop", .{});

    while (!window.shouldClose()) {
        glfw.pollEvents();
        input.update();

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
