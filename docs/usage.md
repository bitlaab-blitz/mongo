# How to use

First, import Mongo on your Zig source file.

```zig
const Mongo = @import("mongo").Mongo;
```

## Initial Setup

Following snippet will initialize a database connection with the specified pool size.

```zig
const uri = "mongodb://localhost:27017/?maxPoolSize=50";

var mongo_db = try Mongo.init(io, true, uri, "your_example_db");
defer mongo_db.deinit();
```

**Remarks:** The `io` handle comes from Zig's `std.process.Init` (e.g. `pub fn main(init: std.process.Init)`), and the boolean enables debug logging.

## Connect Client to a Database

By default, Mongo will connect to the database given in `init()`.

```zig
const db = try mongo_db.database();
defer db.free();
```

You can also connect to a specified database with:

```zig
const db = try mongo_db.databaseWith("your_custom_db");
defer db.free();
```

## Resetting the Connection Pool

**CAUTION:** Every outstanding database handle (borrowed client) must be freed
before resetting, otherwise it is an undefined behavior.

```zig
try mongo_db.resetPool();
```

**Remarks:** Concurrent `database()` calls are blocked until the reset is done.
Useful when a connection pool becomes unusable after a driver failure.

## Working with a Collection

After connecting to a database, you can start using a collection.

```zig
const coll = db.collection("foo");
defer coll.free();
```

Let's check if a collection exists on a database. The call fails with an error
when the existence check itself can not be performed.

```zig
const result = try db.hasCollection("bar");
std.debug.print("Collection exists: {}\n", .{result});
```

You can delete an entire collection with:

```zig
try coll.drop();
```

And rename it with:

```zig
try coll.rename("your_custom_db", "new_name");
```

**CAUTION:** `db.drop()` deletes the entire database and can not be undone.

## Building Documents

Documents are BSON documents. You can build them from formatted JSON or
directly from Zig structures.

### From Formatted JSON

```zig
const query = try Mongo.bsonBuild(&mongo_db, null,
    \\ {{ "name": "{s}" }}
    ,.{"john"}
);
defer Mongo.bsonFree(query);
```

**Remarks:** `{{` `}}` escapes are required because the input is a Zig format
string. For input larger than 4096 bytes, use `bsonBuildLarge()` (requires an
allocator):

```zig
const query = try Mongo.bsonBuildLarge(&mongo_db, heap, null,
    \\ {{ "name": "{s}" }}
    ,.{"john"}
);
defer Mongo.bsonFree(query);
```

### From Zig Structures

`toBsonDoc()` converts a Zig structure directly into a BSON document without
any JSON round-trip.

```zig
const doc = try Mongo.toBsonDoc(.{ .name = "john", .age = 31 });
defer Mongo.bsonFree(doc);
```

- Nested structures become sub-documents, slices/arrays become BSON arrays and
tagged unions are stored as `{ "tag": payload }`.
- Enum tags are stored as strings and optionals are stored as `null`.

### Appending Properties

```zig
const doc = Mongo.bsonNew();
defer Mongo.bsonFree(doc);

try Mongo.bsonAddProp(doc, "name", "john");
try Mongo.bsonAddProp(doc, "age", 31);

const middle_name: ?[]const u8 = null;
try Mongo.bsonSetProp(doc, "middle_name", middle_name); // NOP when null
```

**Remarks:** Enum tags are converted into strings, and `bsonSetProp()` is a
NO-OP when the value is `null`.

### Debug JSON

```zig
const json = try Mongo.bsonToJsonString(doc);
defer Mongo.bsonFreeJson(json);

std.debug.print("{s}\n", .{json});
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

const cursor = try coll.find(null, null);
defer cursor.free();

while (try cursor.next(heap, User)) |doc| {
    defer jsonic.free(heap, doc);

    std.debug.print("{s}\n", .{doc.name});
    std.debug.print("{d}\n", .{doc.age});
}
```

### Insert Document

Following example snippet will insert one or more documents on a collection.

```zig
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
```

### Update Document

Following example snippet will update one or more documents on a collection.
Filters and updates can be built either from formatted JSON or from Zig
structures with `toBsonDoc()`.

```zig
const filter = try Mongo.toBsonDoc(.{ .name = "john" });
defer Mongo.bsonFree(filter);

const update = try Mongo.bsonBuild(&mongo_db, null,
    \\ {{ "$set": {{ "age": {d} }} }}
    ,.{56}
);
defer Mongo.bsonFree(update);

const matched_1 = try coll.updateOne(filter, update, null);
std.debug.print("Matched {} document\n", .{matched_1});

const matched_2 = try coll.updateMany(filter, update, null);
std.debug.print("Matched {} documents\n", .{matched_2});
```

**Remarks:** `updateOne()` and `updateMany()` return the number of **matched**
documents.

### Delete Document

Following example snippet will delete one or more documents on a collection.

```zig
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
```

**Remarks:** Always use the above format for building any query such as **filter**, **options**, **pipeline** etc.

## ACID Session

Following example snippet pattern should be used to perform session transactions for multiple collections.

```zig
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
```

## Working with Indexes

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
const cursor = try coll.findIndexes();
defer cursor.free();

while (try cursor.next(heap, Mongo.IndexData)) |doc| {
    defer jsonic.free(heap, doc);
    std.debug.print("v: {} | name: {s}\n", .{doc.v, doc.name});
}
```

## Document Aggregation

Following example snippet will aggregate & project documents from a collection.

```zig
const Info = struct { uuid: []const u8, name: []const u8, created_at: i64 };

const pipeline = try Mongo.bsonBuild(&mongo_db, null,
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

const cursor = try coll.aggregate(pipeline);
defer cursor.free();

while (try cursor.next(heap, Info)) |doc| {
    defer jsonic.free(heap, doc);

    std.debug.print(
        "uuid: {s}\n name: {s}\n created_at {}\n",
        .{doc.uuid, doc.name, doc.created_at}
    );
}
```
