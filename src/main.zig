const std = @import("std");

const jsonic = @import("jsonic");

const Mongo = @import("mongo").Mongo;


pub fn main() !void {
    std.debug.print("Hello, World!\n", .{});

    var gpa_mem = std.heap.DebugAllocator(.{}).init;
    defer std.debug.assert(gpa_mem.deinit() == .ok);
    const heap = gpa_mem.allocator();

    // Let's start from here...

    _ = heap;

    const uri = "mongodb://localhost:27017/?maxPoolSize=50";
    const mongo_db = try Mongo.init(true, uri, "drug_db");
    defer mongo_db.deinit();

    const db = mongo_db.database();
    defer db.free();

    const coll = db.collection("generic_name");
    defer coll.free();

    // const db = mongo_db.database();
    // defer db.free();

    // const coll = db.collection("drug_template");
    // defer coll.free();


    // std.debug.print("Total {} docs.\n", .{count});


//     const db = mongo_db.database();
//     defer db.free();

    const acid = try db.session();
    defer acid.free();

    try acid.start();

    const res = db.hasCollection("bar");
    std.debug.print("has coll: {}\n", .{res});

    if (res) try acid.end(.Commit) else try acid.end(.Abort);
}
