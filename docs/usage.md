# How to use

First, import Mongo on your Zig source file.

```zig
const Mongo = @import("mongo").Mongo;
```

## Initial Setup

Following snippet will initialize a database connection the specified pool size.

```zig
const uri = "mongodb://localhost:27017/?maxPoolSize=50";
const mongo_db = try Mongo.init(true, uri, "your_example_db");
defer mongo_db.deinit();
```

## Connect Client to a Database

By default, Mongo will connect to the database from the `init()`.

```zig
const db = mongo_db.database();
defer db.free();
```

You can also connect client to a specified database with:

```zig
const db = mongo_db.databaseWith("your_custom_db")
defer db.free();
```

## Working with a Collection

After connecting to a database, you can start using a collection.

```zig
const coll = db.collection("foo");
defer coll.free();
```

Let's check if a collection exists on a database.

```zig
const result = db.hasCollection("bar");
std.debug.print("Collection exists: {}\n", .{result});
```

You can delete an entire collection with:

```zig
try coll.drop();
```

## CRUD Operations on a Collection

### Count Documents

Following snippet will return the total number of documents in a given collection.

```zig
const result = try coll.count(null, null);
std.debug.print("Found: {} documents\n", .{result});
```

### Find Documents

Following example snippet will return matched documents progressively.

```zig
const User = struct { name: []const u8, age: u8 };

const cursor = coll.find(null, null);
defer cursor.free();

while (try cursor.next(heap, User)) |doc| {
    defer jsonic.free(heap, doc) catch unreachable;

    std.debug.print("{s}\n", .{doc.name});
    std.debug.print("{d}\n", .{doc.age});
}
```

### Insert Document

Following example snippet will insert one or more document on a collection.

```zig
const User = struct { name: []const u8, age: u8 };

// Inserts a single document

const user = User {.name = "john", .age = 31};
try coll.insertOne(heap, user);

// Inserts multiple documents

const users = [_]User {
    .{.name = "john doe", .age = 31},
    .{.name = "jane doe", .age = 28}
};

try coll.insertMany(heap, users[0..]);
```

### Delete Document

Following example snippet will delete one or more document on a collection.

```zig
const query = try Mongo.bsonBuild(
    \\ {{ "name": "{s}" }}
    ,.{"john"}
);
defer Mongo.bsonFree(query);

// Deletes a single document

const count_1 = try coll.deleteOne(query);
std.debug.print("Deleted {d} document\n", .{count_1});

// Deletes multiple documents

const count_2 = try coll.deleteMany(query);
std.debug.print("Deleted {d} documents\n", .{count_2});
```

**Remarks:** Always use the above format for building any query such as **filter**, **options**, **pipeline** etc.

### Update Document

Following example snippet will update one or more document on a collection.

```zig
const query = try Mongo.bsonBuild(
    \\ {{ "age": {d} }}
    ,.{31}
);
defer Mongo.bsonFree(query);

const update = try Mongo.bsonBuild(
    \\ {{ "$set": {{ "age": {d} }} }}
    ,.{56}
);
defer Mongo.bsonFree(update);

const result_1 = try coll.updateOne(query, update);
std.debug.print("Modified {} document\n", .{result_1});

const result_2 = try coll.updateMany(query, update);
std.debug.print("Modified {} documents\n", .{result_2});
```

### Create an Index

Following example snippet will create an index on a collection.

```zig
const model_1 = try Mongo.indexModelCreate(heap, "name", .Asc, true);
defer Mongo.indexModelDestroy(model_1);
try coll.indexCreate(&model_1);

const model_2 = try Mongo.indexModelCreate(heap, "age", .Desc, false);
defer Mongo.indexModelDestroy(model_2);
try coll.indexCreate(&model_2);
```

**Remarks:** Order (e.g., `.Asc`, `.Desc`) will tell MongoDB in which order the index should occur. The boolean unique value will enforce uniqueness on a given key.

### Delete an Index

Following example snippet will delete an index from a collection.

```zig
try coll.deleteIndex("name_index");
```

### Find Indexes

Following example snippet will show all available indexes on a collection.

```zig
const cursor = coll.findIndexes();
defer cursor.free();

while (try cursor.next(heap, Mongo.IndexData)) |doc| {
    defer jsonic.free(heap, doc) catch unreachable;
    std.debug.print("v: {} | name: {s}\n", .{doc.v, doc.name});
}
```

### Document Aggregation

Following example snippet will aggregate & project documents from a collection.

```zig
const Info = struct { uuid: Str, name: Str, created_at: i64 };

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

const cursor = coll.aggregate(pipeline);
defer cursor.free();

while (try cursor.next(heap, Info)) |doc| {
    defer jsonic.free(heap, doc) catch unreachable;

    std.debug.print(
        "uuid: {s}\n name: {s}\n created_at {}\n",
        .{doc.uuid, doc.name, doc.created_at}
    );
}
```

### ACID Session

Following example snippet pattern should be used to perform session transactions for multiple collections.

```zig
const acid = try db.session();
defer acid.free();

try acid.start();

const result = db.hasCollection("bar");
std.debug.print("Collection exists: {}\n", .{result});

if (some_res) try acid.end(.Commit) else try acid.end(.Abort);
```
