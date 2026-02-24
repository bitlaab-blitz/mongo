//! # High-level MongoDB Wrapper
//! **Remarks:** Only uses client pool for thread safety.

const std = @import("std");
const fmt = std.fmt;
const log = std.log;
const mem = std.mem;
const math = std.math;
const Allocator = mem.Allocator;

const jsonic = @import("jsonic");
const StaticJSON = jsonic.StaticJSON;
const DynamicJSON = jsonic.DynamicJSON;

const lib_mongo = @import("../binding/lib_mongo.zig");


const Str = []const u8;
const StrZ = [:0]const u8;
const StrC = [*c]const u8;

const Bson = lib_mongo.Bson;
pub const BsonPtr = [*c] lib_mongo.Bson;

pub const IndexModel = lib_mongo.IndexModel;
pub const IndexData = struct { v: u8, name: []const u8 };

const IndexOrder = enum(i8) { Asc = 1, Desc = -1 };

const Error = error {
    InvalidUri,
    OutOfMemory,
    NoSpaceLeft,
    InvalidQuery,
    InvalidCursor,
    DoesNotExists,
    InsertionFailed,
    OperationFailed,
    InvalidInputString,
    UniqueConstraintViolation
};

db_name: StrZ,
debug_mode: bool,
uri: lib_mongo.Uri,
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

    if (uri == null) {
        if (debug_mode) {
            const fmt_str = "Code - {d} | {s}";
            log.err(fmt_str, .{err_res.code, @as(StrC, &err_res.message)});
        }

        return Error.InvalidUri;
    }

    return .{
        .db_name = db_name,
        .debug_mode = debug_mode,
        .uri = uri,
        .pool = lib_mongo.clientPoolNew(uri)
    };
}

/// # Destroys MongoDB Client
/// **Remarks:** Intended for internal use only.
pub fn deinit(self: *const Self) void {
    lib_mongo.clientPoolDestroy(self.pool);
    lib_mongo.destroyUri(self.uri);
    lib_mongo.cleanUp();
}

/// # Resets MongoDB Connection Pool
pub fn resetPool(self: *Self) void {
    lib_mongo.clientPoolDestroy(self.pool);
    self.pool = lib_mongo.clientPoolNew(self.uri);
}

/// # Returns a New Database Handle
/// **Remarks:** Returns default database from the `init()`.
///
/// **WARNING:** Return value must be freed by calling `Database.free()`.
pub fn database(self: *const Self) Database {
    const c = lib_mongo.clientPoolPop(self.pool);
    const d = lib_mongo.clientGetDatabase(c, self.db_name);
    return .{
        .debug_mode = self.debug_mode,
        .pool = self.pool,
        .client = c,
        .instance = d
    };
}

/// # Returns a New Database Handle
/// **WARNING:** Return value must be freed by calling `Database.free()`.
pub fn databaseWith(self: *const Self, db_name: StrZ) Database {
    const c = lib_mongo.clientPoolPop(self.pool);
    const d = lib_mongo.clientGetDatabase(c, db_name);
    return .{
        .debug_mode = self.debug_mode,
        .pool = self.pool,
        .client = c,
        .instance = d
    };
}

/// # Returns an Empty BSON Document
pub fn bsonNew() BsonPtr { return lib_mongo.bsonNew(); }

/// # Builds BSON Document from a Formatted JSON String
/// **WARNING:** Return value must be freed by calling `Mongo.bsonFree()`.
///
/// - `doc` - When **null**, builds from an empty BSON document
pub fn bsonBuild(
    self: *const Self,
    doc: ?BsonPtr,
    comptime fmt_str: Str,
    args: anytype
) Error!BsonPtr {
    var buff: [8192]u8 = undefined;
    const src = try std.fmt.bufPrintZ(&buff, fmt_str, args);

    var err_res: lib_mongo.BsonError = undefined;
    const bson = if (doc) |bson_doc| bson_doc else bsonNew();
    if(!lib_mongo.bsonFromJSON(bson, src, &err_res) and self.debug_mode) {
        const err_str = "Code - {d} | {s} \n {s}";
        log.err(err_str, .{err_res.code, @as(StrC, &err_res.message), src});
        return Error.InvalidInputString;
    }

    return if (lib_mongo.bsonValidate(bson)) |_| bson
    else Error.InvalidInputString;
}

