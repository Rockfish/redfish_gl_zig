const std = @import("std");
const core = @import("core");
const math = @import("math");

const simple_loader = @import("simple_loader.zig");
const gltf_exporter = @import("gltf_exporter.zig");

fn printUsage(program_name: []const u8) void {
    std.debug.print("Usage: {s} [--verbose|-v] <input.fbx> <output.gltf>\n", .{program_name});
    std.debug.print("Converts FBX files to glTF format\n", .{});
    std.debug.print("\nOptions:\n", .{});
    std.debug.print("  --verbose, -v    Enable verbose output with detailed processing information\n", .{});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const base_allocator = gpa.allocator();

    // Use arena allocator for temporary allocations during conversion
    var arena = std.heap.ArenaAllocator.init(base_allocator);
    defer arena.deinit(); // Single cleanup at the end
    const allocator = arena.allocator();

    std.debug.print("=== FBX to glTF Converter ===\n", .{});

    // Parse command line arguments
    const args = try std.process.argsAlloc(allocator);

    var verbose = false;
    var input_file: ?[]const u8 = null;
    var output_file: ?[]const u8 = null;

    // Parse arguments
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--verbose") or std.mem.eql(u8, arg, "-v")) {
            verbose = true;
        } else if (input_file == null) {
            input_file = arg;
        } else if (output_file == null) {
            output_file = arg;
        } else {
            std.debug.print("Error: Too many arguments\n", .{});
            printUsage(args[0]);
            return;
        }
    }

    if (input_file == null or output_file == null) {
        printUsage(args[0]);
        return;
    }

    if (verbose) {
        std.debug.print("Input:  {s}\n", .{input_file.?});
        std.debug.print("Output: {s}\n", .{output_file.?});
    }

    // Phase 1: Load with ASSIMP
    if (verbose) {
        std.debug.print("\n[1/2] Loading model with ASSIMP...\n", .{});
    }
    var load_result = try simple_loader.loadModelWithAssimp(allocator, input_file.?, verbose);
    defer load_result.deinit();

    // Phase 2: Export to glTF
    if (verbose) {
        std.debug.print("\n[2/2] Exporting to glTF format...\n", .{});
    }
    var exporter = gltf_exporter.GltfExporter.init(allocator, verbose);
    defer exporter.deinit();

    // Print summary
    if (!verbose) {
        std.debug.print(
            "ASSIMP Loaded: {d} meshes, {d} animations, {d} bones",
            .{
                load_result.model.meshes.items.len,
                load_result.model.animations.items.len,
                load_result.model.bones.items.len,
            },
        );
        if (load_result.model.meshes.items.len > 0) {
            var total_vertices: u32 = 0;
            var total_indices: u32 = 0;
            for (load_result.model.meshes.items) |mesh| {
                total_vertices += @intCast(mesh.vertices.items.len);
                total_indices += @intCast(mesh.indices.items.len);
            }
            std.debug.print(", {d} vertices, {d} indices", .{ total_vertices, total_indices });
        }
        std.debug.print("\n", .{});
    }

    try exporter.exportModel(&load_result.model, input_file.?, output_file.?, load_result.scene);

    std.debug.print("Conversion completed successfully!\n", .{});
}
