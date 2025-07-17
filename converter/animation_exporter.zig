// Animation export system for FBX → glTF conversion
const std = @import("std");

// Use @cImport to access ASSIMP C functions
const assimp = @cImport({
    @cInclude("assimp/cimport.h");
    @cInclude("assimp/scene.h");
    @cInclude("assimp/anim.h");
});

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

// These will be defined as generic parameters when used
const GltfBufferView = struct {
    buffer: u32,
    byteOffset: u32,
    byteLength: u32,
    target: ?u32 = null,
};

const GltfAccessor = struct {
    bufferView: u32,
    byteOffset: u32 = 0,
    componentType: u32,
    count: u32,
    type: []const u8,
    max: ?[]f32 = null,
    min: ?[]f32 = null,
};

// glTF animation structures
pub const GltfAnimation = struct {
    name: []const u8,
    channels: []GltfAnimationChannel,
    samplers: []GltfAnimationSampler,
};

pub const GltfAnimationChannel = struct {
    sampler: u32,
    target: GltfAnimationChannelTarget,
};

pub const GltfAnimationChannelTarget = struct {
    node: u32,
    path: []const u8, // "translation", "rotation", "scale"
};

pub const GltfAnimationSampler = struct {
    input: u32, // accessor index for timestamps
    output: u32, // accessor index for values
    interpolation: []const u8 = "LINEAR",
};