/// # Builds BSON Document from a Formatted JSON String
/// **WARNING:** Return value must be freed by calling `Mongo.bsonFree()`.
///
/// - `doc` - When **null**, builds from an empty BSON document
///
/// **Remarks:** Same as `bsonBuild()`, use for arbitrarily long input data.
pub fn bsonBuildLarge(
    self: *const Self,
    heap: Allocator,
    doc: ?BsonPtr,
    comptime fmt_str: Str,
    args: anytype
) Error!BsonPtr {
    const src = try std.fmt.allocPrintSentinel(heap, fmt_str, args, 0);
    defer heap.free(src);

    var err_res: lib_mongo.BsonError = undefined;
    const bson = if (doc) |bson_doc| bson_doc else bsonNew();
    if(!lib_mongo.bsonFromJSON(bson, src, &err_res) and self.debug_mode) {
        const err_str = "Code - {d} | {s} \n {s}";
        log.err(err_str, .{err_res.code, @as(StrC, &err_res.message), src});
        return Error.InvalidInputString;
    }

    return if (lib_mongo.bsonValidate(bson)) |_| bson
    else Error.InvalidInputString;
}

/// # Adds a New Sub Document to the Given Parent Document
pub fn bsonAddDoc(doc: BsonPtr, name: StrZ, value: BsonPtr) !void {
    const succeed = lib_mongo.bsonAddDoc(doc, name, value);
    if (!succeed) return Error.InsertionFailed;
}

/// # Adds a New Property to the Given Document
///
/// **Remarks:**
/// - Any heap allocations are freed automatically.
/// - Enum tags gets converted into string.
/// - Passing optional value is supported.
pub fn bsonAddProp(
    heap: Allocator,
    doc: BsonPtr,
    name: Str,
    value: anytype
) !void {
    const T = @TypeOf(value);

    const key = try heap.allocSentinel(u8, name.len, 0);
    mem.copyForwards(u8, key, name);
    defer heap.free(key);

    switch (@typeInfo(T)) {
        .optional => {
            if (value) |v| try bsonAddProp(heap, doc, name, v)
            else {
                const succeed = lib_mongo.bsonAddNull(doc, key);
                if (!succeed) return Error.InsertionFailed;
            }
        },
        .null => {
            const succeed = lib_mongo.bsonAddNull(doc, key);
            if (!succeed) return Error.InsertionFailed;
        },
        .bool => {
            const succeed = lib_mongo.bsonAddBool(doc, key, value);
            if (!succeed) return Error.InsertionFailed;
        },
        .int, .comptime_int => {
            const min_i32 = math.minInt(i32);
            const max_i32 = math.maxInt(i32);
            const min_i64 = math.minInt(i64);
            const max_i64 = math.maxInt(i64);

            if (value >= min_i32 and value <= max_i32) {

                const succeed = lib_mongo.bsonAddInt32(
                    doc, key, @intCast(value)
                );
                if (!succeed) return Error.InsertionFailed;
            } else if (value >= min_i64 and value <= max_i64) {
                const succeed = lib_mongo.bsonAddInt64(
                    doc, key, @intCast(value)
                );
                if (!succeed) return Error.InsertionFailed;
            } else {
                const err_str = "mongo: `{s}` in BSON append is too big";
                @compileError(fmt.comptimePrint(err_str, .{@typeName(T)}));
            }
        },
        .float, .comptime_float => {
            const succeed = lib_mongo.bsonAddFloat64(doc, key, value);
            if (!succeed) return Error.InsertionFailed;
        },
        .@"enum", .@"enum_literal" => {
            const succeed = lib_mongo.bsonAddString(doc, key, @tagName(value));
            if (!succeed) return Error.InsertionFailed;
        },
        .pointer => |p| {
            switch (p.size) {
                .slice => {
                    // Handles []const u8
                    const val = try heap.allocSentinel(u8, value.len, 0);
                    mem.copyForwards(u8, val, value);
                    defer heap.free(val);

                    const succeed = lib_mongo.bsonAddString(doc, key, val);
                    if (!succeed) return Error.InsertionFailed;
                },
                .many => {
                    // Handles [*:0]const u8 - already null-terminated
                    const succeed = lib_mongo.bsonAddString(doc, key, value);
                    if (!succeed) return Error.InsertionFailed;
                },
                .one => {
                    // Handle *const [N:0]u8 (pointer to array)
                    const succeed = lib_mongo.bsonAddString(doc, key, value);
                    if (!succeed) return Error.InsertionFailed;
                },
                else => {
                    const err_str = "mongo: Invalid pointer size `{s}`";
                    @compileError(fmt.comptimePrint(err_str, .{@typeName(T)}));
                },
            }
        },
        else => {
            const err_str = "mongo: `{s}` in BSON append is not supported";
            @compileError(fmt.comptimePrint(err_str, .{@typeName(T)}));
        }
    }
}

