const std = @import("std");

const content_dir = "assets/";

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    
    // Help ZLS understand our project structure
    const build_options = b.addOptions();
    build_options.addOption(bool, "enable_tracy", false);
    build_options.addOption([]const u8, "content_dir", content_dir);
    
    // b.verbose = true;

    const miniaudio = b.dependency("miniaudio", .{
        .target = target,
        .optimize = optimize,
    });

    const miniaudiolib = miniaudio.artifact("miniaudio");
    miniaudiolib.addIncludePath(miniaudio.path("include"));
    b.installArtifact(miniaudiolib);

    // CGLM - C math library (unused - prefer local src/math/ implementation)
    // const cglm = b.dependency("cglm", .{
    //     .target = target,
    //     .optimize = optimize,
    // });
    //
    // const cglmlib = cglm.artifact("cglm");
    // cglmlib.addIncludePath(cglm.path("include"));
    // b.installArtifact(cglmlib);

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

    const formats: []const u8 = "Obj,FBX,glTF,glTF2"; // B3D";

    const assimp = b.dependency("assimp", .{
        .target = target,
        .optimize = optimize,
        .formats = formats,
    });

    const math = b.createModule(.{ .root_source_file = b.path("src/math/main.zig") });
    math.addIncludePath(b.path("src/include"));

    const core = b.createModule(.{ .root_source_file = b.path("src/core/main.zig") });

    core.addImport("math", math);
    core.addImport("zopengl", zopengl.module("root"));
    core.addImport("zgui", zgui.module("root"));
    core.addImport("zstbi", zstbi.module("root"));
    core.addImport("miniaudio", miniaudio.module("root"));
    // core.addImport("cglm", cglm.module("root")); // UNUSED

    core.linkLibrary(zstbi.artifact("zstbi"));

    inline for ([_]struct {
        name: []const u8,
        exe_name: []const u8,
        source: []const u8,
    }{
        // .{ .name = "main", .exe_name = "core_main", .source = "src/main.zig" },
        .{ .name = "animation", .exe_name = "animation_example", .source = "examples/animation_example/main.zig" },
        // .{ .name = "assimp_report", .exe_name = "assimp_report", .source = "examples/assimp_report/assimp_report.zig" },
        // .{ .name = "bullets", .exe_name = "bullets_example", .source = "examples/bullets/main.zig" },
        // .{ .name = "audio", .exe_name = "audio_example", .source = "examples/audio/main.zig" },
        // .{ .name = "gui_settings", .exe_name = "gui_example", .source = "examples/gui_settings/gui_settings.zig" },
        // .{ .name = "skybox", .exe_name = "skybox_example", .source = "examples/skybox/main.zig" },
        // .{ .name = "picker", .exe_name = "picker_example", .source = "examples/picker/main.zig" },
        // .{ .name = "ray_selection", .exe_name = "ray_selection_example", .source = "examples/ray_selection/main.zig" },
        // .{ .name = "scene_tree", .exe_name = "scene_tree_example", .source = "examples/scene_tree/main.zig" },
        // .{ .name = "game_level_001", .exe_name = "game_level_001", .source = "game_level_001/main.zig" },
        .{ .name = "demo_app", .exe_name = "demo_app", .source = "examples/demo_app/main.zig" },
        .{ .name = "game_angrybot", .exe_name = "angry_monsters", .source = "game_angrybot/main.zig" },
        .{ .name = "converter", .exe_name = "fbx_gltf_converter", .source = "converter/main.zig" },
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
        // exe.root_module.addImport("cglm", cglm.module("root"));
        exe.root_module.addImport("miniaudio", miniaudio.module("root"));
        exe.root_module.addImport("zglfw", zglfw.module("root"));
        exe.root_module.addImport("zopengl", zopengl.module("root"));
        exe.root_module.addImport("zgui", zgui.module("root"));
        exe.root_module.addImport("zstbi", zstbi.module("root")); // gui
        exe.root_module.addImport("build_options", build_options.createModule());

        // Add ASSIMP support for converter app
        if (std.mem.eql(u8, app.name, "converter")) {
            exe.root_module.addImport("assimp", assimp.module("root"));
            exe.linkLibrary(assimp.artifact("assimp"));
            exe.addIncludePath(assimp.path("include"));
        }

        exe.addIncludePath(b.path("src/include"));
        exe.addIncludePath(miniaudio.path("include"));

        exe.linkLibrary(zgui.artifact("imgui"));
        exe.linkLibrary(zglfw.artifact("glfw"));
        // exe.linkLibrary(cglm.artifact("cglm"));
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
        .root_source_file = b.path("examples/demo_app/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_check.root_module.addImport("math", math);
    exe_check.root_module.addImport("core", core);
    // exe_check.root_module.addImport("cglm", cglm.module("root")); // UNUSED
    exe_check.root_module.addImport("miniaudio", miniaudio.module("root"));
    exe_check.root_module.addImport("zglfw", zglfw.module("root"));
    exe_check.root_module.addImport("zopengl", zopengl.module("root"));
    exe_check.root_module.addImport("zgui", zgui.module("root"));
    exe_check.root_module.addImport("zstbi", zstbi.module("root"));
    exe_check.root_module.addImport("build_options", build_options.createModule());
    exe_check.linkLibrary(zgui.artifact("imgui"));
    exe_check.linkLibrary(zstbi.artifact("zstbi"));
    exe_check.linkLibrary(miniaudio.artifact("miniaudio"));
    exe_check.linkLibrary(zglfw.artifact("glfw"));
    // exe_check.linkLibrary(cglm.artifact("cglm")); // UNUSED
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
    // movement_tests.root_module.addImport("cglm", cglm.module("root")); // UNUSED
    movement_tests.addIncludePath(b.path("src/include"));
    // movement_tests.linkLibrary(cglm.artifact("cglm")); // UNUSED

    const run_movement_tests = b.addRunArtifact(movement_tests);
    const test_step = b.step("test-movement", "Run movement tests");
    test_step.dependOn(&run_movement_tests.step);

    // Add GLB loading integration test
    const glb_test = b.addExecutable(.{
        .name = "glb_loading_test",
        .root_source_file = b.path("tests/integration/glb_loading_test.zig"),
        .target = target,
        .optimize = optimize,
    });

    glb_test.root_module.addImport("math", math);
    glb_test.root_module.addImport("core", core);
    glb_test.addIncludePath(b.path("src/include"));

    const run_glb_test = b.addRunArtifact(glb_test);
    const glb_test_step = b.step("test-glb", "Run GLB loading integration test");
    glb_test_step.dependOn(&run_glb_test.step);
}

pub const Options = struct {
    optimize: std.builtin.Mode,
    target: std.Build.ResolvedTarget,
};
