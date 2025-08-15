const std = @import("std");

const retain_ = @import("retain.zig");
const remove_ = @import("remove.zig");

pub const retain = retain_.retain;
pub const removeRange = remove_.removeRange;

/// Create a c_str using a local buffer avoiding allocation
pub fn bufCopyZ(buf: []u8, source: []const u8) [:0]const u8 {
    std.mem.copyForwards(u8, buf, source);
    buf[source.len] = 0;
    return buf[0..source.len :0];
}

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

// Cheap string hash
pub fn stringHash(str: []const u8, seed: u32) u32 {
    var hash: u32 = seed;
    if (str.len == 0) return hash;

    for (str) |char| {
        hash = ((hash << 5) - hash) + @as(u32, @intCast(char));
    }
    return hash;
}

pub fn strchr(str: []const u8, c: u8) ?usize {
    for (str, 0..) |char, i| {
        if (char == c) {
            return i;
        }
    }
    return null;
}

/// Generate a timestamp string in format: YYYY-MM-DD_HH.MM.SS.mmm
pub fn generateTimestamp() [23]u8 {
    const timestamp = std.time.timestamp();
    const epoch_seconds: u64 = @intCast(timestamp);
    const millis = @as(u64, @intCast(std.time.milliTimestamp())) % 1000;

    // Convert to local time structure
    const epoch_day = epoch_seconds / (24 * 60 * 60);
    const day_seconds = epoch_seconds % (24 * 60 * 60);

    const hour = day_seconds / 3600;
    const minute = (day_seconds % 3600) / 60;
    const second = day_seconds % 60;

    // Simple date calculation (approximate)
    const days_since_epoch = epoch_day;
    const year = 1970 + days_since_epoch / 365;
    const month = ((days_since_epoch % 365) / 30) + 1;
    const day = ((days_since_epoch % 365) % 30) + 1;

    var result: [23]u8 = undefined;
    _ = std.fmt.bufPrint(
        &result,
        "{d:0>4}-{d:0>2}-{d:0>2}_{d:0>2}.{d:0>2}.{d:0>2}.{d:0>3}",
        .{ year, month, day, hour, minute, second, millis },
    ) catch @panic("Failed to generate timestamp string");

    return result;
}