/// # Adds a New Property to the Given Document
/// **Remarks:** Same as `bsonAddProp()`, except NOP when value is **null**.
pub fn bsonSetProp(heap: Allocator,
    doc: BsonPtr,
    name: Str,
    value: anytype
) !void {
    if (value != null) try bsonAddProp(heap, doc, name, value);
}

/// # Converts BSON Document into a JSON-Formatted String
/// **Remarks:** Intended to be used for debugging purposes.
///
/// - **WARNING:** Return value must be freed by the caller.
pub fn bsonToJsonString(heap: Allocator, doc: BsonPtr) !Str {
    const data = lib_mongo.bsonToJSON(doc);
    defer lib_mongo.bsonFree(@ptrCast(data));

    const json_str: []const u8 = mem.span(data);
    const out = try heap.alloc(u8, json_str.len);
    mem.copyForwards(u8, out, json_str);
    return out;
}

/// # Destroys a BSON Document
pub fn bsonFree(doc: BsonPtr) void { lib_mongo.bsonDestroy(doc); }

/// # Creates a New Index Model
pub fn indexModelCreate(
    heap: Allocator,
    doc_key: Str,
    order: IndexOrder,
    unique: bool
) !IndexModel {
    const key = lib_mongo.bsonNew();
    defer lib_mongo.bsonDestroy(key);

    const ord = @intFromEnum(order);
    const key_fmt = "{{\"{s}\": {d}}}";
    const key_strZ = try fmt.allocPrintSentinel(
        heap, key_fmt, .{doc_key, ord}, 0
    );
    defer heap.free(key_strZ);

    var err_res: lib_mongo.BsonError = undefined;

    if (!lib_mongo.bsonFromJSON(key, key_strZ, &err_res)) {
        const fmt_str = "Code - {d} | {s}";
        log.err(fmt_str, .{err_res.code, @as(StrC, &err_res.message)});
        return Error.OperationFailed;
    }

    const opts = lib_mongo.bsonNew();
    defer lib_mongo.bsonDestroy(opts);

    const opts_fmt = "{{\"name\": \"{s}_index\", \"unique\": {}}}";
    const opts_strZ = try fmt.allocPrintSentinel(
        heap, opts_fmt, .{doc_key, unique}, 0
    );
    defer heap.free(opts_strZ);

    if (!lib_mongo.bsonFromJSON(opts, opts_strZ, &err_res)) {
        const fmt_str = "Code - {d} | {s}";
        log.err(fmt_str, .{err_res.code, @as(StrC, &err_res.message)});
        return Error.OperationFailed;
    }

    return lib_mongo.indexModelNew(key, opts);
}

/// # Destroys the Index Model
pub fn indexModelDestroy(model: IndexModel) void {
    lib_mongo.indexModelDestroy(model);
}

//##############################################################################
//# DATABASE INTERFACE --------------------------------------------------------#
//##############################################################################

pub const Database = struct {
    debug_mode: bool,
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
            if (self.debug_mode) {
                const fmt_str = "Code - {d} | {s}";
                log.err(fmt_str, .{err_res.code, @as(StrC, &err_res.message)});
            }

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
        return .{.debug_mode = self.debug_mode, .instance = coll};
    }

    /// # Returns a New Session Handle
    /// **WARNING:** Return value must be freed by calling `AcidSession.free()`.
    pub fn session(self: DatabaseZ) Error!AcidSession {
        var err_res: lib_mongo.BsonError = undefined;
        const result = lib_mongo.sessionStart(self.client, &err_res);

        if (result == null) {
            if (self.debug_mode) {
                const fmt_str = "Code - {d} | {s}";
                log.err(fmt_str, .{err_res.code, @as(StrC, &err_res.message)});
            }

            return Error.OperationFailed;
        }

        return .{.debug_mode = self.debug_mode, .instance = result};
    }
};

