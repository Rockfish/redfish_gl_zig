const std = @import("std");
const core = @import("core");
const math = @import("math");
const glfw = @import("zglfw");
const gl = @import("zopengl").bindings;
const Window = glfw.Window;

const Vec3 = math.Vec3;
const Mat4 = math.Mat4;

const State = @import("../state.zig").State;
const Movement = core.Movement;

pub var _state: *State = undefined;

pub fn processInput() void {
    var iterator = _state.input.key_presses.iterator();
    while (iterator.next()) |k| {
        const movement_object: *Movement = if (_state.motion_object == .base)
            &_state.scene.getCamera().base_movement
        else
            &_state.scene.getCamera().gimbal_movement;

        // std.debug.print("key: {any}\n", .{k});
        switch (k) {
            .t => std.debug.print("time: {d}\n", .{_state.delta_time}),
            .w => {
                switch (_state.motion_type) {
                    .translate => {
                        movement_object.processMovement(.forward, _state.delta_time);
                    },
                    .orbit => {
                        movement_object.processMovement(.orbit_up, _state.delta_time);
                    },
                    .circle => {
                        movement_object.processMovement(.circle_up, _state.delta_time);
                    },
                    .rotate => {
                        movement_object.processMovement(.rotate_up, _state.delta_time);
                    },
                    .look => {
                        movement_object.processMovement(.rotate_up, _state.delta_time);
                    },
                }
            },
            .s => {
                switch (_state.motion_type) {
                    .translate => {
                        movement_object.processMovement(.backward, _state.delta_time);
                    },
                    .orbit => {
                        movement_object.processMovement(.orbit_down, _state.delta_time);
                    },
                    .circle => {
                        // No circle movement for S key
                        movement_object.processMovement(.circle_down, _state.delta_time);
                    },
                    .rotate => {
                        movement_object.processMovement(.rotate_down, _state.delta_time);
                    },
                    .look => {
                        movement_object.processMovement(.rotate_down, _state.delta_time);
                    },
                }
            },
            .a => {
                switch (_state.motion_type) {
                    .translate => {
                        movement_object.processMovement(.left, _state.delta_time);
                    },
                    .orbit => {
                        movement_object.processMovement(.orbit_left, _state.delta_time);
                    },
                    .circle => {
                        movement_object.processMovement(.circle_left, _state.delta_time);
                    },
                    .rotate => {
                        movement_object.processMovement(.rotate_left, _state.delta_time);
                    },
                    .look => {
                        movement_object.processMovement(.rotate_left, _state.delta_time);
                    },
                }
            },
            .d => {
                switch (_state.motion_type) {
                    .translate => {
                        movement_object.processMovement(.right, _state.delta_time);
                    },
                    .orbit => {
                        movement_object.processMovement(.orbit_right, _state.delta_time);
                    },
                    .circle => {
                        movement_object.processMovement(.circle_right, _state.delta_time);
                    },
                    .rotate => {
                        movement_object.processMovement(.rotate_right, _state.delta_time);
                    },
                    .look => {
                        movement_object.processMovement(.rotate_right, _state.delta_time);
                    },
                }
            },
            .up => {
                switch (_state.motion_type) {
                    .translate => {
                        movement_object.processMovement(.up, _state.delta_time);
                    },
                    .orbit => {
                        movement_object.processMovement(.orbit_up, _state.delta_time);
                    },
                    .circle => {
                        // No circle movement for Up key
                        movement_object.processMovement(.circle_up, _state.delta_time);
                    },
                    .rotate => {
                        movement_object.processMovement(.rotate_up, _state.delta_time);
                    },
                    .look => {
                        movement_object.processMovement(.rotate_up, _state.delta_time);
                    },
                }
            },
            .down => {
                switch (_state.motion_type) {
                    .translate => {
                        movement_object.processMovement(.down, _state.delta_time);
                    },
                    .orbit => {
                        movement_object.processMovement(.orbit_down, _state.delta_time);
                    },
                    .circle => {
                        // No circle movement for Down key
                        movement_object.processMovement(.circle_down, _state.delta_time);
                    },
                    .rotate => {
                        movement_object.processMovement(.rotate_down, _state.delta_time);
                    },
                    .look => {
                        movement_object.processMovement(.rotate_down, _state.delta_time);
                    },
                }
            },
            .right => {
                switch (_state.motion_type) {
                    .translate => {
                        movement_object.processMovement(.right, _state.delta_time);
                    },
                    .orbit => {
                        movement_object.processMovement(.orbit_right, _state.delta_time);
                    },
                    .circle => {
                        movement_object.processMovement(.circle_right, _state.delta_time);
                    },
                    .rotate => {
                        movement_object.processMovement(.rotate_right, _state.delta_time);
                    },
                    .look => {
                        movement_object.processMovement(.rotate_right, _state.delta_time);
                    },
                }
            },
            .left => {
                switch (_state.motion_type) {
                    .translate => {
                        movement_object.processMovement(.left, _state.delta_time);
                    },
                    .orbit => {
                        movement_object.processMovement(.orbit_left, _state.delta_time);
                    },
                    .circle => {
                        movement_object.processMovement(.circle_left, _state.delta_time);
                    },
                    .rotate => {
                        movement_object.processMovement(.rotate_left, _state.delta_time);
                    },
                    .look => {
                        movement_object.processMovement(.rotate_left, _state.delta_time);
                    },
                }
            },
            .r => {
                if (!_state.input.key_processed.contains(.r)) {
                    _state.reset = true;
                }
            },
            .c => {
                if (!_state.input.key_processed.contains(.c)) {
                    _state.use_camera_view = !_state.use_camera_view;
                }
            },
            .one => {
                if (!_state.input.key_processed.contains(.one)) {
                    _state.motion_type = .translate;
                    printMotionViewState();
                }
            },
            .two => {
                if (!_state.input.key_processed.contains(.two)) {
                    _state.motion_type = .circle;
                    printMotionViewState();
                }
            },
            .three => {
                if (!_state.input.key_processed.contains(.three)) {
                    _state.motion_type = .orbit;
                    printMotionViewState();
                }
            },
            .four => {
                if (!_state.input.key_processed.contains(.four)) {
                    _state.motion_type = .rotate;
                    printMotionViewState();
                }
            },
            .five => {
                if (!_state.input.key_processed.contains(.five)) {
                    _state.motion_type = .look;
                    printMotionViewState();
                }
            },
            .six => {
                if (!_state.input.key_processed.contains(.six)) {
                    _state.motion_object = if (_state.motion_object == .base)
                        .gimbal
                    else
                        .base;
                    printMotionViewState();
                }
            },
            .seven => {
                if (!_state.input.key_processed.contains(.seven)) {
                    _state.scene.getCamera().view_mode = if (_state.scene.getCamera().view_mode == .base)
                        .gimbal
                    else
                        .base;
                    _state.scene.getCamera().view_cache_valid = false;
                    printMotionViewState();
                    // state.spin = !state.spin;
                }
            },
            .eight => {
                if (!_state.input.key_processed.contains(.eight)) {
                    _state.scene.getCamera().setPerspective();
                    std.debug.print("Projection: Perspective\n", .{});
                }
            },
            .nine => {
                if (!_state.input.key_processed.contains(.nine)) {
                    _state.scene.getCamera().setOrthographic();
                    std.debug.print("Projection: Orthographic\n", .{});
                }
            },
            .zero => {
                if (!_state.input.key_processed.contains(.zero)) {
                    // _state.animation_reset_requested = true;
                }
            },
            .equal => {
                if (!_state.input.key_processed.contains(.equal)) {
                    // _state.animation_next_requested = true;
                }
            },
            .minus => {
                if (!_state.input.key_processed.contains(.minus)) {
                    // _state.animation_prev_requested = true;
                }
            },
            .n => {
                if (!_state.input.key_processed.contains(.n)) {
                    // _state.direction_index = (_state.direction_index + 1) % 8;
                    // std.debug.print("Next direction: {d} ({d:.1}°)\n", .{ _state.direction_index, @as(f32, @floatFromInt(_state.direction_index)) * 45.0 });
                }
            },
            .b => {
                if (!_state.input.key_processed.contains(.b)) {
                    // _state.direction_index = if (_state.direction_index == 0) 7 else _state.direction_index - 1;
                    // std.debug.print("Previous direction: {d} ({d:.1}°)\n", .{ _state.direction_index, @as(f32, @floatFromInt(_state.direction_index)) * 45.0 });
                }
            },
            .f => {
                if (!_state.input.key_processed.contains(.f)) {
                    _state.scene.floor.plane.shape.is_visible = !_state.scene.floor.plane.shape.is_visible;
                    std.debug.print("floor.is_visible: {any}\n", .{_state.scene.floor.plane.shape.is_visible});
                }
            },
            .p => {
                if (!_state.input.key_processed.contains(.p)) {
                    _state.output_position_requested = true;
                }
            },
            .h => {
                if (!_state.input.key_processed.contains(.h)) {
                    // _state.ui_help_visible = !_state.ui_help_visible;
                    // std.debug.print("Help display: {}\n", .{_state.ui_help_visible});
                }
            },
            .i => {
                if (!_state.input.key_processed.contains(.i)) {
                    // _state.ui_camera_info_visible = !_state.ui_camera_info_visible;
                    // std.debug.print("Camera info display: {}\n", .{_state.ui_camera_info_visible});
                }
            },
            .g => {
                if (!_state.input.key_processed.contains(.g)) {
                    // _state.shader_debug_enabled = !_state.shader_debug_enabled;
                    // std.debug.print("Shader debug: {}\n", .{_state.shader_debug_enabled});
                }
            },
            .u => {
                if (!_state.input.key_processed.contains(.u)) {
                    // _state.shader_debug_dump_requested = true;
                }
            },
            .F12 => {
                if (!_state.input.key_processed.contains(.F12)) {
                    _state.screenshot_requested = true;
                    std.debug.print("Screenshot requested (F12)\n", .{});
                }
            },
            .space => {
                if (!_state.input.key_processed.contains(.space)) {
                    _state.run_animation = !_state.run_animation;
                    std.debug.print("Animation toggle: {}\n", .{_state.run_animation});
                }
            },
            else => {},
        }

        // Mark this key as processed for this frame
        _state.input.key_processed.insert(k);
    }
}

