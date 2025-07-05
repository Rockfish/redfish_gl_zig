const std = @import("std");
const core = @import("core");
const assets_list = @import("assets_list.zig");

const GltfAsset = core.asset_loader.GltfAsset;
const GltfReport = core.gltf_report.GltfReport;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test with the first demo model
    const model_info = assets_list.demo_models[0];
    const path = try std.fs.path.join(allocator, &[_][]const u8{ assets_list.root, model_info.path });
    defer allocator.free(path);

    std.debug.print("Generating glTF report for: {s}\n", .{model_info.name});
    std.debug.print("Path: {s}\n\n", .{path});

    // Load the glTF asset
    var gltf_asset = try GltfAsset.init(allocator, model_info.name, path);
    defer gltf_asset.deinit();

    try gltf_asset.load();

    // Generate and print the report
    GltfReport.printReport(&gltf_asset);

    // Optionally write to file
    try GltfReport.writeReportToFile(allocator, &gltf_asset, "gltf_report.txt");
    std.debug.print("\nReport also written to: gltf_report.txt\n");
}