//##############################################################################
//# COLLECTION INTERFACE ------------------------------------------------------#
//##############################################################################

const Collection = struct {
    debug_mode: bool,
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
            if (self.debug_mode) {
                const fmt_str = "Code - {d} | {s}";
                log.err(fmt_str, .{err_res.code, @as(StrC, &err_res.message)});
            }

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
            if (self.debug_mode) {
                const fmt_str = "Code - {d} | {s}";
                log.err(fmt_str, .{err_res.code, @as(StrC, &err_res.message)});
            }

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
        defer if (filter == null) lib_mongo.bsonDestroy(flt);

        var reply: lib_mongo.Bson = undefined;
        var err_res: lib_mongo.BsonError = undefined;
        const rv = lib_mongo.countDocuments(
            self.instance, flt, options, &reply, &err_res
        );

        if (rv >= 0) return rv
        else {
            if (self.debug_mode) {
                const fmt_str = "Code - {d} | {s}";
                log.err(fmt_str, .{err_res.code, @as(StrC, &err_res.message)});
            }

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
        return .{.debug_mode = self.debug_mode, .instance = cursor};
    }

    /// # Inserts a Single Document
    /// - `opts` - is required for ACID transaction
    pub fn insertOne(
        self: CollectionZ,
        heap: Allocator,
        data: anytype,
        opts: ?BsonPtr
    ) !void {
        const json_str = try StaticJSON.stringify(heap, data);
        defer heap.free(json_str);

        const json_strZ = try fmt.allocPrintSentinel(
            heap, "{s}", .{json_str}, 0
        );
        defer heap.free(json_strZ);

        const doc = lib_mongo.bsonNew();
        defer lib_mongo.bsonDestroy(doc);

        var err_res: lib_mongo.BsonError = undefined;

        if (!lib_mongo.bsonFromJSON(doc, json_strZ, &err_res)) {
            if (self.debug_mode) {
                const fmt_str = "Code - {d} | {s}";
                log.err(fmt_str, .{err_res.code, @as(StrC, &err_res.message)});
            }

            return Error.OperationFailed;
        }

        if (!lib_mongo.insertOne(self.instance, doc, opts, &err_res)) {
            if (self.debug_mode) {
                const fmt_str = "Code - {d} | {s}";
                log.err(fmt_str, .{err_res.code, @as(StrC, &err_res.message)});
            }

            return if (err_res.code == 11000) Error.UniqueConstraintViolation
            else Error.OperationFailed;
        }
    }

    /// # Inserts Multiple Documents
    /// **Remarks:** Data must be a `[]const T`. Each document is inserted
    /// individually, thus not atomic with out ACID across multiple documents.
    ///
    /// - `opts` - is required for ACID transaction
    pub fn insertMany(
        self: CollectionZ,
        heap: Allocator,
        data: anytype,
        opts: ?BsonPtr
    ) !void {
        const docs = try heap.alloc([*c]Bson, data.len);
        for (0..docs.len) |i| docs[i] = lib_mongo.bsonNew();

        defer {
            for (docs) |doc| { if (doc) |d| lib_mongo.bsonDestroy(d); }
            heap.free(docs);
        }

        var err_res: lib_mongo.BsonError = undefined;

        for (data, 0..data.len) |item, i| {
            const json_str = try StaticJSON.stringify(heap, item);
            defer heap.free(json_str);

            const json_strZ = try fmt.allocPrintSentinel(
                heap, "{s}", .{json_str}, 0
            );
            defer heap.free(json_strZ);

            if (!lib_mongo.bsonFromJSON(docs[i], json_strZ, &err_res)) {
                if (self.debug_mode) {
                    const fmt_str = "Code - {d} | {s}";
                    const msg = @as(StrC, &err_res.message);
                    log.err(fmt_str, .{err_res.code, msg});
                }

                return Error.OperationFailed;
            }
        }

        const succeed = lib_mongo.insertMany(
            self.instance, @ptrCast(docs), opts, &err_res
        );

        if (!succeed) {
            if (self.debug_mode) {
                const fmt_str = "Code - {d} | {s}";
                log.err(fmt_str, .{err_res.code, @as(StrC, &err_res.message)});
            }

            return if (err_res.code == 11000) Error.UniqueConstraintViolation
            else Error.OperationFailed;
        }
    }

    /// # Deletes a Single Document
    /// **CAUTION:** When selector matches multiple documents, only one document
    /// (the first found by MongoDB’s internal query planner) is deleted.
    ///
    /// - `opts` - is required for ACID transaction
    pub fn deleteOne(
        self: CollectionZ,
        selector: BsonPtr,
        opts: ?BsonPtr
    ) !i64 {
        const reply = lib_mongo.bsonNew();
        defer lib_mongo.bsonDestroy(reply);

        var err_res: lib_mongo.BsonError = undefined;
        const succeed = lib_mongo.deleteOne(
            self.instance, selector, opts, reply, &err_res
        );

        if (!succeed) {
            if (self.debug_mode) {
                const fmt_str = "Code - {d} | {s}";
                log.err(fmt_str, .{err_res.code, @as(StrC, &err_res.message)});
            }

            return Error.OperationFailed;
        }

        return if (lib_mongo.bsonGetNumeric(reply, "deletedCount")) |c| c
        else Error.OperationFailed;
    }

    /// # Deletes Multiple Documents
    /// - `opts` - is required for ACID transaction
    pub fn deleteMany(
        self: CollectionZ,
        selector: BsonPtr,
        opts: ?BsonPtr
    ) !i64 {
        const reply = lib_mongo.bsonNew();
        defer lib_mongo.bsonDestroy(reply);

        var err_res: lib_mongo.BsonError = undefined;
        const succeed = lib_mongo.deleteMany(
            self.instance, selector, opts, reply, &err_res
        );

        if (!succeed) {
            if (self.debug_mode) {
                const fmt_str = "Code - {d} | {s}";
                log.err(fmt_str, .{err_res.code, @as(StrC, &err_res.message)});
            }

            return Error.OperationFailed;
        }

        return if (lib_mongo.bsonGetNumeric(reply, "deletedCount")) |c| c
        else Error.OperationFailed;
    }

    /// # Updates a Single Document
    /// **Remarks:** Updates only the first document that matches the filter.
    /// Return value is **0**, when updated data is the same.
    ///
    /// - `opts` - is required for ACID transaction
    pub fn updateOne(
        self: CollectionZ,
        selector: BsonPtr,
        doc: BsonPtr,
        opts: ?BsonPtr
    ) !i64 {
        const reply = lib_mongo.bsonNew();
        defer lib_mongo.bsonDestroy(reply);

        var err_res: lib_mongo.BsonError = undefined;
        const succeed = lib_mongo.updateOne(
            self.instance, selector, doc, opts, reply, &err_res
        );

        if (!succeed) {
            if (self.debug_mode) {
                const fmt_str = "Code - {d} | {s}";
                log.err(fmt_str, .{err_res.code, @as(StrC, &err_res.message)});
            }

            return Error.OperationFailed;
        }

        return if (lib_mongo.bsonGetNumeric(reply, "matchedCount")) |c| c
        else Error.OperationFailed;
    }

    /// # Updates Multiple Documents
    /// **Remarks: Updates all documents that match the filter.
    ///
    /// - `opts` - is required for ACID transaction
    pub fn updateMany(
        self: CollectionZ,
        selector: BsonPtr,
        doc: BsonPtr,
        opts: ?BsonPtr
    ) !i64 {
        const reply = lib_mongo.bsonNew();
        defer lib_mongo.bsonDestroy(reply);

        var err_res: lib_mongo.BsonError = undefined;
        const succeed = lib_mongo.updateMany(
            self.instance, selector, doc, opts, reply, &err_res
        );

        if (!succeed) {
            if (self.debug_mode) {
                const fmt_str = "Code - {d} | {s}";
                log.err(fmt_str, .{err_res.code, @as(StrC, &err_res.message)});
            }

            return Error.OperationFailed;
        }

        return if (lib_mongo.bsonGetNumeric(reply, "matchedCount")) |c| c
        else Error.OperationFailed;
    }

    /// # Creates an Index on the Collection
    pub fn indexCreate(self: CollectionZ, models: *const IndexModel) !void {
        var err_res: lib_mongo.BsonError = undefined;
        if (!lib_mongo.createIndex(self.instance, models, &err_res)) {
            if (self.debug_mode) {
                const fmt_str = "Code - {d} | {s}";
                log.warn(fmt_str, .{err_res.code, @as(StrC, &err_res.message)});
            }

            return Error.OperationFailed;
        }
    }

    /// # Deletes an Index from the Collection
    pub fn deleteIndex(self: CollectionZ, name: StrZ) !void {
        var err_res: lib_mongo.BsonError = undefined;
        if (!lib_mongo.deleteIndex(self.instance, name, &err_res)) {
            if (self.debug_mode) {
                const fmt_str = "Code - {d} | {s}";
                log.warn(fmt_str, .{err_res.code, @as(StrC, &err_res.message)});
            }

            return Error.OperationFailed;
        }
    }

    /// # Returns Index List Cursor from the Collection
    /// **WARNING:** Return value must be freed by calling `Iterator.free()`.
    pub fn findIndexes(self: CollectionZ) Iterator {
        const cursor = lib_mongo.findIndexes(self.instance);
        return .{.debug_mode = self.debug_mode, .instance = cursor};
    }

    /// # Executes an Aggregation Pipeline
    /// **WARNING:** Return value must be freed by calling `Iterator.free()`.
    pub fn aggregate(self: CollectionZ, pipeline: BsonPtr) Iterator {
        const cursor = lib_mongo.aggregate(self.instance, pipeline);
        return .{.debug_mode = self.debug_mode, .instance = cursor};
    }
};

