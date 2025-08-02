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

    // const User = struct { name: []const u8, age: u8 };

    // const db = mongo_db.database();
    // defer db.free();

    // const coll = db.collection("foo");
    // defer coll.free();

    // // const user = User {.name = "john", .age = 31};
    // // try coll.insertOne(heap, user);

    // const users = [_]User {
    //     .{.name = "john doe", .age = 31},
    //     .{.name = "jane doe", .age = 28}
    // };

    // try coll.insertMany(heap, users[0..]);


    // const db = mongo_db.database();
    // defer db.free();

    // const coll = db.collection("foo");
    // defer coll.free();

    // const query = try Mongo.bsonBuild(
    //     \\ {{ "name": "{s}" }}
    //     ,.{"john"}
    // );
    // defer Mongo.bsonFree(query);

    // const count = try coll.deleteOne(query);
    // std.debug.print("Count {}\n", .{count});

    // const count = try coll.deleteMany(query);
    // std.debug.print("Count {}\n", .{count});

    // const update = try Mongo.bsonBuild(
    //     \\ {{ "$set": {{ "age": {d} }} }}
    //     ,.{56}
    // );
    // defer Mongo.bsonFree(update);

    // const modified = try coll.updateOne(query, update);
    // std.debug.print("Modified {}\n", .{modified});


    // const db = mongo_db.database();
    // defer db.free();

    // const coll = db.collection("foo");
    // defer coll.free();

    // const query = try Mongo.bsonBuild(
    //     \\ {{ "age": {d} }}
    //     ,.{31}
    // );
    // defer Mongo.bsonFree(query);

    // const update = try Mongo.bsonBuild(
    //     \\ {{ "$set": {{ "age": {d} }} }}
    //     ,.{69}
    // );
    // defer Mongo.bsonFree(update);

    // const modified = try coll.updateMany(query, update);
    // std.debug.print("Modified {}\n", .{modified});

    // const db = mongo_db.database();
    // defer db.free();

    // const coll = db.collection("foo");
    // defer coll.free();

    // const model_1 = try Mongo.indexModelCreate(heap, "name", .Asc, true);
    // defer Mongo.indexModelDestroy(model_1);
    // try coll.indexCreate(&model_1);

    // const model_2 = try Mongo.indexModelCreate(heap, "age", .Desc, false);
    // defer Mongo.indexModelDestroy(model_2);
    // try coll.indexCreate(&model_2);

    // try coll.deleteIndex("name_index");

    // const cursor = coll.findIndexes();
    // defer cursor.free();

    // var count: usize = 0;
    // while (try cursor.next(heap, Mongo.IndexData)) |doc| {
    //     defer jsonic.free(heap, doc) catch unreachable;

    //     count += 1;
    //     std.debug.print("v: {} | name: {s}\n", .{doc.v, doc.name});
    // }

    // std.debug.print("Find {} indexes.\n", .{count});


    const db = mongo_db.database();
    defer db.free();

    const coll = db.collection("drug_template");
    defer coll.free();

    const pipeline = try Mongo.bsonBuild(
        \\ [{{
        \\      "$match": {{
        \\          "name": {{
        \\            "$regex": "^CAP\\."
        \\          }}
        \\      }}
        \\ }},
        \\ {{
        \\      "$project": {{
        \\          "uuid": 1,
        \\          "name": 1,
        \\          "created_at": 1
        \\      }}
        \\ }},
        \\ {{
        \\      "$sort": {{
        \\          "created_at": -1
        \\      }}
        \\ }}]
        ,.{}
    );
    defer Mongo.bsonFree(pipeline);

    const Info = struct { uuid: []const u8, name: []const u8, created_at: i64 };

    const cursor = coll.aggregate(pipeline);
    defer cursor.free();

    var count: usize = 0;
    while (try cursor.next(heap, Info)) |doc| {
        defer jsonic.free(heap, doc) catch unreachable;

        count += 1;
        std.debug.print(
            "uuid: {s}\n name: {s}\n created_at {}\n",
            .{doc.uuid, doc.name, doc.created_at}
        );
    }

    std.debug.print("Total {} docs.\n", .{count});
}
