const std = @import("std");
const core = @import("core");
const zstbi = @import("zstbi");
const zopengl = @import("zopengl");
const gl = @import("zopengl").bindings;
const utils = @import("utils/main.zig");
const gltf_types = @import("gltf/gltf.zig");
const GltfAsset = @import("asset_loader.zig").GltfAsset;

const ArenaAllocator = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;

pub const Texture = struct {
    gltf_texture_id: usize,
    gl_texture_id: u32,
    width: u32,
    height: u32,

    const Self = @This();

    pub fn deleteGlTexture(self: *const Texture) void {
        gl.deleteTextures(1, &self.gl_texture_id);
    }

    // Initialize from glTF texture reference
    pub fn init(
        arena: *ArenaAllocator,
        gltf_asset: *GltfAsset,
        directory: []const u8,
        texture_index: usize,
    ) !*Texture {
        const allocator = arena.allocator();

        const gltf_texture = gltf_asset.gltf.textures.?[texture_index];
        const source_id = gltf_texture.source orelse std.debug.panic("texture.source null not supported.", .{});
        const gltf_image = gltf_asset.gltf.images.?[source_id];

        zstbi.init(allocator);
        defer zstbi.deinit();

        // GLTF defines UV coordinates with a top-left origin
        // OpenGL assumes texture coordinates have a bottom-left origin
        // So always flip vertical
        // zstbi.setFlipVerticallyOnLoad(true);  // hmm, except not for CesiumMan

        var image = loadImage(allocator, gltf_asset, gltf_image, directory);
        defer image.deinit();

        const sampler = blk: {
            if (gltf_texture.sampler) |sampler_id| {
                break :blk gltf_asset.gltf.samplers.?[sampler_id];
            } else {
                break :blk gltf_types.Sampler{};
            }
        };

        const gl_texture_id = createGlTexture(image, sampler);

        const texture = try allocator.create(Texture);
        texture.* = Texture{
            .gltf_texture_id = texture_index,
            .gl_texture_id = @intCast(gl_texture_id),
            .width = image.width,
            .height = image.height,
        };
        // std.debug.print("Texture loaded: {any}, image components: {d}\n", .{ texture, image.num_components });
        return texture;
    }

    // Initialize from custom file path with configuration (for manual texture assignment)
    pub fn initFromFile(
        arena: *ArenaAllocator,
        file_path: []const u8,
        config: @import("asset_loader.zig").TextureConfig,
    ) !*Texture {
        const allocator = arena.allocator();

        zstbi.init(allocator);
        defer zstbi.deinit();

        zstbi.setFlipVerticallyOnLoad(config.flip_v);

        var image = zstbi.Image.loadFromFile(try allocator.dupeZ(u8, file_path), 0) catch |err| {
            std.debug.print("Custom texture loadFromFile error: {any}  filepath: {s}\n", .{ err, file_path });
            return err;
        };
        defer image.deinit();

        // Create custom sampler from config
        const sampler = gltf_types.Sampler{
            .wrap_s = switch (config.wrap) {
                .Clamp => .clamp_to_edge,
                .Repeat => .repeat,
            },
            .wrap_t = switch (config.wrap) {
                .Clamp => .clamp_to_edge,
                .Repeat => .repeat,
            },
            .mag_filter = switch (config.filter) {
                .Linear => .linear,
                .Nearest => .nearest,
            },
            .min_filter = switch (config.filter) {
                .Linear => .linear_mipmap_linear,
                .Nearest => .nearest,
            },
        };

        const gl_texture_id = createGlTexture(image, sampler);

        const texture = try allocator.create(Texture);
        texture.* = Texture{
            .gltf_texture_id = 0, // Not from glTF
            .gl_texture_id = @intCast(gl_texture_id),
            .width = image.width,
            .height = image.height,
        };

        std.debug.print("Custom texture loaded: {s}, dimensions: {d}x{d}\n", .{ file_path, texture.width, texture.height });
        return texture;
    }

    pub fn clone(self: *const Self) !*Texture {
        const texture = try self.allocator.create(Texture);
        texture.* = Texture{
            .gltf_texture_id = self.gltf_texture_id,
            .gl_texture_id = self.gl_texture_id,
            .width = self.width,
            .height = self.height,
            .allocator = self.allocator,
        };
        return texture;
    }
};

