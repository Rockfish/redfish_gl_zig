const std = @import("std");
const containers = @import("containers");
const debug = std.debug;
const testing = std.testing;

pub fn retain(comptime TA: type, comptime TS: type, list: *containers.ManagedArrayList(?TA), filter: TS) void {
    const length = list.list.items.len;
    var i: usize = 0;
    var f: usize = 0;
    var flag = true;
    var count: usize = 0;

    while (true) {
        // test if false
        if (i < length and (list.list.items[i] == null or !filter.predicate(list.list.items[i].?))) {
            if (flag) {
                f = i;
                flag = false;
            }

            while (i < length and (list.list.items[i] == null or !filter.predicate(list.list.items[i].?))) {
                i += 1;
            }

            // move true to here
            if (i < length) {
                const delete = list.list.items[f];
                list.list.items[f] = list.list.items[i];
                list.list.items[i] = null;

                if (delete != null and @typeInfo(TA) == .pointer) {
                    delete.?.deinit();
                }
                f += 1;
                count += 1;
            }
        } else {
            count += 1;
            // fill in gaps
            if (i < length and f < i and flag == false) {
                const delete = list.list.items[f];
                list.list.items[f] = list.list.items[i];
                list.list.items[i] = null;

                if (delete != null and @typeInfo(TA) == .pointer) {
                    delete.?.deinit();
                }
                f += 1;
            }
        }
        i += 1;
        if (i >= length) {
            break;
        }
    }

    // delete remainder
    if (count < length) {
        for (list.list.items[count..length]) |d| {
            if (d != null and @typeInfo(TA) == .pointer) {
                d.?.deinit();
            }
        }
        list.shrinkRetainingCapacity(count);
    }
}

test "retain.retainObject" {
    debug.print("\n", .{});
    const a = testing.allocator;

    const testItem = struct {
        value: u32,
        const Self = @This();

        const Tester = struct {
            max_value: u32 = 0,
            const This = @This();
            pub fn predicate(self: *const This, item: Self) bool {
                // return item.value < self.max_value;
                _ = self;
                return @mod(item.value, 2) == 0;
            }
        };
    };

    const items = a.create(std.ArrayList(?testItem)) catch unreachable;
    items.* = containers.ManagedArrayList(?testItem).init(a);

    debug.print("items type = {s}\n", .{@typeName(@TypeOf(items))});

    for (0..10) |i| {
        const tv: testItem = .{ .value = @intCast(i) };
        items.append(tv) catch unreachable;
    }

    for (items.items, 0..) |item, c| {
        debug.print("{d} : item = {any}\n", .{ c, item });
    }

    debug.print("\n", .{});

    const tester = testItem.Tester{ .max_value = 5 };

    retain(testItem, testItem.Tester, items, tester, a) catch unreachable;

    for (items.items, 0..) |item, c| {
        debug.print("{d} : item = {any}\n", .{ c, item });
    }

    items.deinit();
    a.destroy(items);
}

test "retain.retainPointerObject" {
    debug.print("\n", .{});
    const a = testing.allocator;

    const TestItemPtr = struct {
        value: u32,
        a: std.mem.Allocator,

        const Self = @This();

        pub fn deinit(self: *Self) void {
            self.a.destroy(self);
        }

        const Tester = struct {
            max_value: u32 = 0,
            const This = @This();
            pub fn predicate(self: *const This, item: *Self) bool {
                // return item.value < self.max_value;
                _ = self;
                return @mod(item.value, 2) == 0;
            }
        };
    };

    const items = a.create(containers.ManagedArrayList(?*TestItemPtr)) catch unreachable;
    items.* = std.ArrayList(?*TestItemPtr).init(a);

    debug.print("items type = {s}\n", .{@typeName(@TypeOf(items))});

    for (0..10) |i| {
        const tv: *TestItemPtr = a.create(TestItemPtr) catch unreachable;
        tv.* = .{ .value = @intCast(i), .a = a };
        items.append(tv) catch unreachable;
    }

    for (items.list.items, 0..) |item, c| {
        debug.print("{d} : item = {any}\n", .{ c, item });
    }

    debug.print("\n", .{});

    const tester = TestItemPtr.Tester{ .max_value = 5 };

    retain(*TestItemPtr, TestItemPtr.Tester, items, tester, a) catch unreachable;

    for (items.list.items, 0..) |item, c| {
        debug.print("{d} : item = {any}\n", .{ c, item });
    }

    for (items.list.items) |item| {
        item.?.deinit();
    }

    items.deinit();
    a.destroy(items);
}
