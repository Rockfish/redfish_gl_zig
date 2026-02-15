const std = @import("std");

const Allocator = std.mem.Allocator;

pub const Scene = struct {
    name: []const u8,
    dispatch: Dispatch,

    const Self = @This();

    const Dispatch = struct {
        obj_ptr: *anyopaque,
        type_id: usize,
        update_fn: *const fn (ptr: *anyopaque, state: *anyopaque) anyerror!void,
        draw_fn: *const fn (ptr: *anyopaque) void,
    };

    pub fn init(allocator: Allocator, name: []const u8, object_ptr: anytype, state_ptr: anytype) !*Scene {
        const gen = struct {
            const ObjectType = @TypeOf(object_ptr);
            const StateType = @TypeOf(state_ptr);

            pub fn updateFn(obj_ptr: *anyopaque, state_pointer: *anyopaque) anyerror!void {
                const obj: ObjectType = @ptrCast(@alignCast(obj_ptr));
                const state: StateType = @ptrCast(@alignCast(state_pointer));

                if (std.meta.hasMethod(ObjectType, "update")) {
                    return obj.update(state);
                }
            }

            pub fn drawFn(obj_ptr: *anyopaque) void {
                const obj: ObjectType = @ptrCast(@alignCast(obj_ptr));
                return obj.draw();
            }
        };

        const scene = try allocator.create(Scene);
        scene.* = Scene{
            .name = name,
            .dispatch = .{
                .obj_ptr = object_ptr,
                .type_id = typeId(@TypeOf(object_ptr)),
                .update_fn = gen.updateFn,
                .draw_fn = gen.drawFn,
            },
        };
        return scene;
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn update(self: *Scene, state: *anyopaque) anyerror!void {
        try self.dispatch.update_fn(self.dispatch.obj_ptr, state);
    }

    pub fn draw(self: *Scene) void {
        self.dispatch.draw_fn(self.dispatch.obj_ptr);
    }

    pub fn castTo(self: *Self, comptime T: type) ?*T {
        if (self.dispatch.type_id != typeId(T)) return null;
        return @as(*T, @ptrCast(@alignCast(self.dispatch.obj_ptr)));
    }

    fn typeId(comptime T: type) usize {
        _ = T;
        const H = struct {
            var id: u8 = 0;
        };
        return @intFromPtr(&H.id);
    }
};
