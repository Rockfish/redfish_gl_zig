const std = @import("std");
const glfw = @import("zglfw");
const zopengl = @import("zopengl");
const gl = @import("zopengl").bindings;
const core = @import("core");
const math = @import("math");

const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const vec3 = math.vec3;
const vec4 = math.vec4;
const Mat4 = math.Mat4;
const Quat = math.Quat;
const Ray = core.Ray;

const Allocator = std.mem.Allocator;
const EnumSet = std.EnumSet;

const Window = glfw.Window;
const Camera = core.Camera;

pub const Input = struct {
    first_mouse: bool = false,
    mouse_x: f32 = 0.0,
    mouse_y: f32 = 0.0,
    mouse_right_button: bool = false,
    mouse_left_button: bool = false,
    key_presses: EnumSet(glfw.Key),
    key_shift: bool = false,
    key_alt: bool = false,
};

pub const State = struct {
    viewport_width: f32,
    viewport_height: f32,
    scaled_width: f32,
    scaled_height: f32,
    window_scale: [2]f32,
    delta_time: f32,
    total_time: f32,
    input: Input,
    camera: *Camera,
    projection: Mat4 = undefined,
    projection_type: core.ProjectionType,
    view: Mat4 = undefined,
    view_type: core.ViewType,
    light_postion: Vec3,
    spin: bool = false,
    world_point: ?Vec3,
    camera_initial_position: Vec3,
    camera_initial_target: Vec3,
    single_mesh_id: i32 = -1,
    animation_id: i32 = -1,

    const Self = @This();
};

pub var state: State = undefined;

pub fn initWindowHandlers(window: *glfw.Window) void {
    _ = window.setKeyCallback(keyHandler);
    _ = window.setFramebufferSizeCallback(framebufferSizeHandler);
    _ = window.setCursorPosCallback(cursorPositionHandler);
    _ = window.setScrollCallback(scrollHandler);
    _ = window.setMouseButtonCallback(mouseHandler);
}

pub fn getPVMMatrix(projection: *const Mat4, view: *const Mat4, model_transform: *const Mat4) Mat4 {
    return projection.mulMat4(&view.mulMat4(model_transform));
}

pub fn keyHandler(window: *glfw.Window, key: glfw.Key, scancode: i32, action: glfw.Action, mods: glfw.Mods) callconv(.C) void {
    _ = scancode;

    switch (action) {
        .press => state.input.key_presses.insert(key),
        .release => state.input.key_presses.remove(key),
        else => {},
    }

    state.input.key_shift = mods.shift;
    state.input.key_alt = mods.alt;

    if (key == .escape) {
        window.setShouldClose(true);
    }
}

var last_time: f32 = 0;
const delay_time: f32 = 0.2;

