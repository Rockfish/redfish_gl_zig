const std = @import("std");
const glfw = @import("zglfw");
const zopengl = @import("zopengl");

const log = std.log.scoped(.Main);
const run_app = @import("run_app.zig").run;

const VIEW_PORT_WIDTH: f32 = 1500.0;
const VIEW_PORT_HEIGHT: f32 = 1000.0;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    try glfw.init();
    defer glfw.terminate();

    const gl_major = 4;
    const gl_minor = 0;

    glfw.windowHint(.context_version_major, gl_major);
    glfw.windowHint(.context_version_minor, gl_minor);
    glfw.windowHint(.opengl_profile, .opengl_core_profile);
    glfw.windowHint(.opengl_forward_compat, true);
    glfw.windowHint(.client_api, .opengl_api);
    glfw.windowHint(.doublebuffer, true);

    const window = try glfw.Window.create(VIEW_PORT_WIDTH, VIEW_PORT_HEIGHT, "Angry Monsters", null);
    defer window.destroy();

    glfw.makeContextCurrent(window);
    glfw.swapInterval(1);

    try zopengl.loadCoreProfile(glfw.getProcAddress, gl_major, gl_minor);

    try run_app(allocator, window);

    log.info("Exiting main", .{});
}
