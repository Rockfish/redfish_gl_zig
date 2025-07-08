const std = @import("std");
const glfw = @import("zglfw");
const zopengl = @import("zopengl");
const gl = @import("zopengl").bindings;
const core = @import("core");
const math = @import("math");
// const glftReport = @import("gltf_report.zig").gltfReport;
const run = @import("run_app.zig").run;

const assets_list = @import("assets_list.zig");
const state_module = @import("state.zig");

const SCR_WIDTH: f32 = 1000.0;
const SCR_HEIGHT: f32 = 1000.0;

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
        "Demo App",
        null,
    );
    defer window.destroy();

    glfw.makeContextCurrent(window);
    glfw.swapInterval(1);
    try zopengl.loadCoreProfile(glfw.getProcAddress, gl_major, gl_minor);

    // Display initial model info
    const initial_model = assets_list.demo_models[0];
    std.debug.print(
        "Starting with model: {s} ({s}) - {s}\n",
        .{ initial_model.name, initial_model.format, initial_model.description },
    );
    std.debug.print("Press 'n' for next model, 'b' for previous model\n", .{});

    try run(window);

    glfw.terminate();
}
