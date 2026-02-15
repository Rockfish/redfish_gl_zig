const std = @import("std");
const core = @import("core");
const math = @import("math");
const Grid = @import("grid.zig").Grid;

const Vec3 = math.Vec3;
const vec3 = math.vec3;
const Vec4 = math.Vec4;
const Mat4 = math.Mat4;
const Quat = math.Quat;
const quat = math.quat;
const Input = core.Input;

const Allocator = std.mem.Allocator;
const Transform = core.Transform;

pub const Camera = struct {
    name: []const u8,
    dispatch: Dispatch,

    const Self = @This();

    const Dispatch = struct {
        obj_ptr: *anyopaque,
        update_fn: *const fn (ptr: *anyopaque, input: *core.Input) anyerror!void,
        process_input_fn: *const fn (ptr: *anyopaque, input: *core.Input) anyerror!void,
        getProjection_fn: *const fn (ptr: *anyopaque) Mat4,
        getView_fn: *const fn (ptr: *anyopaque) Mat4,
        setPerspective_fn: *const fn (ptr: *anyopaque) void,
        setOrthographic_fn: *const fn (ptr: *anyopaque) void,
    };

    pub fn init(allocator: Allocator, name: []const u8, object_ptr: anytype) !*Camera {
        const gen = struct {
            const ObjectType = @TypeOf(object_ptr);
            const node_ptr_info = @typeInfo(ObjectType);

            pub fn updateFn(obj_ptr: *anyopaque, input: *core.Input) anyerror!void {
                const obj: ObjectType = @ptrCast(@alignCast(obj_ptr));
                return obj.update(input);
            }

            pub fn processInputFn(obj_ptr: *anyopaque, input: *core.Input) anyerror!void {
                const obj: ObjectType = @ptrCast(@alignCast(obj_ptr));
                return obj.processInput(input);
            }

            pub fn getProjectionFn(obj_ptr: *anyopaque) Mat4 {
                const obj: ObjectType = @ptrCast(@alignCast(obj_ptr));
                return obj.camera.getProjection();
            }

            pub fn getViewFn(obj_ptr: *anyopaque) Mat4 {
                const obj: ObjectType = @ptrCast(@alignCast(obj_ptr));
                return obj.camera.getView();
            }

            pub fn setPerspectiveFn(obj_ptr: *anyopaque) void {
                const obj: ObjectType = @ptrCast(@alignCast(obj_ptr));
                return obj.camera.setPerspective();
            }

            pub fn setOrhograhpicFn(obj_ptr: *anyopaque) void {
                const obj: ObjectType = @ptrCast(@alignCast(obj_ptr));
                return obj.camera.setOrthographic();
            }
        };

        const camera_type = try allocator.create(Camera);
        camera_type.* = Camera{
            .name = name,
            .dispatch = .{
                .obj_ptr = object_ptr,
                .update_fn = gen.updateFn,
                .process_input_fn = gen.processInputFn,
                .getProjection_fn = gen.getProjectionFn,
                .getView_fn = gen.getViewFn,
                .setPerspective_fn = gen.setPerspectiveFn,
                .setOrthographic_fn = gen.setOrhograhpicFn,
            },
        };
        return camera_type;
    }

    pub fn update(self: *Self, input: *core.Input) anyerror!void {
        try self.dispatch.update_fn(self.dispatch.obj_ptr, input);
    }

    pub fn processInput(self: *Self, input: *core.Input) !void {
        try self.dispatch.process_input_fn(self.dispatch.obj_ptr, input);
    }

    pub fn getProjection(self: *Self) Mat4 {
        return self.dispatch.getProjection_fn(self.dispatch.obj_ptr);
    }

    pub fn getView(self: *Self) Mat4 {
        return self.dispatch.getView_fn(self.dispatch.obj_ptr);
    }

    pub fn setPerspective(self: *Self) void {
        self.dispatch.setPerspective_fn(self.dispatch.obj_ptr);
    }

    pub fn setOrthographic(self: *Self) void {
        self.dispatch.setOrthographic_fn(self.dispatch.obj_ptr);
    }
};

pub fn createCameraOne(allocator: Allocator, scr_width: f32, scr_height: f32) !*core.CameraGimbal {
    const camera = try core.CameraGimbal.init(
        allocator,
        .{
            .base_target = vec3(0.0, 0.0, 0.0),
            .base_position = vec3(0.0, 0.0, 20.0),
            .scr_width = scr_width,
            .scr_height = scr_height,
            .view_mode = .base,
        },
    );
    return camera;
}

pub const FreeCamera = struct {
    camera: *core.Camera,
    rotation_speed: f32 = 8.0,
    translate_speed: f32 = 5.0,
    input_tick: u64 = 0,

    const Self = @This();

    pub fn init(allocator: Allocator, scr_width: f32, scr_height: f32) !*Camera {
        const camera = try core.Camera.init(
            allocator,
            .{
                .position = vec3(0.0, 5.0, 15.0),
                .target = vec3(0.0, 1.0, 0.0),
                .scr_width = scr_width,
                .scr_height = scr_height,
            },
        );

        const free_camera = try allocator.create(FreeCamera);
        free_camera.* = FreeCamera{
            .camera = camera,
        };

        return Camera.init(allocator, "free_camera", free_camera);
    }

    pub fn update(self: *Self, input: *core.Input) !void {
        if (input.update_tick != self.input_tick) {
            self.camera.adjustFov(@floatCast(input.scroll_yoffset));
            self.camera.setScreenDimensions(input.framebuffer_width, input.framebuffer_height);
            self.input_tick = input.update_tick;
        }
    }

    fn processInput(self: *Self, input: *core.Input) !void {
        const dt = input.delta_time;

        var iterator = input.key_presses.iterator();
        while (iterator.next()) |k| {
            switch (k) {
                .up => {
                    if (input.key_shift) {
                        self.camera.processMovement(.up, dt);
                    } else {
                        self.camera.processMovement(.rotate_up, dt);
                    }
                },
                .down => {
                    if (input.key_shift) {
                        self.camera.processMovement(.down, dt);
                    } else {
                        self.camera.processMovement(.rotate_down, dt);
                    }
                },
                .left => self.camera.processMovement(.rotate_left, dt),
                .right => self.camera.processMovement(.rotate_right, dt),
                .w => self.camera.processMovement(.forward, dt),
                .s => self.camera.processMovement(.backward, dt),
                .a => self.camera.processMovement(.left, dt),
                .d => self.camera.processMovement(.right, dt),
                else => {},
            }
            // One-shot keys: fire once per press
            if (input.key_processed.contains(k)) {
                continue;
            }
        }
    }
};
