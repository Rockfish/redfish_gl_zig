const std = @import("std");
const glfw = @import("zglfw");
const gl = @import("zopengl").bindings;
const core = @import("core");
const math = @import("math");

const ArenaAllocator = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;
const Io = std.Io;

const Context = core.Context;
const Input = core.Input;
const Scene = @import("scene.zig").Scene;
const SceneDebug = @import("debug_scene.zig").SceneDebug;
const RuinsGalleryScene = @import("ruins_gallery_scene.zig").RuinsGalleryScene;
const ToonGalleryScene = @import("toon_gallery_scene.zig").ToonGalleryScene;

const SceneId = enum {
    debug,
    ruins_gallery,
    toon_gallery,
};

const scene_order = [_]SceneId{ .debug, .ruins_gallery, .toon_gallery };

pub const World = struct {
    alloc_arena: ArenaAllocator,
    temp_alloc_arena: ArenaAllocator,
    context: Context,
    input: *Input,
    scene: *Scene,
    scene_index: usize = 0,

    const Self = @This();

    pub fn init(process_init: std.process.Init, input: *Input) !*Self {
        const alloc_arena = ArenaAllocator.init(process_init.gpa);
        const temp_alloc_arena = ArenaAllocator.init(process_init.gpa);
        const self = try process_init.gpa.create(Self);
        self.* = .{
            .alloc_arena = alloc_arena,
            .temp_alloc_arena = temp_alloc_arena,
            .context = .{
                .alloc = self.alloc_arena.allocator(),
                .temp_alloc = self.temp_alloc_arena.allocator(),
                .io = process_init.io,
            },
            .input = input,
            .scene = undefined,
        };

        self.scene = try SceneDebug.init(self.context, input);
        _ = self.temp_alloc_arena.reset(.retain_capacity);
        std.debug.print("Scene: {s}\n", .{self.scene.name});
        return self;
    }

    pub fn switchScene(self: *Self, scene_id: SceneId) !void {
        self.scene.cleanUp();
        _ = self.alloc_arena.reset(.retain_capacity);
        _ = self.temp_alloc_arena.reset(.retain_capacity);

        self.scene = switch (scene_id) {
            .debug => try SceneDebug.init(self.context, self.input),
            .ruins_gallery => try RuinsGalleryScene.init(self.context, self.input),
            .toon_gallery => try ToonGalleryScene.init(self.context, self.input),
        };
        _ = self.temp_alloc_arena.reset(.retain_capacity);

        std.debug.print("Scene: {s}\n", .{self.scene.name});
    }

    pub fn nextScene(self: *Self) !void {
        self.scene_index = (self.scene_index + 1) % scene_order.len;
        try self.switchScene(scene_order[self.scene_index]);
    }

    pub fn prevScene(self: *Self) !void {
        if (self.scene_index == 0) {
            self.scene_index = scene_order.len - 1;
        } else {
            self.scene_index -= 1;
        }
        try self.switchScene(scene_order[self.scene_index]);
    }

    pub fn deinit(self: *Self, process_init: std.process.Init) void {
        self.scene.cleanUp();
        self.alloc_arena.deinit();
        self.temp_alloc_arena.deinit();
        process_init.gpa.destroy(self);
    }
};