pub fn processKeys() void {
    const toggle = struct {
        var spin_is_set: bool = false;
    };

    var iterator = state.input.key_presses.iterator();
    while (iterator.next()) |k| {
        switch (k) {
            .t => std.debug.print("time: {d}\n", .{state.delta_time}),
            .w => {
                if (state.input.key_shift) {
                    state.camera.processMovement(.RadiusIn, state.delta_time);
                } else if (state.input.key_alt) {
                    state.camera.processMovement(.RotateUp, state.delta_time);
                } else {
                    state.camera.processMovement(.Forward, state.delta_time);
                }
            },
            .s => {
                if (state.input.key_shift) {
                    state.camera.processMovement(.RadiusOut, state.delta_time);
                } else if (state.input.key_alt) {
                    state.camera.processMovement(.RotateDown, state.delta_time);
                } else {
                    state.camera.processMovement(.Backward, state.delta_time);
                }
            },
            .a => {
                if (state.input.key_shift) {
                    state.camera.processMovement(.OrbitLeft, state.delta_time);
                } else if (state.input.key_alt) {
                    state.camera.processMovement(.RotateLeft, state.delta_time);
                } else {
                    state.camera.processMovement(.Left, state.delta_time);
                }
            },
            .d => {
                if (state.input.key_shift) {
                    state.camera.processMovement(.OrbitRight, state.delta_time);
                } else if (state.input.key_alt) {
                    state.camera.processMovement(.RotateRight, state.delta_time);
                } else {
                    state.camera.processMovement(.Right, state.delta_time);
                }
            },
            .up => {
                if (state.input.key_shift) {
                    state.camera.processMovement(.OrbitUp, state.delta_time);
                } else {
                    state.camera.processMovement(.Up, state.delta_time);
                }
            },
            .down => {
                if (state.input.key_shift) {
                    state.camera.processMovement(.OrbitDown, state.delta_time);
                } else {
                    state.camera.processMovement(.Down, state.delta_time);
                }
            },
            .right => {
                if (state.input.key_shift) {
                    state.camera.processMovement(.OrbitRight, state.delta_time);
                } else {
                    state.camera.processMovement(.Right, state.delta_time);
                }
            },
            .left => {
                if (state.input.key_shift) {
                    state.camera.processMovement(.OrbitLeft, state.delta_time);
                } else {
                    state.camera.processMovement(.Left, state.delta_time);
                }
            },
            .r => {
                state.camera.reset(state.camera_initial_position, state.camera_initial_target);
            },
            .one => {
                state.camera.setLookTo();
            },
            .two => {
                state.camera.setLookAt();
            },
            .three => {
                if (!toggle.spin_is_set) {
                    state.spin = !state.spin;
                }
            },
            .four => {
                state.projection_type = .Perspective;
                state.projection = state.camera.getPerspectiveProjection();
            },
            .five => {
                state.projection_type = .Orthographic;
                state.projection = state.camera.getOrthoProjection();
            },
            .zero => { 
                if (last_time + delay_time < state.total_time) {
                    last_time = state.total_time;
                    // state.single_mesh_id = -1;
                    state.animation_id = 0;
                }
            },
            .equal => {
                if (last_time + delay_time < state.total_time) {
                    last_time = state.total_time;
                    //state.single_mesh_id += 1;
                    state.animation_id += 1;
                }
            },
            .minus => {
                if (last_time + delay_time < state.total_time) {
                    last_time = state.total_time;
                    state.animation_id -= 1;
                    if (state.animation_id < 0) {
                        state.animation_id = 0;
                    }
                }
            },
            else => {},
        }
    }
    toggle.spin_is_set = state.input.key_presses.contains(.three);
}

pub fn framebufferSizeHandler(window: *glfw.Window, width: i32, height: i32) callconv(.C) void {
    _ = window;
    gl.viewport(0, 0, width, height);
    setViewPort(width, height);
}

pub fn setViewPort(w: i32, h: i32) void {
    const width: f32 = @floatFromInt(w);
    const height: f32 = @floatFromInt(h);

    state.viewport_width = width;
    state.viewport_height = height;
    state.scaled_width = width / state.window_scale[0];
    state.scaled_height = height / state.window_scale[1];

    const aspect_ratio = (state.scaled_width / state.scaled_height);
    state.camera.setAspect(aspect_ratio);

    switch (state.projection_type) {
        .Perspective => {
            state.projection = state.camera.getPerspectiveProjection();
        },
        .Orthographic => {
            state.camera.setScreenDimensions(state.scaled_width, state.scaled_height);
            state.projection = state.camera.getOrthoProjection();
        },
    }
}

pub fn mouseHandler(window: *glfw.Window, button: glfw.MouseButton, action: glfw.Action, mods: glfw.Mods) callconv(.C) void {
    _ = window;
    _ = mods;

    state.input.mouse_left_button = action == .press and button == glfw.MouseButton.left;
    state.input.mouse_right_button = action == .press and button == glfw.MouseButton.right;
}

pub fn cursorPositionHandler(window: *glfw.Window, xposIn: f64, yposIn: f64) callconv(.C) void {
    _ = window;
    var xpos: f32 = @floatCast(xposIn);
    var ypos: f32 = @floatCast(yposIn);

    xpos = if (xpos < 0) 0 else if (xpos < state.scaled_width) xpos else state.scaled_width;
    ypos = if (ypos < 0) 0 else if (ypos < state.scaled_height) ypos else state.scaled_height;

    if (state.input.first_mouse) {
        state.input.mouse_x = xpos;
        state.input.mouse_y = ypos;
        state.input.first_mouse = false;
    }

    const xoffset = xpos - state.input.mouse_x;
    const yoffset = state.input.mouse_y - ypos; // reversed since y-coordinates go from bottom to top

    state.input.mouse_x = xpos;
    state.input.mouse_y = ypos;

    if (state.input.key_shift) {
        state.camera.processMouseMovement(xoffset, yoffset, true);
    }
}

pub fn scrollHandler(window: *Window, xoffset: f64, yoffset: f64) callconv(.C) void {
    _ = window;
    _ = xoffset;
    state.camera.processMouseScroll(@floatCast(yoffset));
}
