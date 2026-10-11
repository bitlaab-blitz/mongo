const std = @import("std");

const jsonic = @import("jsonic");

const Mongo = @import("mongo").Mongo;


pub fn main(init: std.process.Init) !void {
    std.debug.print("Code coverage examples\n", .{});

    const heap = init.gpa;

    // Let's start from here...

    const uri = "mongodb://localhost:27017?maxPoolSize=50&replicaSet=rs0&serverSelectionTimeoutMS=5000&connectTimeoutMS=10000&retryWrites=true&retryReads=true";
    var mongo_db = try Mongo.init(init.io, true, uri, "your_example_db");
    defer mongo_db.deinit();

    // Database and Collection handles
    {
        const db = try mongo_db.database();
        defer db.free();

        const exist = try db.hasCollection("bar");
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

            const cursor = try coll.find(null, null);
            defer cursor.free();

            while (try cursor.next(heap, User)) |doc| {
                defer jsonic.free(heap, doc);

                std.debug.print("{s}\n", .{doc.name});
                std.debug.print("{d}\n", .{doc.age});
            }
        }

        // Update documents
        {
            // Filter built directly from a Zig structure

            const filter = try Mongo.toBsonDoc(.{ .name = "john" });
            defer Mongo.bsonFree(filter);

            // Update document built from formatted JSON

            const update = try Mongo.bsonBuildLarge(&mongo_db, heap, null,
                \\ {{ "$set": {{ "age": {d} }} }}
                ,.{56}
            );
            defer Mongo.bsonFree(update);

            const matched_1 = try coll.updateOne(filter, update, null);
            std.debug.print("Matched {} document\n", .{matched_1});

            const matched_2 = try coll.updateMany(filter, update, null);
            std.debug.print("Matched {} documents\n", .{matched_2});
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

        // Aggregate documents
        {
            const pipeline = try Mongo.bsonBuild(&mongo_db, null,
                \\ [{{
                \\      "$match": {{
                \\          "age": {{ "$gte": {d} }}
                \\      }}
                \\ }},
                \\ {{
                \\      "$project": {{
                \\          "name": 1,
                \\          "age": 1
                \\      }}
                \\ }},
                \\ {{
                \\      "$sort": {{
                \\          "age": -1
                \\      }}
                \\ }}]
                ,.{18}
            );
            defer Mongo.bsonFree(pipeline);

            const Info = struct { name: []const u8, age: u8 };

            const cursor = try coll.aggregate(pipeline);
            defer cursor.free();

            while (try cursor.next(heap, Info)) |doc| {
                defer jsonic.free(heap, doc);

                std.debug.print(
                    "name: {s} | age: {d}\n",
                    .{doc.name, doc.age}
                );
            }
        }

        // Create, list and delete indexes
        {
            const model_1 = try Mongo.indexModelCreate(heap, "name", .Asc, false);
            defer Mongo.indexModelDestroy(model_1);
            try coll.indexCreate(&model_1);

            const model_2 = try Mongo.indexModelCreate(heap, "age", .Desc, false);
            defer Mongo.indexModelDestroy(model_2);
            try coll.indexCreate(&model_2);

            // Lists all indexes

            {
                const cursor = try coll.findIndexes();
                defer cursor.free();

                while (try cursor.next(heap, Mongo.IndexData)) |doc| {
                    defer jsonic.free(heap, doc);
                    std.debug.print("v: {} | name: {s}\n", .{doc.v, doc.name});
                }
            }

            // Deletes an index

            try coll.deleteIndex("age_index");
        }

        // Create a temporary collection and drop it
        {
            const temp = db.collection("temp_demo");
            defer temp.free();

            try temp.insertOne(heap, .{.note = "scratch"}, null);
            try temp.drop();
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

        // Rename the collection

        try coll.rename("your_example_db", "foo_archive");

        // Deletes the entire database
        // **CAUTION:** Destructive operation, CAN NOT be undone!

        try db.drop();
    }

    // Resets the connection pool
    // **CAUTION:** All database handles must be freed first!

    try mongo_db.resetPool();
    std.debug.print("Connection pool reset\n", .{});

    // Build a nested document from Zig structures
    {
        const Address = struct { city: []const u8, zip: u32 };

        const Profile = struct {
            name: []const u8,
            age: u8,
            tags: []const []const u8,
            address: Address
        };

        const profile = Profile{
            .name = "john",
            .age = 31,
            .tags = &.{ "admin", "staff" },
            .address = .{.city = "nyc", .zip = 10001}
        };

        const doc = try Mongo.toBsonDoc(profile);
        defer Mongo.bsonFree(doc);

        const out = try Mongo.bsonToJsonString(doc);
        defer Mongo.bsonFreeJson(out);

        std.debug.print("{s}\n", .{out});
    }

    // Append properties to an existing document
    {
        const q = Mongo.bsonNew();
        defer Mongo.bsonFree(q);

        try Mongo.bsonAddProp(q, "num_i32", 2_147_483_647);
        try Mongo.bsonAddProp(q, "num_i64", 2_147_483_648);

        const Foo = enum { Bar, Baz };
        const foo = Foo.Bar;

        try Mongo.bsonAddProp(q, "name", "cool cat");
        try Mongo.bsonAddProp(q, "tag1", foo);
        try Mongo.bsonAddProp(q, "tag2", .Baz);

        const bar1: ?i32 = null;
        const bar2: ?i32 = 5000;

        try Mongo.bsonSetProp(q, "bar1", bar1);
        try Mongo.bsonSetProp(q, "bar2", bar2);
        try Mongo.bsonSetProp(q, "bar3", null);

        const out = try Mongo.bsonToJsonString(q);
        defer Mongo.bsonFreeJson(out);

        std.debug.print("{s}\n", .{out});
    }
}
