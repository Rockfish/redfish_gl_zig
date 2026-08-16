const std = @import("std");
const glfw = @import("zglfw");
const zopengl = @import("zopengl");
const gl = zopengl.bindings;

pub fn main() !void {
    try glfw.init();
    defer glfw.terminate();

    const gl_major = 4;
    const gl_minor = 1;

    glfw.windowHint(.context_version_major, gl_major);
    glfw.windowHint(.context_version_minor, gl_minor);
    glfw.windowHint(.opengl_profile, .opengl_core_profile);
    glfw.windowHint(.client_api, .opengl_api);
    glfw.windowHint(.doublebuffer, true);
    glfw.windowHint(.opengl_forward_compat, true);
    glfw.windowHint(.visible, false);

    const window = try glfw.Window.create(64, 64, "gl_caps", null, null);
    defer window.destroy();

    glfw.makeContextCurrent(window);
    try zopengl.loadCoreProfile(glfw.getProcAddress, gl_major, gl_minor);

    printCaps();
}

fn printCaps() void {
    const joints: i64 = 100;
    const floats_per_mat4: i64 = 16;
    const bytes_per_mat4: i64 = 64;
    const texels_per_joint: i64 = 4;
    const palette_bytes = joints * bytes_per_mat4;
    const palette_texels = joints * texels_per_joint;
    const palette_components = joints * floats_per_mat4;

    std.debug.print("=== OpenGL context ===\n", .{});
    std.debug.print("  vendor:    {s}\n", .{glString(gl.VENDOR)});
    std.debug.print("  renderer:  {s}\n", .{glString(gl.RENDERER)});
    std.debug.print("  version:   {s}\n", .{glString(gl.VERSION)});
    std.debug.print("  glsl:      {s}\n", .{glString(gl.SHADING_LANGUAGE_VERSION)});

    const vert_uniform_components = glInt(gl.MAX_VERTEX_UNIFORM_COMPONENTS);
    const vert_uniform_vectors = glInt(gl.MAX_VERTEX_UNIFORM_VECTORS);
    const vert_uniform_blocks = glInt(gl.MAX_VERTEX_UNIFORM_BLOCKS);
    const combined_uniform_blocks = glInt(gl.MAX_COMBINED_UNIFORM_BLOCKS);
    const uniform_bindings = glInt(gl.MAX_UNIFORM_BUFFER_BINDINGS);
    const uniform_block_size = glInt(gl.MAX_UNIFORM_BLOCK_SIZE);
    const ubo_align = glInt(gl.UNIFORM_BUFFER_OFFSET_ALIGNMENT);
    const tex_buffer_size = glInt(gl.MAX_TEXTURE_BUFFER_SIZE);
    const tex_size = glInt(gl.MAX_TEXTURE_SIZE);
    const rect_tex_size = glInt(gl.MAX_RECTANGLE_TEXTURE_SIZE);
    const array_layers = glInt(gl.MAX_ARRAY_TEXTURE_LAYERS);
    const vert_tex_units = glInt(gl.MAX_VERTEX_TEXTURE_IMAGE_UNITS);
    const combined_tex_units = glInt(gl.MAX_COMBINED_TEXTURE_IMAGE_UNITS);
    const vert_attribs = glInt(gl.MAX_VERTEX_ATTRIBS);
    const vert_output_components = glInt(gl.MAX_VERTEX_OUTPUT_COMPONENTS);

    std.debug.print("\n=== Default-block uniforms (the current jointMatrices path) ===\n", .{});
    printLimit("MAX_VERTEX_UNIFORM_COMPONENTS", vert_uniform_components);
    printLimit("MAX_VERTEX_UNIFORM_VECTORS", vert_uniform_vectors);
    std.debug.print(
        "  100 mat4s use {d} components; leftover after one palette: {d}\n",
        .{ palette_components, vert_uniform_components - palette_components },
    );
    std.debug.print(
        "  default-block mat4 budget: {d}\n",
        .{@divTrunc(vert_uniform_components, floats_per_mat4)},
    );

    std.debug.print("\n=== Uniform buffers ===\n", .{});
    printLimit("MAX_VERTEX_UNIFORM_BLOCKS", vert_uniform_blocks);
    printLimit("MAX_COMBINED_UNIFORM_BLOCKS", combined_uniform_blocks);
    printLimit("MAX_UNIFORM_BUFFER_BINDINGS", uniform_bindings);
    printLimit("MAX_UNIFORM_BLOCK_SIZE", uniform_block_size);
    printLimit("UNIFORM_BUFFER_OFFSET_ALIGNMENT", ubo_align);
    std.debug.print(
        "  100-joint palettes per UBO: {d}  ({d} bytes each)\n",
        .{ @divTrunc(uniform_block_size, palette_bytes), palette_bytes },
    );

    std.debug.print("\n=== Texture buffers and 2D textures (crowd / instancing path) ===\n", .{});
    printLimit("MAX_TEXTURE_BUFFER_SIZE", tex_buffer_size);
    printLimit("MAX_TEXTURE_SIZE", tex_size);
    printLimit("MAX_RECTANGLE_TEXTURE_SIZE", rect_tex_size);
    printLimit("MAX_ARRAY_TEXTURE_LAYERS", array_layers);
    printLimit("MAX_VERTEX_TEXTURE_IMAGE_UNITS", vert_tex_units);
    printLimit("MAX_COMBINED_TEXTURE_IMAGE_UNITS", combined_tex_units);
    std.debug.print(
        "  100-joint palettes in one TBO: {d}  (400 texels each)\n",
        .{@divTrunc(tex_buffer_size, palette_texels)},
    );
    std.debug.print(
        "  pose-atlas rows if width = {d} texels: {d}\n",
        .{ palette_texels, tex_size },
    );
    std.debug.print(
        "  vertex-shader texture fetches available: {s}\n",
        .{if (vert_tex_units > 0) "yes" else "NO — texture skinning would fail"},
    );

    std.debug.print("\n=== Draw / vertex ===\n", .{});
    printLimit("MAX_VERTEX_ATTRIBS", vert_attribs);
    printLimit("MAX_VERTEX_OUTPUT_COMPONENTS", vert_output_components);
}

fn printLimit(name: []const u8, value: i32) void {
    std.debug.print("  {s}: {d}\n", .{ name, value });
}

fn glString(name: gl.Enum) []const u8 {
    const ptr = gl.getString(name);
    if (ptr == null) {
        return "(null)";
    }
    return std.mem.span(ptr);
}

fn glInt(pname: gl.Enum) i32 {
    var value: gl.Int = 0;
    gl.getIntegerv(pname, @ptrCast(&value));
    return value;
}