//##############################################################################
//# ITERATOR INTERFACE --------------------------------------------------------#
//##############################################################################

const Iterator = struct {
    debug_mode: bool,
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
                if (self.debug_mode) {
                    const fmt_str = "Code - {d} | {s}";
                    const msg = @as(StrC, &err_res.message);
                    log.err(fmt_str, .{err_res.code, msg});
                }

                return Error.InvalidCursor;
            }

            return null;
        }

        const data = lib_mongo.bsonToJSON(doc);
        defer lib_mongo.bsonFree(@ptrCast(data));

        var json = try DynamicJSON.init(heap, mem.span(data), .{});
        defer json.deinit();

        return try DynamicJSON.parseInto(T, heap, json.data(), .{
            .ignore_unknown_fields = true
        });
    }
};

//##############################################################################
//# SESSION INTERFACE ---------------------------------------------------------#
//##############################################################################

pub const AcidSession = struct {
    debug_mode: bool,
    instance: lib_mongo.Session,

    const Action = enum { Commit, Abort };
    const AcidSessionZ = *const AcidSession;

    /// # Releases the Season Handle
    pub fn free(self: AcidSessionZ) void {
        lib_mongo.sessionDestroy(self.instance);
    }

    /// # Starts a Multi-Document Transaction
    pub fn start(self: AcidSessionZ) Error!void {
        var err_res: lib_mongo.BsonError = undefined;
        if(!lib_mongo.transactionStart(self.instance, &err_res)) {
            if (self.debug_mode) {
                const fmt_str = "Code - {d} | {s}";
                log.err(fmt_str, .{err_res.code, @as(StrC, &err_res.message)});
            }

            return Error.OperationFailed;
        }
    }

    /// # Adds Session's Transaction Metadata
    /// **Remarks:** Pass this `opts` to the target CURD function for ACID.
    pub fn append(self: AcidSessionZ, opts: BsonPtr) Error!void {
        var err_res: lib_mongo.BsonError = undefined;
        if(!lib_mongo.transactionAppend(self.instance, opts, &err_res)) {
            if (self.debug_mode) {
                const fmt_str = "Code - {d} | {s}";
                log.err(fmt_str, .{err_res.code, @as(StrC, &err_res.message)});
            }

            return Error.OperationFailed;
        }
    }

    /// # Ends a Multi-Document Transaction
    pub fn end(self: AcidSessionZ, act: Action) Error!void {
        var err_res: lib_mongo.BsonError = undefined;

        const result = switch(act) {
            .Commit => lib_mongo.transactionCommit(self.instance, &err_res),
            .Abort => lib_mongo.transactionAbort(self.instance, &err_res)
        };

        if(!result) {
            if (self.debug_mode) {
                const fmt_str = "Code - {d} | {s}";
                log.err(fmt_str, .{err_res.code, @as(StrC, &err_res.message)});
            }

            return Error.OperationFailed;
        }
    }
};
