const std = @import("std");

const content_dir = "assets/";

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    // b.verbose = true;

    const miniaudio = b.dependency("miniaudio", .{
        .target = target,
        .optimize = optimize,
    });

    const miniaudiolib = miniaudio.artifact("miniaudio");
    miniaudiolib.addIncludePath(miniaudio.path("include"));
    b.installArtifact(miniaudiolib);

    const cglm = b.dependency("cglm", .{
        .target = target,
        .optimize = optimize,
    });

    const cglmlib = cglm.artifact("cglm");
    cglmlib.addIncludePath(cglm.path("include"));
    b.installArtifact(cglmlib);

    const zglfw = b.dependency("zglfw", .{
        .target = target,
        .optimize = optimize,
    });

    const zopengl = b.dependency("zopengl", .{
        .target = target,
        // .optimize = optimize,
    });

    const zgui = b.dependency("zgui", .{
        .target = target,
        .optimize = optimize,
        .backend = .glfw_opengl3,
        .with_te = true,
        .shared = false,
    });

    const zstbi = b.dependency("zstbi", .{
        .target = target,
        .optimize = optimize,
    });

    const math = b.createModule(.{ .root_source_file = b.path("src/math/main.zig") });
    math.addIncludePath(b.path("src/include"));

    const core = b.createModule(.{ .root_source_file = b.path("src/core/main.zig") });

    core.addImport("math", math);
    core.addImport("zopengl", zopengl.module("root"));
    core.addImport("zgui", zgui.module("root"));
    core.addImport("zstbi", zstbi.module("root"));
    core.addImport("miniaudio", miniaudio.module("root"));

    core.linkLibrary(zstbi.artifact("zstbi"));

    inline for ([_]struct {
        name: []const u8,
        exe_name: []const u8,
        source: []const u8,
    }{
        // .{ .name = "main", .exe_name = "core_main", .source = "src/main.zig" },
        // .{ .name = "animation", .exe_name = "animation_example", .source = "examples/sample_animation/sample_animation.zig" },
        // .{ .name = "assimp_report", .exe_name = "assimp_report", .source = "examples/assimp_report/assimp_report.zig" },
        // .{ .name = "bullets", .exe_name = "bullets_example", .source = "examples/bullets/main.zig" },
        // .{ .name = "audio", .exe_name = "audio_example", .source = "examples/audio/main.zig" },
        // .{ .name = "gui_settings", .exe_name = "gui_example", .source = "examples/gui_settings/gui_settings.zig" },
        // .{ .name = "skybox", .exe_name = "skybox_example", .source = "examples/skybox/main.zig" },
        // .{ .name = "picker", .exe_name = "picker_example", .source = "examples/picker/main.zig" },
        // .{ .name = "ray_selection", .exe_name = "ray_selection_example", .source = "examples/ray_selection/main.zig" },
        // .{ .name = "scene_tree", .exe_name = "scene_tree_example", .source = "examples/scene_tree/main.zig" },
        // .{ .name = "game_level_001", .exe_name = "game_level_001", .source = "game_level_001/main.zig" },
        .{ .name = "zgltf_port", .exe_name = "zgltf_port", .source = "examples/zgltf_port/main.zig" },
        // .{ .name = "chat_gltf", .exe_name = "chat_gltf", .source = "examples/chat_gltf/main.zig" },
    }) |app| {
        const exe = b.addExecutable(.{
            .name = app.exe_name,
            .root_source_file = b.path(app.source),
            .target = target,
            .optimize = optimize,
        });

        // exe.addCxxFlag("-std=c++14");

        if (exe.root_module.optimize == .ReleaseFast) {
            exe.root_module.strip = true;
        }

        exe.root_module.addImport("math", math);
        exe.root_module.addImport("core", core);
        exe.root_module.addImport("cglm", cglm.module("root"));
        exe.root_module.addImport("miniaudio", miniaudio.module("root"));
        exe.root_module.addImport("zglfw", zglfw.module("root"));
        exe.root_module.addImport("zopengl", zopengl.module("root"));
        exe.root_module.addImport("zgui", zgui.module("root"));
        exe.root_module.addImport("zstbi", zstbi.module("root")); // gui

        exe.addIncludePath(b.path("src/include"));
        exe.addIncludePath(miniaudio.path("include"));

        exe.linkLibrary(zgui.artifact("imgui"));
        exe.linkLibrary(zglfw.artifact("glfw"));
        exe.linkLibrary(cglm.artifact("cglm"));
        exe.linkLibrary(miniaudio.artifact("miniaudio"));

        const install_exe = b.addInstallArtifact(exe, .{});

        b.getInstallStep().dependOn(&install_exe.step);
        b.step(app.name, "Build '" ++ app.name ++ "' app").dependOn(&install_exe.step);

        const run_exe = b.addRunArtifact(exe);
        run_exe.step.dependOn(&install_exe.step);

        if (b.args) |args| {
            run_exe.addArgs(args);
        }

        b.step(app.name ++ "-run", "Run '" ++ app.name ++ "' app").dependOn(&run_exe.step);

        const exe_options = b.addOptions();
        exe.root_module.addOptions("build_options", exe_options);
        exe_options.addOption([]const u8, "content_dir", content_dir);

        const install_content_step = b.addInstallDirectory(.{
            .source_dir = b.path(content_dir),
            .install_dir = .{ .custom = "" },
            .install_subdir = "bin/" ++ content_dir,
        });

        run_exe.step.dependOn(&install_content_step.step);
    }

    // extra check step for the game for better zls
    // See https://kristoff.it/blog/improving-your-zls-experience/
    const exe_check = b.addExecutable(.{
        .name = "angry_monsters",
        .root_source_file = b.path("examples/zgltf_port/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_check.root_module.addImport("math", math);
    exe_check.root_module.addImport("core", core);
    exe_check.root_module.addImport("cglm", cglm.module("root"));
    exe_check.root_module.addImport("miniaudio", miniaudio.module("root"));
    exe_check.root_module.addImport("zglfw", zglfw.module("root"));
    exe_check.root_module.addImport("zopengl", zopengl.module("root"));
    exe_check.linkLibrary(miniaudio.artifact("miniaudio"));
    exe_check.linkLibrary(zglfw.artifact("glfw"));
    exe_check.linkLibrary(cglm.artifact("cglm"));
    exe_check.addIncludePath(b.path("src/include"));
    exe_check.addIncludePath(miniaudio.path("include"));

    const check = b.step("check", "Check if game compiles");
    check.dependOn(&exe_check.step);

    // Add test step for movement
    const movement_tests = b.addTest(.{
        .root_source_file = b.path("src/core/movement.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add required dependencies
    movement_tests.root_module.addImport("math", math);
    movement_tests.root_module.addImport("cglm", cglm.module("root"));
    movement_tests.addIncludePath(b.path("src/include"));
    movement_tests.linkLibrary(cglm.artifact("cglm"));

    const run_movement_tests = b.addRunArtifact(movement_tests);
    const test_step = b.step("test-movement", "Run movement tests");
    test_step.dependOn(&run_movement_tests.step);
}

pub const Options = struct {
    optimize: std.builtin.Mode,
    target: std.Build.ResolvedTarget,
};
