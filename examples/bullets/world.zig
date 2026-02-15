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
    root_allocator: Allocator,
    scene_arena: ArenaAllocator,
    input: *Input,
    scene: *Scene,

    const Self = @This();

    pub fn init(root_allocator: Allocator, input: *Input) !*Self {
        const self = try root_allocator.create(Self);
        self.* = .{
            .root_allocator = root_allocator,
            .scene_arena = ArenaAllocator.init(root_allocator),
            .input = input,
            .scene = undefined,
        };

        const scene_allocator = self.scene_arena.allocator();
        self.scene = try SceneDebug.init(scene_allocator, input);
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.scene_arena.deinit();
        self.root_allocator.destroy(self);
    }
};
