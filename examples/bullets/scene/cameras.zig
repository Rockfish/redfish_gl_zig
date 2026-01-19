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
const Camera = core.CameraGimbal;

const Allocator = std.mem.Allocator;
const Transform = core.Transform;

pub fn createCameraOne(allocator: Allocator, scr_width: f32, scr_height: f32) !*Camera {
    const camera = try Camera.init(
        allocator,
        .{
            .base_target = vec3(0.0, 0.0, 0.0),
            .base_position = vec3(0.0, 0.0, 5.0),
            .scr_width = scr_width,
            .scr_height = scr_height,
            .view_mode = .base,
        },
    );
    return camera;
}

const SceneCamera = struct {
    camera: Camera,

    const Self = @This();

    pub fn init(allocator: Allocator, scr_width: f32, scr_height: f32) !Self {
        const camera = Camera.init(
            allocator,
            .{
                //.position = vec3(0.0, 5.0, 15.0),
                .base_target = vec3(0.0, 1.0, 0.0),
                .base_position = vec3(0.0, 1.0, 5.0),
                .scr_width = scr_width,
                .scr_height = scr_height,
                .view_mode = .base,
            },
        );

        defer camera.deinit();

        var buf: [500]u8 = undefined;
        var buf2: [500]u8 = undefined;
        var buf3: [500]u8 = undefined;
        var buf4: [500]u8 = undefined;

        var transform = Transform.fromTranslation(vec3(0.0, 5.0, 15.0));
        transform.lookAt(vec3(0.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0));
        std.debug.print("transform: {s}\n", .{transform.asString(&buf)});

        const fwd = camera.base_movement.transform.forward();
        const right_vec = camera.base_movement.transform.right();
        const up_vec = camera.base_movement.transform.up();

        std.debug.print(
            "camera: position: {s}  forward: {s}  right: {s}  up: {s}\n",
            .{
                camera.base_movement.transform.translation.asString(&buf),
                fwd.asString(&buf2),
                right_vec.asString(&buf3),
                up_vec.asString(&buf4),
            },
        );

        return .{
            .camera = camera,
        };
    }

    pub fn deinit(self: *Self) void {
        self.camera.deinit();
    }
};
