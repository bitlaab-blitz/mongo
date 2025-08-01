const std = @import("std");

const jsonic = @import("jsonic");
const Mongo = @import("mongo").Mongo;


pub fn main() !void {
    std.debug.print("Hello, World!\n", .{});

    var gpa_mem = std.heap.DebugAllocator(.{}).init;
    defer std.debug.assert(gpa_mem.deinit() == .ok);
    const heap = gpa_mem.allocator();

    // Let's start from here...

    // _ = heap;

    const uri = "mongodb://localhost:27017/?maxPoolSize=50";
    const mongo_db = try Mongo.init(true, uri, "drug_db");
    defer mongo_db.deinit();

    // const db = mongo_db.database("foo");
    // defer db.free();

    // const res = db.hasCollection("bar");
    // std.debug.print("has coll: {}\n", .{res});

    // const coll = db.collection("bar");
    // defer coll.free();

    // try coll.drop();

    // const res2 = db.hasCollection("bar");
    // std.debug.print("has coll: {}\n", .{res2});

    // try db.drop();


    // const Drug = struct { uuid: []const u8, name: []const u8, created_at: i64 };

    // const db = mongo_db.database();
    // defer db.free();

    // const coll = db.collection("generic_name");
    // defer coll.free();

    // //const x = try Mongo.bsonBuild("", .{});

    // const res = try coll.count(null, null);
    // std.debug.print("res: {}\n", .{res});

    // const cursor = coll.find(null, null);
    // defer cursor.free();

    // var count: usize = 0;
    // while (try cursor.next(heap, Drug)) |doc| {
    //     defer jsonic.free(heap, doc) catch unreachable;

    //     count += 1;
    //     // std.debug.print("{s}\n", .{doc.name});
    //     // std.debug.print("{s}\n", .{doc.uuid});
    //     // std.debug.print("{d}\n", .{doc.created_at});
    // }

    // std.debug.print("Find {} documents.\n", .{count});

    const User = struct { name: []const u8, age: u8 };

    const db = mongo_db.database();
    defer db.free();

    const coll = db.collection("foo");
    defer coll.free();

    // const user = User {.name = "john", .age = 31};
    // try coll.insertOne(heap, user);

    const users = [_]User {
        .{.name = "john doe", .age = 31},
        .{.name = "jane doe", .age = 28}
    };

    try coll.insertMany(heap, users[0..]);

}
