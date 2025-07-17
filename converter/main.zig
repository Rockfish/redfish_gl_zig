const std = @import("std");
const core = @import("core");
const math = @import("math");

// ASSIMP integration for converter
const assimp = @import("assimp");
const simple_loader = @import("simple_loader.zig");
const gltf_exporter = @import("gltf_exporter.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== FBX to glTF Converter ===\n", .{});

    // Parse command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 3) {
        std.debug.print("Usage: {s} <input.fbx> <output.gltf>\n", .{args[0]});
        std.debug.print("Converts FBX/DAE files to glTF format\n", .{});
        return;
    }

    const input_file = args[1];
    const output_file = args[2];

    std.debug.print("Input:  {s}\n", .{input_file});
    std.debug.print("Output: {s}\n", .{output_file});

    // Phase 1: Load with ASSIMP
    std.debug.print("\n[1/2] Loading model with ASSIMP...\n", .{});
    var load_result = try simple_loader.loadModelWithAssimp(allocator, input_file);
    defer load_result.deinit();

    // Phase 2: Export to glTF
    std.debug.print("\n[2/2] Exporting to glTF format...\n", .{});
    var exporter = gltf_exporter.GltfExporter.init(allocator);
    defer exporter.deinit();
    try exporter.exportModel(&load_result.model, input_file, output_file, load_result.scene);

    std.debug.print("\nConversion completed successfully!\n", .{});
}