pub fn AnimationExporter(comptime BufferViewType: type, comptime AccessorType: type) type {
    return struct {
        const Self = @This();

        allocator: Allocator,
        animations: ArrayList(GltfAnimation),
        binary_data: *ArrayList(u8),
        buffer_views: *ArrayList(BufferViewType),
        accessors: *ArrayList(AccessorType),

        pub fn init(allocator: Allocator, binary_data: *ArrayList(u8), buffer_views: *ArrayList(BufferViewType), accessors: *ArrayList(AccessorType)) Self {
            return Self{
                .allocator = allocator,
                .animations = ArrayList(GltfAnimation).init(allocator),
                .binary_data = binary_data,
                .buffer_views = buffer_views,
                .accessors = accessors,
            };
        }

        pub fn deinit(self: *AnimationExporter) void {
            for (self.animations.items) |animation| {
                self.allocator.free(animation.name);
                self.allocator.free(animation.channels);
                self.allocator.free(animation.samplers);
            }
            self.animations.deinit();
        }

        pub fn processAnimations(self: *AnimationExporter, ai_scene: *const assimp.aiScene) !void {
            if (ai_scene.mNumAnimations == 0) {
                return;
            }

            std.debug.print("Processing {d} animations for glTF export...\n", .{ai_scene.mNumAnimations});

            for (0..ai_scene.mNumAnimations) |anim_idx| {
                const ai_anim = ai_scene.mAnimations[anim_idx];
                try self.processAnimation(ai_anim, anim_idx);
            }
        }

        fn processAnimation(self: *AnimationExporter, ai_anim: *const assimp.aiAnimation, anim_idx: usize) !void {
            const anim_name = if (ai_anim.mName.length > 0)
                try self.allocator.dupe(u8, ai_anim.mName.data[0..ai_anim.mName.length])
            else
                try std.fmt.allocPrint(self.allocator, "animation_{d}", .{anim_idx});

            std.debug.print("  Animation '{s}': duration={d}, ticks_per_second={d}, channels={d}\n", .{ anim_name, ai_anim.mDuration, ai_anim.mTicksPerSecond, ai_anim.mNumChannels });

            // Convert ASSIMP channels to glTF channels and samplers
        var channels = ArrayList(GltfAnimationChannel).init(self.allocator);
            var samplers = ArrayList(GltfAnimationSampler).init(self.allocator);

            for (0..ai_anim.mNumChannels) |channel_idx| {
                const ai_channel = ai_anim.mChannels[channel_idx];
                try self.processAnimationChannel(ai_channel, ai_anim, &channels, &samplers);
            }

            const gltf_animation = GltfAnimation{
                .name = anim_name,
                .channels = try channels.toOwnedSlice(),
                .samplers = try samplers.toOwnedSlice(),
            };

            try self.animations.append(gltf_animation);
        }

        fn processAnimationChannel(self: *AnimationExporter, ai_channel: *const assimp.aiNodeAnim, ai_animation: *const assimp.aiAnimation, channels: *ArrayList(GltfAnimationChannel), samplers: *ArrayList(GltfAnimationSampler)) !void {
            const node_name = ai_channel.mNodeName.data[0..ai_channel.mNodeName.length];
            std.debug.print("    Channel: node='{s}', pos_keys={d}, rot_keys={d}, scale_keys={d}\n", .{ node_name, ai_channel.mNumPositionKeys, ai_channel.mNumRotationKeys, ai_channel.mNumScalingKeys });

            // Translation channel
        if (ai_channel.mNumPositionKeys > 0) {
                const time_accessor = try self.writeTranslationKeyframes(ai_channel, ai_animation);
                const position_accessor = try self.writePositionKeyframes(ai_channel, ai_animation);

                const sampler_idx: u32 = @intCast(samplers.items.len);
                try samplers.append(GltfAnimationSampler{
                    .input = time_accessor,
                    .output = position_accessor,
                });

                try channels.append(GltfAnimationChannel{
                    .sampler = sampler_idx,
                    .target = GltfAnimationChannelTarget{
                        .node = 0, // TODO: Find node index by name
                    .path = "translation",
                    },
                });
            }

            // Rotation channel
        if (ai_channel.mNumRotationKeys > 0) {
                const time_accessor = try self.writeRotationTimeKeyframes(ai_channel, ai_animation);
                const rotation_accessor = try self.writeRotationKeyframes(ai_channel, ai_animation);

                const sampler_idx: u32 = @intCast(samplers.items.len);
                try samplers.append(GltfAnimationSampler{
                    .input = time_accessor,
                    .output = rotation_accessor,
                });

                try channels.append(GltfAnimationChannel{
                    .sampler = sampler_idx,
                    .target = GltfAnimationChannelTarget{
                        .node = 0, // TODO: Find node index by name
                    .path = "rotation",
                    },
                });
            }

            // Scale channel
        if (ai_channel.mNumScalingKeys > 0) {
                const time_accessor = try self.writeScaleTimeKeyframes(ai_channel, ai_animation);
                const scale_accessor = try self.writeScaleKeyframes(ai_channel, ai_animation);

                const sampler_idx: u32 = @intCast(samplers.items.len);
                try samplers.append(GltfAnimationSampler{
                    .input = time_accessor,
                    .output = scale_accessor,
                });

                try channels.append(GltfAnimationChannel{
                    .sampler = sampler_idx,
                    .target = GltfAnimationChannelTarget{
                        .node = 0, // TODO: Find node index by name
                    .path = "scale",
                    },
                });
            }
        }

        // Helper function to convert ASSIMP time to glTF time (seconds)
    fn convertTimeToSeconds(time: f64, ticks_per_second: f64) f32 {
            const tps = if (ticks_per_second == 0.0) 25.0 else ticks_per_second; // Default to 25 FPS
        return @floatCast(time / tps);
        }

        // Write translation keyframe timestamps
    fn writeTranslationKeyframes(self: *AnimationExporter, ai_channel: *const assimp.aiNodeAnim, ai_animation: *const assimp.aiAnimation) !u32 {
            const start_offset: u32 = @intCast(self.binary_data.items.len);

            // Write time data
        for (0..ai_channel.mNumPositionKeys) |i| {
                const time = self.convertTimeToSeconds(ai_channel.mPositionKeys[i].mTime, ai_animation.mTicksPerSecond);
                try self.binary_data.writer().writeAll(std.mem.asBytes(&time));
            }

            const byte_length: u32 = @intCast(self.binary_data.items.len - start_offset);

            // Create buffer view
        const buffer_view = GltfBufferView{
                .buffer = 0,
                .byteOffset = start_offset,
                .byteLength = byte_length,
            };

            const buffer_view_idx: u32 = @intCast(self.buffer_views.items.len);
            try self.buffer_views.append(buffer_view);

            // Create accessor
        const accessor = GltfAccessor{
                .bufferView = buffer_view_idx,
                .componentType = 5126, // FLOAT
            .count = @intCast(ai_channel.mNumPositionKeys),
                .type = "SCALAR",
            };

            const accessor_idx: u32 = @intCast(self.accessors.items.len);
            try self.accessors.append(accessor);

            return accessor_idx;
        }

        // Write position keyframe data
    fn writePositionKeyframes(self: *AnimationExporter, ai_channel: *const assimp.aiNodeAnim, ai_animation: *const assimp.aiAnimation) !u32 {
            _ = ai_animation;
            const start_offset: u32 = @intCast(self.binary_data.items.len);

            // Write position data
        for (0..ai_channel.mNumPositionKeys) |i| {
                const pos = ai_channel.mPositionKeys[i].mValue;
                const position = [3]f32{ pos.x, pos.y, pos.z };
                try self.binary_data.writer().writeAll(std.mem.asBytes(&position));
            }

            const byte_length: u32 = @intCast(self.binary_data.items.len - start_offset);

            // Create buffer view
        const buffer_view = GltfBufferView{
                .buffer = 0,
                .byteOffset = start_offset,
                .byteLength = byte_length,
            };

            const buffer_view_idx: u32 = @intCast(self.buffer_views.items.len);
            try self.buffer_views.append(buffer_view);

            // Create accessor
        const accessor = GltfAccessor{
                .bufferView = buffer_view_idx,
                .componentType = 5126, // FLOAT
            .count = @intCast(ai_channel.mNumPositionKeys),
                .type = "VEC3",
            };

            const accessor_idx: u32 = @intCast(self.accessors.items.len);
            try self.accessors.append(accessor);

            return accessor_idx;
        }

        // Write rotation keyframe timestamps
    fn writeRotationTimeKeyframes(self: *AnimationExporter, ai_channel: *const assimp.aiNodeAnim, ai_animation: *const assimp.aiAnimation) !u32 {
            const start_offset: u32 = @intCast(self.binary_data.items.len);

            // Write time data
        for (0..ai_channel.mNumRotationKeys) |i| {
                const time = self.convertTimeToSeconds(ai_channel.mRotationKeys[i].mTime, ai_animation.mTicksPerSecond);
                try self.binary_data.writer().writeAll(std.mem.asBytes(&time));
            }

            const byte_length: u32 = @intCast(self.binary_data.items.len - start_offset);

            // Create buffer view
        const buffer_view = GltfBufferView{
                .buffer = 0,
                .byteOffset = start_offset,
                .byteLength = byte_length,
            };

            const buffer_view_idx: u32 = @intCast(self.buffer_views.items.len);
            try self.buffer_views.append(buffer_view);

            // Create accessor
        const accessor = GltfAccessor{
                .bufferView = buffer_view_idx,
                .componentType = 5126, // FLOAT
            .count = @intCast(ai_channel.mNumRotationKeys),
                .type = "SCALAR",
            };

            const accessor_idx: u32 = @intCast(self.accessors.items.len);
            try self.accessors.append(accessor);

            return accessor_idx;
        }

        // Write rotation keyframe data
    fn writeRotationKeyframes(self: *AnimationExporter, ai_channel: *const assimp.aiNodeAnim, ai_animation: *const assimp.aiAnimation) !u32 {
            _ = ai_animation;
            const start_offset: u32 = @intCast(self.binary_data.items.len);

            // Write quaternion data (x, y, z, w)
        for (0..ai_channel.mNumRotationKeys) |i| {
                const rot = ai_channel.mRotationKeys[i].mValue;
                const quaternion = [4]f32{ rot.x, rot.y, rot.z, rot.w };
                try self.binary_data.writer().writeAll(std.mem.asBytes(&quaternion));
            }

            const byte_length: u32 = @intCast(self.binary_data.items.len - start_offset);

            // Create buffer view
        const buffer_view = GltfBufferView{
                .buffer = 0,
                .byteOffset = start_offset,
                .byteLength = byte_length,
            };

            const buffer_view_idx: u32 = @intCast(self.buffer_views.items.len);
            try self.buffer_views.append(buffer_view);

            // Create accessor
        const accessor = GltfAccessor{
                .bufferView = buffer_view_idx,
                .componentType = 5126, // FLOAT
            .count = @intCast(ai_channel.mNumRotationKeys),
                .type = "VEC4",
            };

            const accessor_idx: u32 = @intCast(self.accessors.items.len);
            try self.accessors.append(accessor);

            return accessor_idx;
        }

        // Write scale keyframe timestamps
    fn writeScaleTimeKeyframes(self: *AnimationExporter, ai_channel: *const assimp.aiNodeAnim, ai_animation: *const assimp.aiAnimation) !u32 {
            const start_offset: u32 = @intCast(self.binary_data.items.len);

            // Write time data
        for (0..ai_channel.mNumScalingKeys) |i| {
                const time = self.convertTimeToSeconds(ai_channel.mScalingKeys[i].mTime, ai_animation.mTicksPerSecond);
                try self.binary_data.writer().writeAll(std.mem.asBytes(&time));
            }

            const byte_length: u32 = @intCast(self.binary_data.items.len - start_offset);

            // Create buffer view
        const buffer_view = GltfBufferView{
                .buffer = 0,
                .byteOffset = start_offset,
                .byteLength = byte_length,
            };

            const buffer_view_idx: u32 = @intCast(self.buffer_views.items.len);
            try self.buffer_views.append(buffer_view);

            // Create accessor
        const accessor = GltfAccessor{
                .bufferView = buffer_view_idx,
                .componentType = 5126, // FLOAT
            .count = @intCast(ai_channel.mNumScalingKeys),
                .type = "SCALAR",
            };

            const accessor_idx: u32 = @intCast(self.accessors.items.len);
            try self.accessors.append(accessor);

            return accessor_idx;
        }

        // Write scale keyframe data
    fn writeScaleKeyframes(self: *AnimationExporter, ai_channel: *const assimp.aiNodeAnim, ai_animation: *const assimp.aiAnimation) !u32 {
            _ = ai_animation;
            const start_offset: u32 = @intCast(self.binary_data.items.len);

            // Write scale data
        for (0..ai_channel.mNumScalingKeys) |i| {
                const scale = ai_channel.mScalingKeys[i].mValue;
                const scale_data = [3]f32{ scale.x, scale.y, scale.z };
                try self.binary_data.writer().writeAll(std.mem.asBytes(&scale_data));
            }

            const byte_length: u32 = @intCast(self.binary_data.items.len - start_offset);

            // Create buffer view
        const buffer_view = GltfBufferView{
                .buffer = 0,
                .byteOffset = start_offset,
                .byteLength = byte_length,
            };

            const buffer_view_idx: u32 = @intCast(self.buffer_views.items.len);
            try self.buffer_views.append(buffer_view);

            // Create accessor
        const accessor = GltfAccessor{
                .bufferView = buffer_view_idx,
                .componentType = 5126, // FLOAT
            .count = @intCast(ai_channel.mNumScalingKeys),
                .type = "VEC3",
            };

            const accessor_idx: u32 = @intCast(self.accessors.items.len);
            try self.accessors.append(accessor);

            return accessor_idx;
        }
    };
}
