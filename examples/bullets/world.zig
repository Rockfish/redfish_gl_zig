const std = @import("std");
const glfw = @import("zglfw");
const gl = @import("zopengl").bindings;
const core = @import("core");
const math = @import("math");

const ArenaAllocator = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;
const Io = std.Io;

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
    io: Io,
    root_allocator: Allocator,
    scene_arena: ArenaAllocator,
    input: *Input,
    scene: *Scene,
    scene_index: usize = 0,

    const Self = @This();

    pub fn init(process_init: std.process.Init, input: *Input) !*Self {
        const self = try process_init.gpa.create(Self);
        self.* = .{
            .io = process_init.io,
            .root_allocator = process_init.gpa,
            .scene_arena = ArenaAllocator.init(process_init.gpa),
            .input = input,
            .scene = undefined,
        };

        const scene_allocator = self.scene_arena.allocator();
        self.scene = try SceneDebug.init(self.io, scene_allocator, input);
        std.debug.print("Scene: {s}\n", .{self.scene.name});
        return self;
    }

    pub fn switchScene(self: *Self, scene_id: SceneId) !void {
        // Clean up GL resources before freeing arena memory
        self.scene.deinit();
        self.scene_arena.deinit();
        self.scene_arena = ArenaAllocator.init(self.root_allocator);

        const allocator = self.scene_arena.allocator();
        self.scene = switch (scene_id) {
            .debug => try SceneDebug.init(self.io, allocator, self.input),
            .ruins_gallery => try RuinsGalleryScene.init(self.io, allocator, self.input),
            .toon_gallery => try ToonGalleryScene.init(self.io, allocator, self.input),
        };
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

    pub fn deinit(self: *Self) void {
        self.scene.deinit();
        self.scene_arena.deinit();
        self.root_allocator.destroy(self);
    }
};
