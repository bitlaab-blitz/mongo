//! # High-level MongoDB Wrapper
//! **Remarks:** Only uses client pool for thread safety.

const std = @import("std");
const Io = std.Io;
const fmt = std.fmt;
const log = std.log;
const mem = std.mem;
const math = std.math;
const Allocator = mem.Allocator;

const jsonic = @import("jsonic");
const StaticJSON = jsonic.StaticJSON;

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

/// Tracks live `Mongo` clients, so the driver is initialized once
/// and cleaned up only after the last instance is released.
var client_refs = std.atomic.Value(u32).init(0);

io: Io,
db_name: StrZ,
debug_mode: bool,
uri: lib_mongo.Uri,
pool: lib_mongo.Pool,

/// Serializes pool access against `resetPool()`
pool_mutex: Io.Mutex = .init,

const Self = @This();

/// # Initializes MongoDB Client
/// - `mode` - Enables debug mode when **true**.
/// **Remarks:** Intended for internal use only.
pub fn init(io: Io, mode: bool, uri_string: StrZ, db_name: StrZ) Error!Self {
    // Whether any error log will be shown in the terminal
    if (mode) lib_mongo.logSetHandler(lib_mongo.showErr, null)
    else lib_mongo.logSetHandler(null, null);

    // `mongoc_cleanup()` tears down global driver state, so it must only
    // run once the last `Mongo` instance is gone
    if (client_refs.fetchAdd(1, .seq_cst) == 0) lib_mongo.init();
    errdefer _ = client_refs.fetchSub(1, .seq_cst);

    var err_res: lib_mongo.BsonError = undefined;
    const uri = lib_mongo.newUri(uri_string, &err_res);

    if (uri == null) {
        logBsonErr(.err, mode, &err_res);

        return Error.InvalidUri;
    }
    errdefer lib_mongo.destroyUri(uri);

    const pool = lib_mongo.clientPoolNew(uri);
    if (pool == null) return Error.InvalidUri;

    return .{
        .io = io,
        .db_name = db_name,
        .debug_mode = mode,
        .uri = uri,
        .pool = pool
    };
}

/// # Destroys MongoDB Client
/// **Remarks:** Intended for internal use only.
pub fn deinit(self: *const Self) void {
    lib_mongo.clientPoolDestroy(self.pool);
    lib_mongo.destroyUri(self.uri);

    if (client_refs.fetchSub(1, .seq_cst) == 1) lib_mongo.cleanUp();
}

/// # Resets MongoDB Connection Pool
/// **CAUTION:** All outstanding `Database` handles (borrowed clients) must
/// be freed before calling this, otherwise it's an undefined behavior.
///
/// **Remarks:** Concurrent `database()` calls are blocked until reset is done.
pub fn resetPool(self: *Self) !void {
    try self.pool_mutex.lock(self.io);
    defer self.pool_mutex.unlock(self.io);

    lib_mongo.clientPoolDestroy(self.pool);
    self.pool = lib_mongo.clientPoolNew(self.uri);
}

/// # Returns a New Database Handle
/// **Remarks:** Returns default database from the `init()`.
///
/// **WARNING:** Return value must be freed by calling `Database.free()`.
pub fn database(self: *Self) !Database {
    return databaseWith(self, self.db_name);
}

