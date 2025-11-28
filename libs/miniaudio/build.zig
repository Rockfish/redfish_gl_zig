const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Add cglm source files
    const sources = &[_][]const u8{
        "src/miniaudio.c",
    };

    const mod = b.addModule("root", .{
        .root_source_file = b.path("src/miniaudio.zig"),
        .optimize = optimize,
        .target = target,
    });

    const lib = b.addLibrary(.{
        .name = "miniaudio",
        .root_module = mod,
    });

    lib.addCSourceFiles(.{
        .root = b.path(""),
        .files = sources,
        .flags = &.{"-fno-sanitize=undefined"},
    });

    mod.addIncludePath(b.path("include"));

    lib.addIncludePath(b.path("include"));

    lib.installHeadersDirectory(
        b.path("include"),
        "",
        .{ .include_extensions = &.{ ".h", } },
    );

    // b.verbose = true;

    b.installArtifact(lib);
}
