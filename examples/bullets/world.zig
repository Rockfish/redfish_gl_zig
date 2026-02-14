const std = @import("std");
const glfw = @import("zglfw");
const gl = @import("zopengl").bindings;
const core = @import("core");
const math = @import("math");

const ArenaAllocator = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;

const Input = core.Input;
const Scene = @import("scene.zig").Scene;
const SceneDebug = @import("debug_scene.zig").SceneDebug;

pub const World = struct {
    input: *Input,
    scene: *Scene,

    const Self = @This();

    pub fn init(allocator: Allocator, input: *Input) !Self {
        const debug_scene = try SceneDebug.init(allocator, input);

        return .{
            .input = input,
            .scene = try Scene.init(allocator, "Debug", debug_scene, input),
        };
    }
};
