const std = @import("std");

pub fn ManagedArrayList(comptime T: type) type {
    return struct {
        unmanagedList: std.ArrayList(T),
        allocator: std.mem.Allocator,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .unmanagedList = std.ArrayList(T).empty,
                .allocator = allocator,
            };
        }

        pub fn initCapacity(allocator: std.mem.Allocator, cap: usize) !Self {
            return .{
                .unmanagedList = try std.ArrayList(T).initCapacity(allocator, cap),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.unmanagedList.deinit(self.allocator);
        }

        // forward std.ArrayList methods you use most
        pub fn append(self: *Self, item: T) !void {
            try self.unmanagedList.append(self.allocator, item);
        }

        pub fn appendSlice(self: *Self, itms: []const T) !void {
            try self.unmanagedList.appendSlice(self.allocator, itms);
        }

        pub fn toOwnedSlice(self: *Self) ![]T {
            return try self.unmanagedList.toOwnedSlice(self.allocator);
        }

        // forward the fields you need
        pub fn items(self: Self) []T { return self.unmanagedList.items; }

        pub fn len(self: Self) usize { return self.unmanagedList.items.len; }

        pub const Writer = if (T != u8) void else std.io.GenericWriter(*Self, std.mem.Allocator.Error, appendWrite);

        fn appendWrite(self: *Self, data: []const T) std.mem.Allocator.Error!usize {
            try self.unmanagedList.appendSlice(self.allocator, data);
            return data.len;
        }

        pub fn writer(self: *Self) Writer {
            return .{ .context = self };
        }

        pub fn clearRetainingCapacity(self: *Self) void {
            self.unmanagedList.clearRetainingCapacity();
        }

        pub fn clearAndFree(self: *Self) void {
            self.unmanagedList.clearAndFree(self.allocator);
        }

        pub fn ensureTotalCapacity(self: *Self, new_capacity: usize) !void {
            try self.unmanagedList.ensureTotalCapacity(self.allocator, new_capacity);
        }
    };
}