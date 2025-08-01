//! # High-level MongoDB Wrapper
//! **Remarks:** Only uses client pool for thread safety.

const std = @import("std");
const fmt = std.fmt;
const log = std.log;
const mem = std.mem;
const Allocator = mem.Allocator;

const jsonic = @import("jsonic");
const StaticJson = jsonic.StaticJson;
const DynamicJson = jsonic.DynamicJson;

const lib_mongo = @import("../binding/lib_mongo.zig");


const Str = []const u8;
const StrZ = [:0]const u8;
const StrC = [*c]const u8;

const Bson = lib_mongo.Bson;
const BsonPtr = [*c] lib_mongo.Bson;

const Cursor = lib_mongo.Cursor;

const Error = error {
    InvalidUri,
    InvalidQuery,
    InvalidCursor,
    DoesNotExists,
    OperationFailed,
    InvalidInputString
};

db_name: StrZ,
pool: lib_mongo.Pool,

const Self = @This();

/// # Initializes MongoDB Client
/// **Remarks:** Intended for internal use only.
pub fn init(debug_mode: bool, uri_string: StrZ, db_name: StrZ) Error!Self {
    // Whether any error log will be shown in the terminal
    if (debug_mode) lib_mongo.logSetHandler(lib_mongo.showErr, null)
    else lib_mongo.logSetHandler(null, null);

    lib_mongo.init();

    var err_res: lib_mongo.BsonError = undefined;
    const uri = lib_mongo.newUri(uri_string, &err_res);
    defer lib_mongo.destroyUri(uri);

    if (uri == null) {
        const fmt_str = "Code - {d} | {s}";
        log.err(fmt_str, .{err_res.code, @as(StrC, &err_res.message)});
        return Error.InvalidUri;
    }

    return .{.db_name = db_name, .pool = lib_mongo.clientPoolNew(uri)};
}

/// # Destroys MongoDB Client
/// **Remarks:** Intended for internal use only.
pub fn deinit(self: *const Self) void {
    lib_mongo.clientPoolDestroy(self.pool);
    lib_mongo.cleanUp();
}

/// # Returns a New Database Handle
/// **Remarks:** Returns default database from the `init()`.
///
/// **WARNING:** Return value must be freed by calling `Database.free()`.
pub fn database(self: *const Self) Database {
    const c = lib_mongo.clientPoolPop(self.pool);
    const d = lib_mongo.clientGetDatabase(c, self.db_name);
    return .{.pool = self.pool, .client = c, .instance = d};
}

/// # Returns a New Database Handle
/// **WARNING:** Return value must be freed by calling `Database.free()`.
pub fn databaseWith(self: *const Self, db_name: StrZ) void {
    const c = lib_mongo.clientPoolPop(self.pool);
    const d = lib_mongo.clientGetDatabase(c, db_name);
    return .{.pool = self.pool, .client = c, .instance = d};
}

/// # Builds BSON Document from formatted String
/// **Remarks:** Provided string must be a formatted JSON string.
/// **WARNING:** Return value must be freed by calling `Mongo.bsonFree()`.
pub fn bsonBuild(comptime fmt_str: Str, args: anytype) Error!BsonPtr {
    const doc = lib_mongo.bsonNew();
    errdefer lib_mongo.bsonDestroy(doc);

    const src = std.fmt.comptimePrint(fmt_str, args);

    var err_res: lib_mongo.BsonError = undefined;
    if(!lib_mongo.bsonFromJSON(doc, src, &err_res)) {
        const err_str = "Code - {d} | {s}";
        log.err(err_str, .{err_res.code, @as(StrC, &err_res.message)});
        return Error.InvalidInputString;
    }

    return if (lib_mongo.bsonValidate(doc)) |_| doc
    else Error.InvalidInputString;
}

/// # Destroys a BSON Document
pub fn bsonFree(doc: BsonPtr) void { lib_mongo.bsonDestroy(doc); }

//##############################################################################
//# DATABASE INTERFACE --------------------------------------------------------#
//##############################################################################

