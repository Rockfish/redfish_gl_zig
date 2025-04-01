const std = @import("std");
const math = @import("math");
const Assimp = @import("assimp.zig").Assimp;
const Transform = @import("transform.zig").Transform;
const NodeKeyframes = @import("model_node_keyframes.zig").NodeKeyframes;
const String = @import("string.zig").String;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Mat4 = math.Mat4;

pub const ModelNode = struct {
    node_name: *String,
    transform: Transform,
    children: *ArrayList(*ModelNode),
    meshes: *ArrayList(u32),
    allocator: Allocator,

    const Self = @This();

    pub fn deinit(self: *Self) void {
        for (self.children.items) |child| {
            child.deinit();
        }
        self.children.deinit();
        self.node_name.deinit();
        self.meshes.deinit();
        self.allocator.destroy(self.children);
        self.allocator.destroy(self.meshes);
        self.allocator.destroy(self);
    }

    pub fn init(allocator: Allocator, name: *String) !*ModelNode {
        const node = try allocator.create(ModelNode);
        node.* = ModelNode{
            .node_name = name,
            .transform = Transform.default(),
            .children = try allocator.create(ArrayList(*ModelNode)),
            .meshes = try allocator.create(ArrayList(u32)),
            .allocator = allocator,
        };
        node.children.* = ArrayList(*ModelNode).init(allocator);
        node.meshes.* = ArrayList(u32).init(allocator);
        return node;
    }
};

pub const ModelBone = struct {
    bone_name: *String,
    bone_index: u32,
    offset_transform: Transform,
    allocator: Allocator,

    const Self = @This();

    pub fn deinit(self: *Self) void {
        self.bone_name.deinit();
        self.allocator.destroy(self);
    }

    // not used
    // pub fn init(allocator: Allocator, name: []const u8, id: u32, offset: Mat4) !*ModelBone {
    //     const bone = try allocator.create(ModelBone);
    //     bone.* = ModelBone{
    //         .bone_name = String.new(name),
    //         .bone_index = id,
    //         .offset_transform = Transform.from_matrix(offset),
    //         .allocator = allocator,
    //     };
    //
    //     return bone;
    // }

    pub fn asString(self: *const Self, buf: []u8) [:0]u8 {
        var buffer: [256]u8 = undefined;
        const transform_str = self.offset_transform.asString(&buffer);
        return std.fmt.bufPrintZ(
            buf,
            "bone_name: {s}  index: {d}  offset_transform: {s}",
            .{self.bone_name.str, self.bone_index, transform_str},
        ) catch @panic("bufPrintZ error.");
    }
};

pub const ModelAnimation = struct {
    name: *String,
    duration: f32,
    ticks_per_second: f32,
    node_keyframes: *ArrayList(*NodeKeyframes),
    allocator: Allocator,

    const Self = @This();

    pub fn deinit(self: *Self) void {
        self.name.deinit();
        for (self.node_keyframes.items) |node_animation| {
            node_animation.deinit();
        }
        self.node_keyframes.deinit();
        self.allocator.destroy(self.node_keyframes);
        self.allocator.destroy(self);
    }

    pub fn init(allocator: Allocator, name: Assimp.aiString) !*Self {
        const node_keyframes = try allocator.create(ArrayList(*NodeKeyframes));
        node_keyframes.* = ArrayList(*NodeKeyframes).init(allocator);

        const animation = try allocator.create(ModelAnimation);
        animation.* = .{
            .name = try String.from_aiString(name),
            .duration = 0.0,
            .ticks_per_second = 0.0,
            .node_keyframes = node_keyframes,
            .allocator = allocator,
        };
        return animation;
    }
};