/// # Returns a New Database Handle
/// **WARNING:** Return value must be freed by calling `Database.free()`.
pub fn databaseWith(self: *Self, db_name: StrZ) !Database {
    try self.pool_mutex.lock(self.io);
    const c = lib_mongo.clientPoolPop(self.pool);
    self.pool_mutex.unlock(self.io);

    const d = lib_mongo.clientGetDatabase(c, db_name);
    return .{
        .debug_mode = self.debug_mode,
        .parent = self,
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
///
/// **Remarks:** Formatted data can be up to **4096** bytes, use
/// `bsonBuildLarge()` for bigger input.
pub fn bsonBuild(
    self: *const Self,
    doc: ?BsonPtr,
    comptime fmt_str: Str,
    args: anytype
) Error!BsonPtr {
    var buff: [4096]u8 = undefined;
    const src = try std.fmt.bufPrint(&buff, fmt_str, args);

    return bsonParse(self, doc, src);
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
    const src = try std.fmt.allocPrint(heap, fmt_str, args);
    defer heap.free(src);

    return bsonParse(self, doc, src);
}

/// # Parses a JSON-Formatted String into a BSON Document
/// **Remarks:** Intended for internal use only.
fn bsonParse(
    self: *const Self,
    doc: ?BsonPtr,
    src: Str
) Error!BsonPtr {
    const bson = doc orelse lib_mongo.bsonNew();
    // Only clean up when the document is owned by this function
    errdefer if (doc == null) lib_mongo.bsonDestroy(bson);

    var err_res: lib_mongo.BsonError = undefined;

    if (!lib_mongo.bsonFromJSON(bson, src, &err_res)) {
        if (self.debug_mode) {
            const err_str = "Code - {d} | {s} \n {s}";
            log.err(err_str, .{err_res.code, @as(StrC, &err_res.message), src});
        }

        return Error.InvalidInputString;
    }

    if (lib_mongo.bsonValidate(bson) == null) return Error.InvalidInputString;

    return bson;
}

/// # Adds a New Sub Document to the Given Parent Document
pub fn bsonAddDoc(doc: BsonPtr, name: StrZ, value: BsonPtr) !void {
    const succeed = lib_mongo.bsonAddDoc(doc, name, value);
    if (!succeed) return Error.InsertionFailed;
}

/// # Adds a New Property to the Given Document
///
/// **Remarks:**
/// - Enum tags gets converted into string.
/// - Passing optional value is supported.
pub fn bsonAddProp(
    doc: BsonPtr,
    name: Str,
    value: anytype
) !void {
    const T = @TypeOf(value);

    switch (@typeInfo(T)) {
        .optional => {
            if (value) |v| try bsonAddProp(doc, name, v)
            else {
                const succeed = lib_mongo.bsonAddNull(doc, name);
                if (!succeed) return Error.InsertionFailed;
            }
        },
        .null => {
            const succeed = lib_mongo.bsonAddNull(doc, name);
            if (!succeed) return Error.InsertionFailed;
        },
        .bool => {
            const succeed = lib_mongo.bsonAddBool(doc, name, value);
            if (!succeed) return Error.InsertionFailed;
        },
        .int, .comptime_int => {
            const min_i32 = math.minInt(i32);
            const max_i32 = math.maxInt(i32);
            const min_i64 = math.minInt(i64);
            const max_i64 = math.maxInt(i64);

            if (value >= min_i32 and value <= max_i32) {

                const succeed = lib_mongo.bsonAddInt32(
                    doc, name, @intCast(value)
                );
                if (!succeed) return Error.InsertionFailed;
            } else if (value >= min_i64 and value <= max_i64) {
                const succeed = lib_mongo.bsonAddInt64(
                    doc, name, @intCast(value)
                );
                if (!succeed) return Error.InsertionFailed;
            } else {
                const err_str = "@mongo: `{s}` in BSON append is too big";
                @compileError(fmt.comptimePrint(err_str, .{@typeName(T)}));
            }
        },
        .float, .comptime_float => {
            const succeed = lib_mongo.bsonAddFloat64(doc, name, value);
            if (!succeed) return Error.InsertionFailed;
        },
        .@"enum", .@"enum_literal" => {
            const succeed = lib_mongo.bsonAddString(doc, name, @tagName(value));
            if (!succeed) return Error.InsertionFailed;
        },
        .pointer => |p| {
            switch (p.size) {
                .slice => {
                    // Handles []const u8
                    if (p.child != u8) {
                        @compileError(fmt.comptimePrint(
                            "@mongo: `{s}` in BSON append is not a u8 slice",
                            .{@typeName(T)}
                        ));
                    }

                    const succeed = lib_mongo.bsonAddString(doc, name, value);
                    if (!succeed) return Error.InsertionFailed;
                },
                .many => {
                    // Handles [*:0]const u8 - already null-terminated
                    if (p.child != u8 or p.sentinel_ptr == null) {
                        @compileError(fmt.comptimePrint(
                            "@mongo: `{s}` in BSON append is not a null terminated string",
                            .{@typeName(T)}
                        ));
                    }

                    const succeed = lib_mongo.bsonAddString(
                        doc, name, mem.span(value)
                    );
                    if (!succeed) return Error.InsertionFailed;
                },
                .one => {
                    // Handles *const [N:0]u8 (pointer to array)
                    switch (@typeInfo(p.child)) {
                        .array => |a| {
                            if (a.child != u8 or a.sentinel_ptr == null) {
                                @compileError(fmt.comptimePrint(
                                    "@mongo: `{s}` in BSON append is not a null terminated string",
                                    .{@typeName(T)}
                                ));
                            }
                        },
                        else => {
                            @compileError(fmt.comptimePrint(
                                "@mongo: `{s}` in BSON append is not a null terminated string",
                                .{@typeName(T)}
                            ));
                        },
                    }

                    const succeed = lib_mongo.bsonAddString(doc, name, value);
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
/// **Remarks:** Same as `bsonAddProp()`, except NO-OP when value is **null**.
pub fn bsonSetProp(doc: BsonPtr, name: Str, value: anytype) !void {
    if (value != null) try bsonAddProp(doc, name, value);
}

/// # Converts a Zig Structure into a New BSON Document
///
/// - `data` - Must be a `struct`, a tagged `union`, an `optional` of either,
/// or a pointer to one.
///
/// **Remarks:**
/// - Enum tags gets converted into string.
/// - Struct fields can nest arbitrarily deep.
/// - Slices/arrays (except `[]const u8`) are encoded as BSON arrays.
///
/// **WARNING:** Return value must be freed by calling `Mongo.bsonFree()`.
pub fn toBsonDoc(data: anytype) Error!BsonPtr {
    const T = @TypeOf(data);

    const doc = lib_mongo.bsonNew();
    if (doc == null) return Error.OutOfMemory;
    errdefer lib_mongo.bsonDestroy(doc);

    switch (@typeInfo(T)) {
        .@"struct", .@"union" => try bsonEncodeDoc(doc, data),
        .optional => {
            if (data) |v| try bsonEncodeDoc(doc, v)
            else return Error.OperationFailed;
        },
        .pointer => |p| {
            switch (p.size) {
                .one => try bsonEncodeDoc(doc, data.*),
                else => {
                    const err_str = "@mongo: `{s}` is not supported by `toBsonDoc()`";
                    @compileError(fmt.comptimePrint(err_str, .{@typeName(T)}));
                },
            }
        },
        else => {
            const err_str = "@mongo: `{s}` is not supported by `toBsonDoc()`";
            @compileError(fmt.comptimePrint(err_str, .{@typeName(T)}));
        }
    }

    return doc;
}

/// # Encodes a Zig Structure or Tagged Union Into a BSON Document
/// **Remarks:** Intended for internal use only.
fn bsonEncodeDoc(doc: BsonPtr, data: anytype) Error!void {
    switch (@typeInfo(@TypeOf(data))) {
        .@"struct" => |s| {
            if (comptime s.is_tuple) try bsonEncodeArray(doc, data)
            else try bsonEncodeFields(doc, data);
        },
        .@"union" => try bsonEncodeUnion(doc, data),
        else => {
            const err_str = "@mongo: `{s}` is not supported by `toBsonDoc()`";
            @compileError(fmt.comptimePrint(
                err_str, .{@typeName(@TypeOf(data))}
            ));
        },
    }
}

/// # Encodes a Zig Structure's Fields Into a BSON Document
/// **Remarks:** Intended for internal use only.
fn bsonEncodeFields(doc: BsonPtr, data: anytype) Error!void {
    const s = @typeInfo(@TypeOf(data)).@"struct";

    inline for (s.field_names, 0..) |name, i| {
        if (comptime s.field_attrs[i].@"comptime") continue;

        try bsonAppendValue(doc, name, @field(data, name));
    }
}

/// # Encodes a Tagged Union Into a BSON Document
/// **Remarks:** Intended for internal use only. Encoded as
/// `{ "tag": payload }`, mirroring `std.json`'s tagged union form.
fn bsonEncodeUnion(doc: BsonPtr, data: anytype) Error!void {
    switch (data) {
        inline else => |payload, tag| {
            if (@TypeOf(payload) == void) {
                const succeed = lib_mongo.bsonAddNull(doc, @tagName(tag));
                if (!succeed) return Error.InsertionFailed;
            } else {
                try bsonAppendValue(doc, @tagName(tag), payload);
            }
        }
    }
}

/// # Encodes a Slice/Array's Elements Into a BSON Array
/// **Remarks:** Intended for internal use only.
fn bsonEncodeArray(doc: BsonPtr, data: anytype) Error!void {
    var key: [24]u8 = undefined;

    for (data, 0..) |item, i| {
        const idx = try fmt.bufPrint(&key, "{d}", .{i});
        try bsonAppendValue(doc, idx, item);
    }
}

/// # Encodes a Single Value Into the Given Document
/// **Remarks:** Intended for internal use only. Mirrors the BSON decoder's
/// semantics, so the result round-trips through `Iterator.next()`.
fn bsonAppendValue(doc: BsonPtr, name: Str, value: anytype) Error!void {
    const T = @TypeOf(value);

    switch (@typeInfo(T)) {
        .optional => {
            if (value) |v| try bsonAppendValue(doc, name, v)
            else {
                const succeed = lib_mongo.bsonAddNull(doc, name);
                if (!succeed) return Error.InsertionFailed;
            }
        },
        .null => {
            const succeed = lib_mongo.bsonAddNull(doc, name);
            if (!succeed) return Error.InsertionFailed;
        },
        .@"struct" => |s| {
            const sub = lib_mongo.bsonNew();
            if (sub == null) return Error.OutOfMemory;
            defer lib_mongo.bsonDestroy(sub);

            if (comptime s.is_tuple) try bsonEncodeArray(sub, value)
            else try bsonEncodeFields(sub, value);

            if (!lib_mongo.bsonAddDoc(doc, name, sub)) return Error.InsertionFailed;
        },
        .@"union" => {
            const sub = lib_mongo.bsonNew();
            if (sub == null) return Error.OutOfMemory;
            defer lib_mongo.bsonDestroy(sub);

            try bsonEncodeUnion(sub, value);

            if (!lib_mongo.bsonAddDoc(doc, name, sub)) return Error.InsertionFailed;
        },
        .array => {
            const sub = lib_mongo.bsonNew();
            if (sub == null) return Error.OutOfMemory;
            defer lib_mongo.bsonDestroy(sub);

            try bsonEncodeArray(sub, value);

            if (!lib_mongo.bsonAddDoc(doc, name, sub)) return Error.InsertionFailed;
        },
        .pointer => |p| {
            switch (p.size) {
                .slice => {
                    if (p.child != u8) {
                        const sub = lib_mongo.bsonNew();
                        if (sub == null) return Error.OutOfMemory;
                        defer lib_mongo.bsonDestroy(sub);

                        try bsonEncodeArray(sub, value);

                        if (!lib_mongo.bsonAddDoc(doc, name, sub)) {
                            return Error.InsertionFailed;
                        }
                    } else {
                        try bsonAddProp(doc, name, value);
                    }
                },
                .one => {
                    switch (@typeInfo(p.child)) {
                        .@"struct", .@"union" => try bsonAppendValue(doc, name, value.*),
                        else => try bsonAddProp(doc, name, value),
                    }
                },
                else => try bsonAddProp(doc, name, value),
            }
        },
        else => try bsonAddProp(doc, name, value),
    }
}

/// # Converts BSON Document into a JSON-Formatted String
/// **Remarks:** Intended to be used for debugging purposes.
///
/// - **WARNING:** Return value must be freed by calling `Mongo.bsonFreeJson()`.
pub fn bsonToJsonString(doc: BsonPtr) Error!Str {
    const data = lib_mongo.bsonToJSON(doc);

    if (data == null) return Error.OperationFailed;

    return mem.span(data);
}

/// # Frees a JSON String Returned by `bsonToJsonString()`
pub fn bsonFreeJson(data: Str) void {
    lib_mongo.bsonFree(@constCast(data.ptr));
}

/// # Destroys a BSON Document
pub fn bsonFree(doc: BsonPtr) void { lib_mongo.bsonDestroy(doc); }

/// # Logs a BSON Error When Debug Mode is Enabled
/// **Remarks:** Intended for internal use only.
fn logBsonErr(
    comptime level: log.Level,
    debug_mode: bool,
    err: *const lib_mongo.BsonError
) void {
    if (!debug_mode) return;

    const fmt_str = "Code - {d} | {s}";
    switch (level) {
        .err => log.err(fmt_str, .{err.code, @as(StrC, &err.message)}),
        .warn => log.warn(fmt_str, .{err.code, @as(StrC, &err.message)}),
        else => {}
    }
}

/// # Creates a New Index Model
pub fn indexModelCreate(
    heap: Allocator,
    doc_key: Str,
    order: IndexOrder,
    unique: bool
) !IndexModel {
    const key = lib_mongo.bsonNew();
    defer lib_mongo.bsonDestroy(key);

    if (!lib_mongo.bsonAddInt32(key, doc_key, @intFromEnum(order))) {
        return Error.OperationFailed;
    }

    const opts = lib_mongo.bsonNew();
    defer lib_mongo.bsonDestroy(opts);

    const name = try fmt.allocPrint(heap, "{s}_index", .{doc_key});
    defer heap.free(name);

    if (!lib_mongo.bsonAddString(opts, "name", name)) {
        return Error.OperationFailed;
    }

    if (!lib_mongo.bsonAddBool(opts, "unique", unique)) {
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
    parent: *Self,
    debug_mode: bool,
    client: lib_mongo.Client,
    instance: lib_mongo.Database,

    const DatabaseZ = *const Database;

    /// # Releases the Database Handle
    pub fn free(self: DatabaseZ) void {
        lib_mongo.destroyDatabase(self.instance);

        self.parent.pool_mutex.lockUncancelable(self.parent.io);
        defer self.parent.pool_mutex.unlock(self.parent.io);
        lib_mongo.clientPoolPush(self.parent.pool, self.client);
    }

    /// # Deletes the Entire Database
    /// **CAUTION:** Destructive operation, CAN NOT be undone!
    pub fn drop(self: DatabaseZ) Error!void {
        var err_res: lib_mongo.BsonError = undefined;
        if (!lib_mongo.dropDatabase(self.instance, &err_res)) {
            logBsonErr(.err, self.debug_mode, &err_res);

            return Error.OperationFailed;
        }
    }

    /// # Checks Whether a Collection Exists
    /// **Remarks:** Fails with `Error.OperationFailed` when the existence
    /// check itself fails (e.g. network error), rather than returning false.
    pub fn hasCollection(self: DatabaseZ, name: StrZ) Error!bool {
        var err_res = std.mem.zeroes(lib_mongo.BsonError);
        const exists = lib_mongo.hasCollection(self.instance, name, &err_res);

        if (!exists and err_res.code != 0) {
            logBsonErr(.err, self.debug_mode, &err_res);

            return Error.OperationFailed;
        }

        return exists;
    }

    /// # Returns a New Collection Handle
    /// **WARNING:** Return value must be freed by calling `Collection.free()`.
    pub fn collection(self: DatabaseZ, name: StrZ) Collection {
        const coll = lib_mongo.getCollection(self.instance, name);
        return .{.debug_mode = self.debug_mode, .instance = coll};
    }

    /// # Returns a New Session Handle
    /// **Remarks:** The session is bound to this Database's client and must
    /// be released before the Database is freed.
    ///
    /// **WARNING:** Return value must be freed by calling `AcidSession.free()`.
    pub fn session(self: DatabaseZ) Error!AcidSession {
        var err_res: lib_mongo.BsonError = undefined;
        const result = lib_mongo.sessionStart(self.client, &err_res);

        if (result == null) {
            logBsonErr(.err, self.debug_mode, &err_res);

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
        if (!lib_mongo.dropCollection(self.instance, &err_res)) {
            logBsonErr(.err, self.debug_mode, &err_res);

            return Error.OperationFailed;
        }
    }

    /// # Rename the Collection
    pub fn rename(self: CollectionZ, dest_db: StrZ, new_name: StrZ) Error!void {
        var err_res: lib_mongo.BsonError = undefined;
        const succeed = lib_mongo.renameCollection(
            self.instance, dest_db, new_name, &err_res
        );

        if (!succeed) {
            logBsonErr(.err, self.debug_mode, &err_res);

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

        // The reply is initialized by `count_documents` and must be destroyed
        const reply = lib_mongo.bsonNew();
        defer lib_mongo.bsonDestroy(reply);

        var err_res: lib_mongo.BsonError = undefined;
        const rv = lib_mongo.countDocuments(
            self.instance, flt, options, @ptrCast(reply), &err_res
        );

        if (rv >= 0) return rv
        else {
            logBsonErr(.err, self.debug_mode, &err_res);

            return Error.InvalidQuery;
        }
    }

    /// # Executes a Query
    /// **Remarks:** Fails when the cursor can not be created.
    ///
    /// **WARNING:** Return value must be freed by calling `Iterator.free()`.
    pub fn find(
        self: CollectionZ,
        filter: ?BsonPtr,
        options: ?BsonPtr
    ) Error!Iterator {
        const flt = if (filter) |f| f else lib_mongo.bsonNew();
        defer if (filter == null) lib_mongo.bsonDestroy(flt);

        const cursor = lib_mongo.find(self.instance, flt, options);

        if (cursor == null) return Error.InvalidCursor;

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

        const doc = lib_mongo.bsonNew();
        defer lib_mongo.bsonDestroy(doc);

        var err_res: lib_mongo.BsonError = undefined;

        if (!lib_mongo.bsonFromJSON(doc, json_str, &err_res)) {
            logBsonErr(.err, self.debug_mode, &err_res);

            return Error.OperationFailed;
        }

        if (!lib_mongo.insertOne(self.instance, doc, opts, &err_res)) {
            logBsonErr(.err, self.debug_mode, &err_res);

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

            if (!lib_mongo.bsonFromJSON(docs[i], json_str, &err_res)) {
                logBsonErr(.err, self.debug_mode, &err_res);

                return Error.OperationFailed;
            }
        }

        const succeed = lib_mongo.insertMany(
            self.instance, @ptrCast(docs), opts, &err_res
        );

        if (!succeed) {
            logBsonErr(.err, self.debug_mode, &err_res);

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
            logBsonErr(.err, self.debug_mode, &err_res);

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
            logBsonErr(.err, self.debug_mode, &err_res);

            return Error.OperationFailed;
        }

        return if (lib_mongo.bsonGetNumeric(reply, "deletedCount")) |c| c
        else Error.OperationFailed;
    }

    /// # Updates a Single Document
    /// **Remarks:** Updates only the first document that matches the filter. 
    /// Returns the number of **matched** documents, which also counts 
    /// documents where the update did not change any data.
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
            logBsonErr(.err, self.debug_mode, &err_res);

            return Error.OperationFailed;
        }

        return if (lib_mongo.bsonGetNumeric(reply, "matchedCount")) |c| c
        else Error.OperationFailed;
    }

    /// # Updates Multiple Documents
    /// **Remarks:** Updates all documents that match the filter. Returns the
    /// number of **matched** documents.
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
            logBsonErr(.err, self.debug_mode, &err_res);

            return Error.OperationFailed;
        }

        return if (lib_mongo.bsonGetNumeric(reply, "matchedCount")) |c| c
        else Error.OperationFailed;
    }

    /// # Creates an Index on the Collection
    pub fn indexCreate(self: CollectionZ, models: *const IndexModel) !void {
        var err_res: lib_mongo.BsonError = undefined;
        if (!lib_mongo.createIndex(self.instance, models, &err_res)) {
            logBsonErr(.warn, self.debug_mode, &err_res);

            return Error.OperationFailed;
        }
    }

    /// # Deletes an Index from the Collection
    pub fn deleteIndex(self: CollectionZ, name: StrZ) !void {
        var err_res: lib_mongo.BsonError = undefined;
        if (!lib_mongo.deleteIndex(self.instance, name, &err_res)) {
            logBsonErr(.warn, self.debug_mode, &err_res);

            return Error.OperationFailed;
        }
    }

    /// # Returns Index List Cursor from the Collection
    /// **WARNING:** Return value must be freed by calling `Iterator.free()`.
    pub fn findIndexes(self: CollectionZ) Error!Iterator {
        const cursor = lib_mongo.findIndexes(self.instance);

        if (cursor == null) return Error.OperationFailed;

        return .{.debug_mode = self.debug_mode, .instance = cursor};
    }

    /// # Executes an Aggregation Pipeline
    /// **WARNING:** Return value must be freed by calling `Iterator.free()`.
    pub fn aggregate(self: CollectionZ, pipeline: BsonPtr) Error!Iterator {
        const cursor = lib_mongo.aggregate(self.instance, pipeline);

        if (cursor == null) return Error.OperationFailed;

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
        if (self.instance) |cursor| lib_mongo.destroyCursor(cursor);
    }

    /// # Iterates the Cursor to the Next Document
    /// **WARNING:** Return value must be freed by calling `jsonic.free()`.
    pub fn next(self: Iterator, heap: Allocator, comptime T: type) !?T {
        // The document is cursor-owned (ephemeral until the next call),
        // so it must neither be allocated nor destroyed here.
        var doc: lib_mongo.BsonC = null;

        if (!lib_mongo.nextCursor(self.instance, @ptrCast(&doc))) {
            var err_res: lib_mongo.BsonError = undefined;
            if (lib_mongo.errorCursor(self.instance, &err_res)) {
                if (self.debug_mode) {
                    const fmt_str = "Code - {d} | {s}";
                    const msg = @as(StrC, &err_res.message);
                    log.err(fmt_str, .{err_res.code, msg});
                }

                return Error.InvalidCursor;
            }

            return null;
        }

        return try bsonDecodeDoc(T, heap, doc);
    }
};

//##############################################################################
//# BSON DECODER --------------------------------------------------------------#
//##############################################################################

// Mirrors `jsonic`'s copy semantics.
// So every decoded value can be freed with `jsonic.free()`.

fn bsonIsScalar(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .bool, .int, .float, .@"enum" => true, else => false
    };
}

fn bsonCheckScalar(comptime T: type) void {
    switch (@typeInfo(T)) {
        .int => |n| {
            if (n.bits > 53) {
                const err_str = "@mongo: `{s}` in BSON decode exceeds the IEEE 754 double-precision boundary!";
                @compileError(fmt.comptimePrint(err_str, .{@typeName(T)}));
            }
        },
        .float => |f| {
            if (f.bits != 64) @compileError("@mongo: Use only `f64` instead!");
        },
        else => {}
    }
}

/// - Frees the decoded value.
/// - Mirrors `jsonic.free()`, so the memory layout matches.
fn bsonFreeValue(heap: Allocator, comptime T: type, value: T) void {
    switch (@typeInfo(T)) {
        .optional => |o| {
            if (value) |v| bsonFreeValue(heap, o.child, v);
        },
        .array => |a| {
            if (comptime !bsonIsScalar(a.child)) {
                for (value) |item| bsonFreeValue(heap, a.child, item);
            }
        },
        .pointer => |p| {
            switch (p.size) {
                .slice => {
                    if (comptime !bsonIsScalar(p.child)) {
                        for (value) |item| bsonFreeValue(heap, p.child, item);
                    }

                    heap.free(value);
                },
                .one => {
                    bsonFreeValue(heap, p.child, value.*);
                    heap.destroy(value);
                },
                else => {}
            }
        },
        .@"struct" => |s| {
            inline for (s.field_names, s.field_types, s.field_attrs) |name, FT, attrs| {
                if (comptime attrs.@"comptime") continue;

                bsonFreeValue(heap, FT, @field(value, name));
            }
        },
        .@"union" => {
            switch (value) {
                inline else => |payload| bsonFreeValue(heap, @TypeOf(payload), payload)
            }
        },
        else => {} // NO-OP
    }
}

/// # Decodes a BSON Document into the Given Structure
/// **Remarks:** Intended for internal use only. Only structs (and pointers
/// to structs) are supported at the top level.
fn bsonDecodeDoc(
    comptime T: type,
    heap: Allocator,
    doc: lib_mongo.BsonC
) Error!T {
    switch (@typeInfo(T)) {
        .optional => |o| return try bsonDecodeDoc(o.child, heap, doc),
        .pointer => |p| {
            if (!p.attrs.@"const") {
                @compileError("@mongo: Use `const` ptr for `{s}` instead");
            }

            if (p.sentinel() != null) {
                @compileError("@mongo: Sentinel terminated `{s}` is unsupported");
            }

            switch (p.size) {
                .one => {
                    const child = try heap.create(p.child);
                    errdefer heap.destroy(child);

                    child.* = try bsonDecodeDoc(p.child, heap, doc);
                    return child;
                },
                else => return Error.OperationFailed,
            }
        },
        else => {},
    }

    if (@typeInfo(T) != .@"struct") return Error.OperationFailed;

    var iter: lib_mongo.Iter = undefined;
    if (!lib_mongo.iterInit(&iter, doc)) return Error.OperationFailed;

    return try bsonDecodeStruct(T, heap, &iter);
}

/// # Decodes a BSON Sub Document Into a Structure
/// **Remarks:** Intended for internal use only. Iterates the elements and
/// matches them against the structure's fields.
fn bsonDecodeStruct(
    comptime T: type,
    heap: Allocator,
    iter: *lib_mongo.Iter
) Error!T {
    const s = @typeInfo(T).@"struct";

    var dest: T = undefined;
    var done: [s.field_names.len]bool = undefined;
    inline for (&done) |*d| d.* = false;

    errdefer {
        inline for (
            s.field_names, s.field_types, s.field_attrs, 0..
        ) |name, FT, attrs, i| {
            if (comptime !attrs.@"comptime") {
                if (done[i]) bsonFreeValue(heap, FT, @field(dest, name));
            }
        }
    }

    while (lib_mongo.iterNext(iter)) {
        const key = mem.span(lib_mongo.iterKey(iter));

        inline for (s.field_names, s.field_types, 0..) |name, FT, i| {
            if (!done[i] and mem.eql(u8, key, name)) {
                @field(dest, name) = try bsonDecodeValue(FT, heap, iter);
                done[i] = true;
            }
        }
    }

    inline for (s.field_names, s.field_types, s.field_attrs, 0..) |name, FT, attrs, i| {
        if (comptime !attrs.@"comptime") {
            if (!done[i]) {
                if (FT == void) continue;
                if (comptime @typeInfo(FT) == .optional) {
                    @field(dest, name) = null;
                } else if (attrs.defaultValue(FT)) |dflt| {
                    @field(dest, name) = dflt;
                } else return Error.OperationFailed;
            }
        }
    }

    return dest;
}

/// # Decodes a BSON Value Into the Given Type
/// **Remarks:** Intended for internal use only. Matches `std.json`'s
/// type coercions, so the decode semantics mirror `jsonic`.
fn bsonDecodeValue(
    comptime T: type,
    heap: Allocator,
    iter: *lib_mongo.Iter
) Error!T {
    switch (@typeInfo(T)) {
        .void => return {},
        .null => return null,
        .bool => {
            if (lib_mongo.iterTypeTag(iter) != .boolean) return Error.OperationFailed;
            return lib_mongo.iterBool(iter);
        },
        .int => {
            comptime bsonCheckScalar(T);

            switch (lib_mongo.iterTypeTag(iter)) {
                .int32, .int64 => {
                    const num = lib_mongo.iterAsInt64(iter);
                    if (num < math.minInt(T) or num > math.maxInt(T)) {
                        return Error.OperationFailed;
                    }

                    return @intCast(num);
                },
                .double => {
                    const num = lib_mongo.iterAsDouble(iter);
                    if (!math.isFinite(num) or
                        num < math.minInt(T) or num > math.maxInt(T)
                    ) return Error.OperationFailed;

                    return @intFromFloat(num);
                },
                else => return Error.OperationFailed,
            }
        },
        .float => {
            comptime bsonCheckScalar(T);

            switch (lib_mongo.iterTypeTag(iter)) {
                .double, .int32, .int64 => return lib_mongo.iterAsDouble(iter),
                else => return Error.OperationFailed,
            }
        },
        .@"enum" => {
            if (lib_mongo.iterTypeTag(iter) != .utf8) return Error.OperationFailed;

            const tag = lib_mongo.iterUtf8(iter);
            return std.meta.stringToEnum(T, tag) orelse Error.OperationFailed;
        },
        .optional => |o| {
            if (lib_mongo.iterTypeTag(iter) == .null) return null;
            return try bsonDecodeValue(o.child, heap, iter);
        },
        .pointer => |p| {
            if (!p.attrs.@"const") {
                const err_str = "@mongo: Use `const` ptr for `{s}` instead";
                @compileError(fmt.comptimePrint(err_str, .{@typeName(T)}));
            }

            if (p.sentinel() != null) {
                const err_str = "@mongo: Sentinel terminated `{s}` is unsupported";
                @compileError(fmt.comptimePrint(err_str, .{@typeName(T)}));
            }

            switch (p.size) {
                .slice => {
                    // Handles []const u8 from a BSON string
                    if (comptime p.child == u8) {
                        if (lib_mongo.iterTypeTag(iter) != .utf8) {
                            return Error.OperationFailed;
                        }

                        return try heap.dupe(u8, lib_mongo.iterUtf8(iter));
                    }

                    if (comptime bsonIsScalar(p.child)) comptime bsonCheckScalar(p.child);

                    if (lib_mongo.iterTypeTag(iter) != .array) {
                        return Error.OperationFailed;
                    }

                    const count = lib_mongo.iterCount(iter);
                    var sub: lib_mongo.Iter = undefined;
                    if (!lib_mongo.iterRecurse(iter, &sub)) return Error.OperationFailed;

                    const out = try heap.alloc(p.child, count);
                    var n: usize = 0;
                    errdefer {
                        for (out[0..n]) |item| bsonFreeValue(heap, p.child, item);
                        heap.free(out);
                    }

                    while (lib_mongo.iterNext(&sub)) {
                        if (n == count) return Error.OperationFailed;

                        out[n] = try bsonDecodeValue(p.child, heap, &sub);
                        n += 1;
                    }

                    if (n != count) return Error.OperationFailed;

                    return out;
                },
                .one => {
                    const child = try heap.create(p.child);
                    errdefer heap.destroy(child);

                    child.* = try bsonDecodeValue(p.child, heap, iter);
                    return child;
                },
                else => {
                    const err_str = "@mongo: Unsupported pointer type `{s}`";
                    @compileError(fmt.comptimePrint(err_str, .{@typeName(T)}));
                },
            }
        },
        .array => |a| {
            if (comptime bsonIsScalar(a.child)) comptime bsonCheckScalar(a.child);

            if (lib_mongo.iterTypeTag(iter) != .array) return Error.OperationFailed;

            var count_iter = iter.*;
            const count = lib_mongo.iterCount(&count_iter);
            if (count != a.len) return Error.OperationFailed;

            var sub: lib_mongo.Iter = undefined;
            if (!lib_mongo.iterRecurse(iter, &sub)) return Error.OperationFailed;

            var dest: T = undefined;
            var n: usize = 0;
            errdefer {
                if (comptime !bsonIsScalar(a.child)) {
                    for (dest[0..n]) |item| bsonFreeValue(heap, a.child, item);
                }
            }

            while (lib_mongo.iterNext(&sub)) {
                if (n == a.len) return Error.OperationFailed;

                dest[n] = try bsonDecodeValue(a.child, heap, &sub);
                n += 1;
            }

            if (n != a.len) return Error.OperationFailed;

            return dest;
        },
        .@"struct" => {
            if (lib_mongo.iterTypeTag(iter) != .document) return Error.OperationFailed;

            var sub: lib_mongo.Iter = undefined;
            if (!lib_mongo.iterRecurse(iter, &sub)) return Error.OperationFailed;

            return try bsonDecodeStruct(T, heap, &sub);
        },
        .@"union" => {
            if (lib_mongo.iterTypeTag(iter) != .document) return Error.OperationFailed;

            var sub: lib_mongo.Iter = undefined;
            if (!lib_mongo.iterRecurse(iter, &sub)) return Error.OperationFailed;
            if (!lib_mongo.iterNext(&sub)) return Error.OperationFailed;

            const key = mem.span(lib_mongo.iterKey(&sub));

            inline for (@typeInfo(T).@"union".field_names, @typeInfo(T).@"union".field_types) |name, FT| {
                if (mem.eql(u8, key, name)) {
                    if (FT == void) return @unionInit(T, name, {});

                    const payload = try bsonDecodeValue(FT, heap, &sub);
                    return @unionInit(T, name, payload);
                }
            }

            return Error.OperationFailed;
        },
        else => {
            const err_str = "@mongo: Unsupported type `{s}` in BSON decode";
            @compileError(fmt.comptimePrint(err_str, .{@typeName(T)}));
        }
    }
}

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
        if (!lib_mongo.transactionStart(self.instance, &err_res)) {
            logBsonErr(.err, self.debug_mode, &err_res);

            return Error.OperationFailed;
        }
    }

    /// # Adds Session's Transaction Metadata
    /// **Remarks:** Pass this `opts` to the target CURD function for ACID.
    pub fn append(self: AcidSessionZ, opts: BsonPtr) Error!void {
        var err_res: lib_mongo.BsonError = undefined;
        if (!lib_mongo.transactionAppend(self.instance, opts, &err_res)) {
            logBsonErr(.err, self.debug_mode, &err_res);

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

        if (!result) {
            logBsonErr(.err, self.debug_mode, &err_res);

            return Error.OperationFailed;
        }
    }
};
