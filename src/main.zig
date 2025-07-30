const std = @import("std");

const Mongo = @import("mongo").Mongo;

pub fn main() !void {
    std.debug.print("Hello, World!\n", .{});

    var gpa_mem = std.heap.DebugAllocator(.{}).init;
    defer std.debug.assert(gpa_mem.deinit() == .ok);
    const heap = gpa_mem.allocator();

    // Let's start from here...

    _ = heap;

    Mongo.init();
}