pub fn printMotionViewState() void {
    std.debug.print("-----\n", .{});
    std.debug.print("Look mode: {any}\n", .{_state.scene.getCamera().view_mode});
    std.debug.print("Motion type: {any}\n", .{_state.motion_type});
    std.debug.print("Motion object: {any}\n", .{_state.motion_object});
    // std.debug.print("-----\n", .{});
}

// pub fn frameToFit() void {
// _state.camera_reposition_requested = true;
// std.debug.print("Frame to fit requested\n", .{});
// }

pub fn initWindowHandlers(window: *glfw.Window) void {
    _ = window.setKeyCallback(keyHandler);
    _ = window.setFramebufferSizeCallback(framebufferSizeHandler);
    _ = window.setCursorPosCallback(cursorPositionHandler);
    _ = window.setScrollCallback(scrollHandler);
    _ = window.setMouseButtonCallback(mouseHandler);
}

pub fn getProjectionView(projection: *const Mat4, view: *const Mat4, model_transform: *const Mat4) Mat4 {
    return projection.mulMat4(&view.mulMat4(model_transform));
}

pub fn keyHandler(window: *glfw.Window, key: glfw.Key, scancode: i32, action: glfw.Action, mods: glfw.Mods) callconv(.c) void {
    _ = scancode;

    _state.input.handleKey(key, action, mods);

    if (key == .escape) {
        window.setShouldClose(true);
    }
}