pub fn loadImage(allocator: Allocator, gltf_asset: *GltfAsset, gltf_image: gltf_types.Image, directory: []const u8) zstbi.Image {
    if (gltf_image.uri) |uri| {
        if (std.mem.eql(u8, uri[0..5], "data:")) {
            const comma = utils.strchr(uri, ',');
            if (comma) |idx| {
                const decoder = std.base64.standard.Decoder;
                const decoded_length = decoder.calcSizeForSlice(uri[idx..uri.len]) catch |err| {
                    std.debug.panic("Texture base64 decoder error: {any}\n", .{err});
                };
                const data_buffer: []align(4) u8 = allocator.allocWithOptions(u8, decoded_length, 4, null) catch |err| {
                    std.debug.panic("Texture allocator error: {any}\n", .{err});
                };
                decoder.decode(data_buffer, uri[idx..uri.len]) catch |err| {
                    std.debug.panic("Texture base64 decoder error: {any}\n", .{err});
                };
                // zstbi will own the data_buffer and free it on image deinit.
                const image = zstbi.Image.loadFromMemory(data_buffer, 0) catch |err| {
                    std.debug.print("Texture loadFromMemory error: {any}  using uri: {any}\n", .{ err, uri[0..5] });
                    @panic(@errorName(err));
                };
                std.debug.print("Image loaded from uri: {s}\n", .{uri});
                return image;
            }
            std.debug.panic("Texture uri malformed. uri: {any}", .{uri});
        } else {
            const c_path = std.fs.path.joinZ(allocator, &[_][]const u8{ directory, uri }) catch |err| {
                std.debug.panic("Texture allocator error: {any}\n", .{err});
            };
            defer allocator.free(c_path);
            std.debug.print("Loading texture from file: {s}\n", .{c_path});
            // Try forcing RGBA (4 channels) to handle sRGB images properly
            const image = zstbi.Image.loadFromFile(c_path, 4) catch |err| {
                std.debug.print("Texture loadFromFile error: {any}  filepath: {s}\n", .{ err, c_path });
                @panic(@errorName(err));
            };
            return image;
        }
    } else if (gltf_image.buffer_view) |buffer_view_id| {
        const buffer_view = gltf_asset.gltf.buffer_views.?[buffer_view_id];

        // TODO: testing the length of the buffer should include the byte_offset:width:
        // const data = gltf_asset.buffer_data.items[buffer_view.buffer][buffer_view.byte_offset..buffer_view.byte_length];
        const data = gltf_asset.buffer_data.items[buffer_view.buffer][buffer_view.byte_offset .. buffer_view.byte_offset + buffer_view.byte_length];

        const image = zstbi.Image.loadFromMemory(data, 0) catch |err| {
            std.debug.print("Texture loadFromMemory error: {any}  bufferview: {any}\n", .{ err, buffer_view });
            @panic(@errorName(err));
        };
        return image;
    } else {
        std.debug.panic("Gltf Image needs either a uri or a bufferview.", .{});
    }
}

pub fn createGlTexture(image: zstbi.Image, sampler: gltf_types.Sampler) c_uint {
    const format: u32 = switch (image.num_components) {
        0 => gl.RED,
        3 => gl.RGB,
        4 => gl.RGBA,
        else => gl.RED,
    };

    var gl_texture_id: gl.Uint = undefined;

    gl.genTextures(1, &gl_texture_id);
    gl.bindTexture(gl.TEXTURE_2D, gl_texture_id);

    gl.texImage2D(
        gl.TEXTURE_2D,
        0,
        format,
        @intCast(image.width),
        @intCast(image.height),
        0,
        format,
        gl.UNSIGNED_BYTE,
        image.data.ptr,
    );
    glSuccess("glTexImage2D");

    gl.generateMipmap(gl.TEXTURE_2D);

    const wrap_s: i32 = switch (sampler.wrap_s) {
        gltf_types.WrapMode.clamp_to_edge => gl.CLAMP_TO_EDGE,
        gltf_types.WrapMode.repeat => gl.REPEAT,
        gltf_types.WrapMode.mirrored_repeat => gl.MIRRORED_REPEAT,
    };

    const wrap_t: i32 = switch (sampler.wrap_t) {
        gltf_types.WrapMode.clamp_to_edge => gl.CLAMP_TO_EDGE,
        gltf_types.WrapMode.repeat => gl.REPEAT,
        gltf_types.WrapMode.mirrored_repeat => gl.MIRRORED_REPEAT,
    };

    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, wrap_s);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, wrap_t);

    const min_filter: gl.Int = blk: {
        if (sampler.min_filter) |filter| {
            break :blk switch (filter) {
                gltf_types.MinFilter.nearest => gl.NEAREST,
                gltf_types.MinFilter.linear => gl.LINEAR,
                gltf_types.MinFilter.nearest_mipmap_nearest => gl.NEAREST_MIPMAP_NEAREST,
                gltf_types.MinFilter.nearest_mipmap_linear => gl.NEAREST_MIPMAP_LINEAR,
                gltf_types.MinFilter.linear_mipmap_nearest => gl.LINEAR_MIPMAP_NEAREST,
                gltf_types.MinFilter.linear_mipmap_linear => gl.LINEAR_MIPMAP_LINEAR,
            };
        } else {
            break :blk gl.LINEAR;
        }
    };

    const mag_filter: gl.Int = blk: {
        if (sampler.mag_filter) |filter| {
            break :blk switch (filter) {
                gltf_types.MagFilter.nearest => gl.NEAREST,
                gltf_types.MagFilter.linear => gl.LINEAR,
            };
        } else {
            break :blk gl.LINEAR;
        }
    };

    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, min_filter);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, mag_filter);

    return gl_texture_id;
}

pub fn glSuccess(func_name: []const u8) void {
    for (0..8) |_| {
        const error_code = gl.getError();
        if (error_code == gl.NO_ERROR) {
            break;
        }
        std.debug.print("GL error for function: {s}  error code: {d}\n", .{ func_name, error_code });
    }
}