pub const Database = struct {
    pool: lib_mongo.Pool,
    client: lib_mongo.Client,
    instance: lib_mongo.Database,

    const DatabaseZ = *const Database;

    /// # Releases the Database Handle
    pub fn free(self: DatabaseZ) void {
        lib_mongo.destroyDatabase(self.instance);
        lib_mongo.clientPoolPush(self.pool, self.client);
    }

    /// # Deletes the Entire Database
    /// **CAUTION:** Destructive operation, CAN NOT be undone!
    pub fn drop(self: DatabaseZ) Error!void {
        var err_res: lib_mongo.BsonError = undefined;
        if(!lib_mongo.dropDatabase(self.instance, &err_res)) {
            const fmt_str = "Code - {d} | {s}";
            log.err(fmt_str, .{err_res.code, @as(StrC, &err_res.message)});
            return Error.DoesNotExists;
        }
    }

    /// # Checks Whether a Collection Exists
    pub fn hasCollection(self: DatabaseZ, name: StrZ) bool {
        var err_res: lib_mongo.BsonError = undefined;
        return lib_mongo.hasCollection(self.instance, name, &err_res);
    }

    /// # Returns a New Collection Handle
    /// **WARNING:** Return value must be freed by calling `Collection.free()`.
    pub fn collection(self: DatabaseZ, name: StrZ) Collection {
        const coll = lib_mongo.getCollection(self.instance, name);
        return .{.instance = coll};
    }
};

//##############################################################################
//# COLLECTION INTERFACE ------------------------------------------------------#
//##############################################################################

