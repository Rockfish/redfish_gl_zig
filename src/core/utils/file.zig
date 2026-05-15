const std = @import("std");

const Io = std.Io;
const Allocator = std.mem.Allocator;

pub fn fileExists(path: []const u8) bool {
    const stat = std.fs.cwd().statFile(path) catch return false;
    return stat.kind == .file;
}

/// Attempts to fix odd file paths that might be found in model files.
/// Returns owned string
pub fn getExistsFilename(allocator: std.mem.Allocator, directory: []const u8, filename: []const u8) ![]const u8 {
    if (fileExists(filename)) {
        return allocator.dupe(u8, filename);
    }

    var path = try std.fs.path.join(allocator, &[_][]const u8{ directory, filename });

    if (fileExists(path)) {
        return path;
    }

    const filepath = try std.mem.replaceOwned(u8, allocator, filename, "\\", "/");
    defer allocator.free(filepath);

    const file_name = std.fs.path.basename(filepath);
    path = try std.fs.path.join(allocator, &[_][]const u8{ directory, file_name });

    if (fileExists(path)) {
        return path;
    }

    std.debug.print("getExistsFilename file not found error. initial filename: {s}  fixed filename: {s}\n", .{ filename, path });
    @panic("getExistsFilename file not found error.");
}

pub fn readFileToEnd(io: Io, allocator: Allocator, file_path: []const u8) ![]u8 {
    const file = try std.Io.Dir.cwd().openFile(io, file_path, .{});
    defer file.close(io);

    const file_size = try file.length(io);
    const buf = try allocator.alloc(u8, file_size);
    errdefer allocator.free(buf);

    const n = try file.readPositionalAll(io, buf, 0);
    if (n != buf.len) return error.UnexpectedEndOfFile;
    return buf;
}

pub fn readFileToEndZ(io: Io, allocator: Allocator, file_path: []const u8) ![:0]u8 {
    const file = try std.Io.Dir.cwd().openFile(io, file_path, .{});
    defer file.close(io);

    const file_size = try file.length(io);
    const buf = try allocator.allocSentinel(u8, file_size, 0);
    errdefer allocator.free(buf);

    const n = try file.readPositionalAll(io, buf, 0);
    if (n != buf.len) return error.UnexpectedEndOfFile;
    return buf;
}
