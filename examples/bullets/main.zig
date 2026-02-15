const std = @import("std");
const glfw = @import("zglfw");
const zopengl = @import("zopengl");
const run_app = @import("run_app.zig").run_app;

const SCR_WIDTH: f32 = 1000.0;
const SCR_HEIGHT: f32 = 1000.0;

fn printUsage() void {
    std.debug.print("Usage: bullets [options]\n", .{});
    std.debug.print("Options:\n", .{});
    std.debug.print("  --duration, -d <seconds>     Run for specified duration then exit\n", .{});
    std.debug.print("  --help, -h                   Show this help message\n", .{});
}

pub fn main() !void {
    // Parse command line arguments
    var args = std.process.args();
    _ = args.skip(); // Skip program name

    var runtime_duration: ?f32 = null;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printUsage();
            return;
        } else if (std.mem.eql(u8, arg, "--duration") or std.mem.eql(u8, arg, "-d")) {
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
        } else {
            std.debug.print("Unknown argument: {s}\n", .{arg});
            printUsage();
            std.process.exit(1);
        }
    }

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
        "Bullet App",
        null,
    );
    defer window.destroy();

    glfw.makeContextCurrent(window);
    glfw.swapInterval(1);
    try zopengl.loadCoreProfile(glfw.getProcAddress, gl_major, gl_minor);

    try run_app(window, runtime_duration);

    glfw.terminate();
}