pub const Collection = struct {
    instance: lib_mongo.Collection,

    const CollectionZ = *const Collection;

    /// # Releases the Collection Handle
    pub fn free(self: *const Collection) void {
        lib_mongo.destroyCollection(self.instance);
    }

    /// # Deletes the Entire Collection
    /// **CAUTION:** Destructive operation, CAN NOT be undone!
    pub fn drop(self: CollectionZ) Error!void {
        var err_res: lib_mongo.BsonError = undefined;
        if(!lib_mongo.dropCollection(self.instance, &err_res)) {
            const fmt_str = "Code - {d} | {s}";
            log.err(fmt_str, .{err_res.code, @as(StrC, &err_res.message)});
            return Error.DoesNotExists;
        }
    }

    /// # Rename the Collection
    pub fn rename(self: CollectionZ, dest_db: StrZ, new_name: StrZ) Error!void {
        var err_res: lib_mongo.BsonError = undefined;
        const succeed = lib_mongo.renameCollection(
            self.instance, dest_db, new_name, &err_res
        );

        if (!succeed) {
            const fmt_str = "Code - {d} | {s}";
            log.err(fmt_str, .{err_res.code, @as(StrC, &err_res.message)});
            return Error.OperationFailed;
        }
    }

    /// # Returns the Total Number of Documents
    pub fn count(
        self: CollectionZ,
        filter: ?BsonPtr,
        options: ?BsonPtr
    ) Error!i64 {
        const flt = if (filter) |f| f else lib_mongo.bsonNew();
        defer if(filter == null) lib_mongo.bsonDestroy(flt);

        var reply: lib_mongo.Bson = undefined;
        var err_res: lib_mongo.BsonError = undefined;
        const rv = lib_mongo.countDocuments(
            self.instance, flt, options, &reply, &err_res
        );

        if (rv >= 0) return rv
        else {
            const fmt_str = "Code - {d} | {s}";
            log.err(fmt_str, .{err_res.code, @as(StrC, &err_res.message)});
            return Error.InvalidQuery;
        }
    }

    /// # Executes a Query
    /// **WARNING:** Return value must be freed by calling `Iterator.free()`.
    pub fn find(
        self: CollectionZ,
        filter: ?BsonPtr,
        options: ?BsonPtr
    ) Iterator {
        const flt = if (filter) |f| f else lib_mongo.bsonNew();
        defer if(filter == null) lib_mongo.bsonDestroy(flt);

        const cursor = lib_mongo.find(self.instance, flt, options);
        return .{.instance = cursor};
    }

    // # Inserts a Single Document
    pub fn insertOne(self: CollectionZ, heap: Allocator, data: anytype) !void {
        const json_str = try StaticJson.stringify(heap, data);
        defer heap.free(json_str);

        const json_strZ = try fmt.allocPrintZ(heap, "{s}", .{json_str});
        defer heap.free(json_strZ);

        const doc = lib_mongo.bsonNew();
        defer lib_mongo.bsonDestroy(doc);

        var err_res: lib_mongo.BsonError = undefined;

        if (!lib_mongo.bsonFromJSON(doc, json_strZ, &err_res)) {
            const fmt_str = "Code - {d} | {s}";
            log.err(fmt_str, .{err_res.code, @as(StrC, &err_res.message)});
            return Error.OperationFailed;
        }

        if (!lib_mongo.insertOne(self.instance, doc, &err_res)) {
            const fmt_str = "Code - {d} | {s}";
            log.err(fmt_str, .{err_res.code, @as(StrC, &err_res.message)});
            return Error.OperationFailed;
        }
    }

    /// # Inserts Multiple Documents
    /// **Remarks:** Data must a `[]const T`.
    pub fn insertMany(self: CollectionZ, heap: Allocator, data: anytype) !void {
        const docs = try heap.alloc([*c]Bson, data.len);
        for (0..docs.len) |i| docs[i] = lib_mongo.bsonNew();

        defer {
            for (docs) |doc| { if (doc) |d| lib_mongo.bsonDestroy(d); }
            heap.free(docs);
        }

        var err_res: lib_mongo.BsonError = undefined;

        for (data, 0..data.len) |item, i| {
            const json_str = try StaticJson.stringify(heap, item);
            defer heap.free(json_str);

            const json_strZ = try fmt.allocPrintZ(heap, "{s}", .{json_str});
            defer heap.free(json_strZ);

            if (!lib_mongo.bsonFromJSON(docs[i], json_strZ, &err_res)) {
                const fmt_str = "Code - {d} | {s}";
                log.err(fmt_str, .{err_res.code, @as(StrC, &err_res.message)});
                return Error.OperationFailed;
            }
        }

        if (!lib_mongo.insertMany(self.instance, @ptrCast(docs), &err_res)) {
            const fmt_str = "Code - {d} | {s}";
            log.err(fmt_str, .{err_res.code, @as(StrC, &err_res.message)});
            return Error.OperationFailed;
        }
    }
};

//##############################################################################
//# ITERATOR INTERFACE --------------------------------------------------------#
//##############################################################################

pub const Iterator = struct {
    instance: lib_mongo.Cursor,

    const IteratorZ = *const Iterator;

    /// # Releases the Cursor Handle
    pub fn free(self: IteratorZ) void {
        lib_mongo.destroyCursor(self.instance);
    }

    /// # Iterates the Cursor to the Next Document
    /// **WARNING:** Return value must be freed by calling `jsonic.free()`.
    pub fn next(self: Iterator, heap: Allocator, comptime T: type) !?T {
        var doc = lib_mongo.bsonNew();
        defer lib_mongo.bsonDestroy(doc);

        if (!lib_mongo.nextCursor(self.instance, @ptrCast(&doc))) {
            var err_res: lib_mongo.BsonError = undefined;
            if(lib_mongo.errorCursor(self.instance, &err_res)) {
                const fmt_str = "Code - {d} | {s}";
                log.err(fmt_str, .{err_res.code, @as(StrC, &err_res.message)});
                return Error.InvalidCursor;
            }

            return null;
        }

        const data = lib_mongo.bsonToJSON(doc);
        defer lib_mongo.bsonFree(@ptrCast(data));

        var json = try DynamicJson.init(heap, mem.span(data), .{});
        defer json.deinit();

        return try DynamicJson.parseInto(T, heap, json.data(), .{
            .ignore_unknown_fields = true
        });
    }
};



