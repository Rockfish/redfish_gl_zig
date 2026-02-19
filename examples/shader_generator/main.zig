const std = @import("std");
const sc = @import("shader_compose.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize generator with module search paths
    var generator = sc.ShaderGenerator.init(allocator, &.{"modules"});
    defer generator.deinit();

    // ========================================================================
    // Example 1: Simple PBR Material
    // ========================================================================
    const pbr_recipe = sc.ShaderRecipe{
        .name = "pbr_standard",
        .vertex_modules = &.{"transforms/standard"},
        .fragment_modules = &.{
            "sampling/texture",
            "material/pbr_maps",
            "lighting/pbr",
            "output/hdr",
        },
        .vertex_inputs = &.{
            .{ .name = "position", .type = .vec3, .location = 0 },
            .{ .name = "normal", .type = .vec3, .location = 1 },
            .{ .name = "uv", .type = .vec2, .location = 2 },
        },
        .vertex_outputs = &.{
            .{ .name = "world_position", .type = .vec3 },
            .{ .name = "world_normal", .type = .vec3 },
            .{ .name = "frag_uv", .type = .vec2 },
        },
        .uniforms = &.{},
        .uniform_blocks = &.{
            .{
                .name = "Transforms",
                .binding = 0,
                .members = &.{
                    .{ .name = "model", .type = .mat4 },
                    .{ .name = "view_projection", .type = .mat4 },
                },
            },
        },
        .defines = &.{
            .{ .name = "MAX_LIGHTS", .value = "4" },
        },
    };

    const pbr_shader = generator.generate(pbr_recipe) catch |err| {
        std.debug.print("Failed to generate PBR shader: {}\n", .{err});
        return;
    };

    std.debug.print("=== Generated PBR Vertex Shader ===\n{s}\n\n", .{pbr_shader.vertex_source});
    std.debug.print("=== Generated PBR Fragment Shader ===\n{s}\n\n", .{pbr_shader.fragment_source});

    // ========================================================================
    // Example 2: Unlit/Debug Material (minimal modules)
    // ========================================================================
    const unlit_recipe = sc.ShaderRecipe{
        .name = "unlit_textured",
        .vertex_modules = &.{"transforms/standard"},
        .fragment_modules = &.{
            "sampling/texture",
        },
        .vertex_inputs = &.{
            .{ .name = "position", .type = .vec3, .location = 0 },
            .{ .name = "normal", .type = .vec3, .location = 1 },
            .{ .name = "uv", .type = .vec2, .location = 2 },
        },
        .vertex_outputs = &.{
            .{ .name = "world_position", .type = .vec3 },
            .{ .name = "world_normal", .type = .vec3 },
            .{ .name = "frag_uv", .type = .vec2 },
        },
        .uniforms = &.{},
        .uniform_blocks = &.{
            .{
                .name = "Transforms",
                .binding = 0,
                .members = &.{
                    .{ .name = "model", .type = .mat4 },
                    .{ .name = "view_projection", .type = .mat4 },
                },
            },
        },
    };

    // For the unlit shader, we need an inline module that bridges to final_color
    // Let's register it directly
    try generator.registerModule(.{
        .name = "output/unlit",
        .stage = .fragment,
        .requires = &.{
            .{ .name = "base_color", .type = .vec4 },
        },
        .provides = &.{
            .{ .name = "final_color", .type = .vec4 },
        },
        .uniforms = &.{},
        .uniform_blocks = &.{},
        .code =
        \\void output_unlit() {
        \\    final_color = base_color;
        \\}
        ,
    });

    // Update recipe to use the inline module
    var unlit_recipe_with_output = unlit_recipe;
    unlit_recipe_with_output.fragment_modules = &.{
        "sampling/texture",
        "output/unlit",
    };

    const unlit_shader = generator.generate(unlit_recipe_with_output) catch |err| {
        std.debug.print("Failed to generate unlit shader: {}\n", .{err});
        return;
    };

    std.debug.print("=== Generated Unlit Fragment Shader ===\n{s}\n\n", .{unlit_shader.fragment_source});
}
