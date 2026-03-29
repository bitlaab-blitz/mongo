const std = @import("std");

const jsonic = @import("jsonic");

const Mongo = @import("mongo").Mongo;


pub fn main() !void {
    std.debug.print("Code coverage examples\n", .{});

    var gpa_mem = std.heap.DebugAllocator(.{}).init;
    defer std.debug.assert(gpa_mem.deinit() == .ok);
    const heap = gpa_mem.allocator();

    // Let's start from here...

    const uri = "mongodb://localhost:27017?maxPoolSize=50&replicaSet=rs0&serverSelectionTimeoutMS=5000&connectTimeoutMS=10000&retryWrites=true&retryReads=true";
    const mongo_db = try Mongo.init(true, uri, "your_example_db");
    defer mongo_db.deinit();

    const db = mongo_db.database();
    defer db.free();

    const exist = db.hasCollection("bar");
    std.debug.print("Collection exists: {}\n", .{exist});

    const coll = db.collection("foo");
    defer coll.free();

    // Insert new document
    {
        const User = struct { name: []const u8, age: u8 };

        // Inserts a single document

        const user = User {.name = "john", .age = 31};
        try coll.insertOne(heap, user, null);

        // Inserts multiple documents

        const users = [_]User {
            .{.name = "john doe", .age = 31},
            .{.name = "jane doe", .age = 28}
        };

        try coll.insertMany(heap, users[0..], null);
    }

    // Count documents
    {
        const result = try coll.count(null, null);
        std.debug.print("Found: {} documents\n", .{result});
    }

    // Find documents
    {
        const User = struct { name: []const u8, age: u8 };

        const cursor = coll.find(null, null);
        defer cursor.free();

        while (try cursor.next(heap, User)) |doc| {
            defer jsonic.free(heap, doc) catch unreachable;

            std.debug.print("{s}\n", .{doc.name});
            std.debug.print("{d}\n", .{doc.age});
        }
    }

    // Delete document
    {
        const query = try Mongo.bsonBuild(&mongo_db, null,
            \\ {{ "name": "{s}" }}
            ,.{"john"}
        );
        defer Mongo.bsonFree(query);

        // Deletes a single document

        const count_1 = try coll.deleteOne(query, null);
        std.debug.print("Deleted {d} document\n", .{count_1});

        // Deletes multiple documents

        const count_2 = try coll.deleteMany(query, null);
        std.debug.print("Deleted {d} documents\n", .{count_2});

    }

    // Create index
    {
        const model_1 = try Mongo.indexModelCreate(heap, "name", .Asc, false);
        defer Mongo.indexModelDestroy(model_1);
        try coll.indexCreate(&model_1);

        const model_2 = try Mongo.indexModelCreate(heap, "age", .Desc, false);
        defer Mongo.indexModelDestroy(model_2);
        try coll.indexCreate(&model_2);
    }

    // Find indexes
    {
        const cursor = coll.findIndexes();
        defer cursor.free();

        while (try cursor.next(heap, Mongo.IndexData)) |doc| {
            defer jsonic.free(heap, doc) catch unreachable;
            std.debug.print("v: {} | name: {s}\n", .{doc.v, doc.name});
        }
    }

    // ACID
    {
        const acid = try db.session();
        defer acid.free();

        try acid.start();
        errdefer acid.end(.Abort) catch unreachable;

        const opts = Mongo.bsonNew();
        defer Mongo.bsonFree(opts);

        try acid.append(opts);

        const query = try Mongo.bsonBuild(&mongo_db, null,
            \\ {{ "name": "{s}" }}
            ,.{"john"}
        );
        defer Mongo.bsonFree(query);

        // Deletes a single document as ACID Session

        const count = try coll.deleteOne(query, opts);
        std.debug.print("ACID - Deleted {d} document\n", .{count});

        if (count == 1) try acid.end(.Commit) else try acid.end(.Abort);
    }

    {
        const q = Mongo.bsonNew();
        defer Mongo.bsonFree(q);

        try Mongo.bsonAddProp(heap, q, "num_i32", 2_147_483_647);
        try Mongo.bsonAddProp(heap, q, "num_i64", 2_147_483_648);

        const Foo = enum { Bar, Baz };
        const foo = Foo.Bar;

        try Mongo.bsonAddProp(heap, q, "name", "cool cat");
        try Mongo.bsonAddProp(heap, q, "tag1", foo);
        try Mongo.bsonAddProp(heap, q, "tag2", .Baz);

        const bar1: ?i32 = null;
        const bar2: ?i32 = 5000;

        try Mongo.bsonSetProp(heap, q, "bar1", bar1);
        try Mongo.bsonSetProp(heap, q, "bar2", bar2);
        try Mongo.bsonSetProp(heap, q, "bar3", null);

        const out = try Mongo.bsonToJsonString(heap, q);
        defer heap.free(out);

        std.debug.print("{s}\n", .{out});
    }
}
