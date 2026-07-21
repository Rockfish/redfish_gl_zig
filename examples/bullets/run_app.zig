const std = @import("std");
const glfw = @import("zglfw");
const zopengl = @import("zopengl");
const core = @import("core");
const world_module = @import("world.zig");

const Allocator = std.mem.Allocator;
const gl = zopengl.bindings;
const Input = core.Input;
const World = world_module.World;

const log = std.log.scoped(.BulletsApp);

pub fn run_app(init: std.process.Init, window: *glfw.Window, max_duration: ?f32) !void {
    // var root_allocator = std.heap.PageAllocator
    // defer _ = root_allocator.deinit();

    log.info("Starting simple bullets test app", .{});
    const input = Input.init(window);

    const world = try World.init(init, input);
    defer world.deinit(init);

    gl.enable(gl.DEPTH_TEST);
    gl.enable(gl.BLEND);

    log.info("Starting main loop", .{});

    // glfw.setWindowMonitor( window, null, 0, 0, 3440, 1440, 3000);
    // 1836.2 fps
    const monitor = glfw.getPrimaryMonitor();
    const mode = try glfw.getVideoMode(monitor.?); // Gets native res/refresh
    glfw.setWindowMonitor(window, monitor, 0, 0, mode.*.width, mode.*.height, mode.*.refresh_rate);
    glfw.maximizeWindow(window);
    try glfw.setInputMode(window, glfw.InputMode.cursor, glfw.InputMode.ValueType(glfw.InputMode.cursor).disabled);

    // Turn off vsync
    glfw.swapInterval(0);

    var frame_counter = core.FrameCounter.init(init.io);

    var count: u64 = 0;
    while (!window.shouldClose()) {
        glfw.pollEvents();
        input.update();

        count += 1;
        frame_counter.update();

        if (@mod(count, 10000) == 0) {
            std.debug.print("{d:.1} fps\n", .{frame_counter.fps});
        }

        if (max_duration) |duration| {
            if (input.total_time >= duration) {
                log.info("Reached maximum duration of {d} seconds, exiting", .{duration});
                break;
            }
        }

        // Scene switching
        if (input.key_presses.contains(.page_down) and !input.key_processed.contains(.page_down)) {
            input.key_processed.insert(.page_down);
            try world.nextScene();
        }
        if (input.key_presses.contains(.page_up) and !input.key_processed.contains(.page_up)) {
            input.key_processed.insert(.page_up);
            try world.prevScene();
        }

        clearWindow();

        try world.scene.update(input);

        world.scene.draw(input.total_time);

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