pub fn framebufferSizeHandler(window: *glfw.Window, width: i32, height: i32) callconv(.c) void {
    _ = window;
    gl.viewport(0, 0, width, height);
    setViewPort(width, height);
}

pub fn setViewPort(w: i32, h: i32) void {
    const width: f32 = @floatFromInt(w);
    const height: f32 = @floatFromInt(h);

    _state.viewport_width = width;
    _state.viewport_height = height;
    _state.scaled_width = width / _state.window_scale[0];
    _state.scaled_height = height / _state.window_scale[1];

    const aspect_ratio = (_state.scaled_width / _state.scaled_height);
    _state.scene.getCamera().setAspect(aspect_ratio);
    _state.scene.getCamera().setScreenDimensions(_state.scaled_width, _state.scaled_height);
}

pub fn mouseHandler(window: *glfw.Window, button: glfw.MouseButton, action: glfw.Action, mods: glfw.Mods) callconv(.c) void {
    _ = window;
    _ = mods;

    _state.input.mouse_left_button = action == .press and button == glfw.MouseButton.left;
    _state.input.mouse_right_button = action == .press and button == glfw.MouseButton.right;
}

pub fn cursorPositionHandler(window: *glfw.Window, xposIn: f64, yposIn: f64) callconv(.c) void {
    _ = window;
    var xpos: f32 = @floatCast(xposIn);
    var ypos: f32 = @floatCast(yposIn);

    xpos = if (xpos < 0) 0 else if (xpos < _state.scaled_width) xpos else _state.scaled_width;
    ypos = if (ypos < 0) 0 else if (ypos < _state.scaled_height) ypos else _state.scaled_height;

    if (_state.input.first_mouse) {
        _state.input.mouse_x = xpos;
        _state.input.mouse_y = ypos;
        _state.input.first_mouse = false;
    }

    const xoffset = xpos - _state.input.mouse_x;
    const yoffset = _state.input.mouse_y - ypos; // reversed since y-coordinates go from bottom to top

    _state.input.mouse_x = xpos;
    _state.input.mouse_y = ypos;

    _ = xoffset;
    _ = yoffset;

    // if (state.input.key_shift) {
    //     state.camera.processMouseMovement(xoffset, yoffset, true);
    // }
}

pub fn scrollHandler(window: *Window, xoffset: f64, yoffset: f64) callconv(.c) void {
    _ = window;
    _ = xoffset;
    _state.scene.getCamera().adjustFov(@floatCast(yoffset));
}
