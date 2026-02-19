const std = @import("std");
const core = @import("core");
const math = @import("math");

const Lights = @import("scene/lights.zig").Lights;

const Allocator = std.mem.Allocator;
const Mat4 = math.Mat4;
const Transform = core.Transform;

pub const SceneObject = struct {
    name: []const u8,
    dispatch: Dispatch,

    const Self = @This();

    const Dispatch = struct {
        obj_ptr: *anyopaque,
        draw_fn: *const fn (ptr: *anyopaque, projection: *const Mat4, view: *const Mat4) void,
        update_lights_fn: *const fn (ptr: *anyopaque, lights: Lights) void,
        get_transform_fn: *const fn (ptr: *anyopaque) *Transform,
    };

    pub fn init(allocator: Allocator, name: []const u8, object_ptr: anytype) !*SceneObject {
        const gen = struct {
            const ObjectType = @TypeOf(object_ptr);

            pub fn draw(obj_ptr: *anyopaque, projection: *const Mat4, view: *const Mat4) void {
                const obj: ObjectType = @ptrCast(@alignCast(obj_ptr));
                obj.draw(projection, view);
            }

            pub fn updateLights(obj_ptr: *anyopaque, lights: Lights) void {
                const obj: ObjectType = @ptrCast(@alignCast(obj_ptr));
                obj.update_lights(lights);
            }

            pub fn getTransform(obj_ptr: *anyopaque) *Transform {
                const obj: ObjectType = @ptrCast(@alignCast(obj_ptr));
                return &obj.transform;
            }
        };

        const scene_object = try allocator.create(SceneObject);
        scene_object.* = SceneObject{
            .name = name,
            .dispatch = .{
                .obj_ptr = object_ptr,
                .draw_fn = gen.draw,
                .update_lights_fn = gen.updateLights,
                .get_transform_fn = gen.getTransform,
            },
        };
        return scene_object;
    }

    pub fn draw(self: *Self, projection: *const Mat4, view: *const Mat4) void {
        self.dispatch.draw_fn(self.dispatch.obj_ptr, projection, view);
    }

    pub fn updateLights(self: *Self, lights: Lights) void {
        self.dispatch.update_lights_fn(self.dispatch.obj_ptr, lights);
    }

    pub fn getTransform(self: *Self) *Transform {
        return self.dispatch.get_transform_fn(self.dispatch.obj_ptr);
    }
};
