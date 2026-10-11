//! # Underlying MongoDB C Driver v2.0.2 API Bindings
//! - See API reference - https://mongoc.org/libmongoc/current/index.html

const std = @import("std");

const bson = @import("bson");
const mongoc = @import("mongoc");


const Str = []const u8;
const StrZ = [:0]const u8;
const StrC = [*c]const u8;

pub const Uri = ?*mongoc.mongoc_uri_t;

pub const Bson = mongoc.bson_t;
pub const BsonC = [*c]const Bson;
pub const BsonError = mongoc.bson_error_t;

pub const Client = ?*mongoc.mongoc_client_t;
pub const Pool = ?*mongoc.mongoc_client_pool_t;
pub const Database = ?*mongoc.mongoc_database_t;
pub const Collection = ?*mongoc.mongoc_collection_t;

pub const Cursor = ?*mongoc.mongoc_cursor_t;
pub const Session = ?*mongoc.mongoc_client_session_t;
pub const IndexModel = ?*mongoc.mongoc_index_model_t;
pub const Iter = mongoc.bson_iter_t;

pub const LogHandle = mongoc.mongoc_log_func_t;


//##############################################################################
//# INITIALIZATION AND CLEANUP ------------------------------------------------#
//##############################################################################

/// # Initialize the Driver
/// **Remarks:** Must be called once before any other `libmongoc` functions.
pub fn init() void { mongoc.mongoc_init(); }

/// # Destroys the Driver
/// **Remarks:** Cleans up resources before program exit.
pub fn cleanUp() void { mongoc.mongoc_cleanup(); }

//##############################################################################
//# UTILITY AND LOGGING -------------------------------------------------------#
//##############################################################################

/// # Sets the Application Name for This Client
pub fn setAppName(client: Client, name: StrZ) bool {
    return mongoc.mongoc_client_set_appname(client, @as(StrC, name));
}

/// # Sets Custom Log Handler
/// **Remarks:** Call this before `mongoc_init()` Otherwise, some log traces
/// could not be processed by the log handler.
pub fn logSetHandler(cb: LogHandle, args: ?*anyopaque) void {
    mongoc.mongoc_log_set_handler(cb, args);
}

/// # Custom Log Handler
pub fn showErr(
    log_level: u32,
    domain: StrC,
    message: StrC,
    userdata: ?*anyopaque
) callconv(.c) void {
    _ = userdata; // Not being used right now
    std.log.err("Level {d} ~ {s} | {s}", .{log_level, domain, message});
}

//##############################################################################
//# URI PARSING AND OPTIONS ---------------------------------------------------#
//##############################################################################

/// # Parses MongoDB URI
/// **Remarks:** populates error details on failure.
pub fn newUri(uri_string: StrZ, err: *BsonError) Uri {
    return mongoc.mongoc_uri_new_with_error(@as(StrC, uri_string), err);
}

/// # Frees URI Structure
pub fn destroyUri(uri: Uri) void { mongoc.mongoc_uri_destroy(uri); }

//##############################################################################
//# CLIENT CONNECTION POOL ----------------------------------------------------#
//##############################################################################

/// # Create a Thread-Safe Connection Pool
pub fn clientPoolNew(uri: Uri) Pool {
    return mongoc.mongoc_client_pool_new(uri);
}

/// # Borrows a Client from the Connection Pool
pub fn clientPoolPop(pool: Pool) Client {
    return mongoc.mongoc_client_pool_pop(pool);
}

/// # Returns the Client to thr Connection Pool
pub fn clientPoolPush(pool: Pool, client: Client) void {
    return mongoc.mongoc_client_pool_push(pool, client);
}

/// # Destroys the Connection Pool
pub fn clientPoolDestroy(pool: Pool) void {
    mongoc.mongoc_client_pool_destroy(pool);
}

//##############################################################################
//# DATABASE AND COLLECTION ---------------------------------------------------#
//##############################################################################

/// # Returns a Database Handle
pub fn clientGetDatabase(client: Client, db_name: StrZ) Database {
    return mongoc.mongoc_client_get_database(client, @as(StrC, db_name));
}

/// # Destroys the Database Handle
pub fn destroyDatabase(db: Database) void {
    mongoc.mongoc_database_destroy(db);
}

/// # Deletes the Entire Database
/// **CAUTION:** Destructive operation, CAN NOT be undone!
pub fn dropDatabase(db: Database, err: *BsonError) bool {
    return mongoc.mongoc_database_drop(db, @as([*c]BsonError, err));
}

/// # Returns a Collection Handle
pub fn clientGetCollection(
    client: Client,
    db_name: StrZ,
    coll_name: StrZ
) Collection {
    return mongoc.mongoc_client_get_collection(
        client, @as(StrC, db_name), @as(StrC, coll_name)
    );
}

/// # Returns a Collection Handle from a Database Handle
pub fn getCollection(db: Database, coll_name: StrZ) Collection {
    return mongoc.mongoc_database_get_collection(db, @as(StrC, coll_name));
}

/// # Destroys the Collection Handle
pub fn destroyCollection(coll: Collection) void {
    mongoc.mongoc_collection_destroy(coll);
}

/// # Checks Whether a Collection Exists
pub fn hasCollection(db: Database, coll_name: StrZ, err: *BsonError) bool {
    const coll = @as(StrC, coll_name);
    const bson_err = @as([*c]BsonError, err);
    return mongoc.mongoc_database_has_collection(db, coll, bson_err);
}

/// # Renames the Collection
pub fn renameCollection(
    coll: Collection,
    dest_db_name: StrZ,
    new_name: StrZ,
    err: *BsonError
) bool {
    return mongoc.mongoc_collection_rename(
        coll, @as(StrC, dest_db_name), @as(StrC, new_name), false, err
    );
}

/// # Deletes the Entire Collection
/// **CAUTION:** Destructive operation, CAN NOT be undone!
pub fn dropCollection(coll: Collection, err: *BsonError) bool {
    return mongoc.mongoc_collection_drop(coll, err);
}


//##############################################################################
//# CRUD OPERATIONS -----------------------------------------------------------#
//##############################################################################

/// # Executes a Count Query on Collection
pub fn countDocuments(
    coll: Collection,
    filter: ?BsonC,
    options: ?BsonC,
    reply: *Bson,
    err: *BsonError
) i64 {
    return mongoc.mongoc_collection_count_documents(
        coll,
        filter orelse @ptrFromInt(0),
        options orelse @ptrFromInt(0),
        @ptrFromInt(0),
        reply,
        err
    );
}

/// # Executes a Query
pub fn find(coll: Collection, filter: BsonC, options: ?BsonC) Cursor {
    return mongoc.mongoc_collection_find_with_opts(
        coll,
        filter,
        options orelse @ptrFromInt(0),
        @ptrFromInt(0)
    );
}

/// # Destroys the Cursor Handle
pub fn destroyCursor(cur: Cursor) void { mongoc.mongoc_cursor_destroy(cur); }

/// # Iterates the Cursor to the Next Document (Blocking)
pub fn nextCursor(cur: Cursor, doc: [*c][*c]const Bson) bool {
    return mongoc.mongoc_cursor_next(cur, doc);
}

/// # Sets Batch Size Limit on a Cursor
/// **Remarks:** Limits the number of documents returned in one batch.
/// Each batch requires a round trip to the server. If the batch size is zero,
/// the cursor uses the server-defined maximum batch size.
pub fn setCursorBatchSize(cur: Cursor, batch_sz: u32) void {
    mongoc.mongoc_cursor_set_batch_size(cur, batch_sz);
}

/// # Checks Whether an Error Occurred While Iterating
/// - NOTE: Use, `mongoc_cursor_error_document()` for more details
pub fn errorCursor(cur: Cursor, err: *BsonError) bool {
    return mongoc.mongoc_cursor_error(cur, err);
}

/// # Inserts a Single Document
pub fn insertOne(
    coll: Collection,
    doc: BsonC,
    opts: ?BsonC,
    err: *BsonError
) bool {
    return mongoc.mongoc_collection_insert_one(
        coll, doc, opts orelse @ptrFromInt(0), null, err
    );
}

/// # Inserts Multiple Documents
pub fn insertMany(
    coll: Collection,
    docs: []BsonC,
    opts: ?BsonC,
    err: *BsonError
) bool {
    const docs_ptr: [*c]BsonC = @ptrCast(docs);
    return mongoc.mongoc_collection_insert_many(
        coll, docs_ptr, docs.len, opts orelse @ptrFromInt(0), null, err
    );
}

/// # Deletes a Single Document
/// **CAUTION:** When selector matches multiple documents, only one document
/// (the first found by MongoDB’s internal query planner) is deleted.
pub fn deleteOne(
    coll: Collection,
    selector: BsonC,
    opts: ?BsonC,
    reply: [*c]Bson,
    err: *BsonError
) bool {
    return mongoc.mongoc_collection_delete_one(
        coll, selector, opts orelse @ptrFromInt(0), reply, err
    );
}

/// # Deletes Multiple Documents
pub fn deleteMany(
    coll: Collection,
    selector: BsonC,
    opts: ?BsonC,
    reply: [*c]Bson,
    err: *BsonError
) bool {
    return mongoc.mongoc_collection_delete_many(
        coll, selector, opts orelse @ptrFromInt(0), reply, err
    );
}

/// # Updates a Single Document
pub fn updateOne(
    coll: Collection,
    selector: BsonC,
    update: BsonC,
    opts: ?BsonC,
    reply: [*c]Bson,
    err: *BsonError
) bool {
    return mongoc.mongoc_collection_update_one(
        coll, selector, update, opts orelse @ptrFromInt(0), reply, err
    );
}

/// # Updates Multiple Documents
pub fn updateMany(
    coll: Collection,
    selector: BsonC,
    update: BsonC,
    opts: ?BsonC,
    reply: [*c]Bson,
    err: *BsonError
) bool {
    return mongoc.mongoc_collection_update_many(
        coll, selector, update, opts orelse @ptrFromInt(0), reply, err
    );
}

/// # Creates a New Index Model
pub fn indexModelNew(keys: BsonC, opts: BsonC) IndexModel {
    return mongoc.mongoc_index_model_new(keys, opts);
}

/// # Destroys the Index Model
pub fn indexModelDestroy(model: IndexModel) void {
    mongoc.mongoc_index_model_destroy(model);
}

/// # Creates an Index on the Collection
pub fn createIndex(
    coll: Collection,
    model: *const IndexModel,
    err: *BsonError
) bool {
    return mongoc.mongoc_collection_create_indexes_with_opts(
        coll, @ptrCast(model), 1, null, null, err
    );
}

/// # Deletes an Index from the Collection
pub fn deleteIndex(coll: Collection, name: StrZ, err: *BsonError) bool {
    return mongoc.mongoc_collection_drop_index_with_opts(
        coll, @as(StrC, name), null, err
    );
}

/// # Returns Index List from the Collection
pub fn findIndexes(coll: Collection) Cursor {
    return mongoc.mongoc_collection_find_indexes_with_opts(coll, null);
}

/// # Executes an Aggregation Pipeline
pub fn aggregate(coll: Collection, pipeline: BsonC) Cursor {
    const flag = mongoc.MONGOC_QUERY_NONE;
    return mongoc.mongoc_collection_aggregate(coll, flag, pipeline, null, null);
}

//##############################################################################
//# ACID SESSION --------------------------------------------------------------#
//##############################################################################

/// # Starts a New Client Session
pub fn sessionStart(client: Client, err: *BsonError) Session {
    return mongoc.mongoc_client_start_session(client, null, err);
}

/// # Destroys the Session Handle
pub fn sessionDestroy(session: Session) void {
    mongoc.mongoc_client_session_destroy(session);
}

/// # Starts a Multi-Document Transaction
pub fn transactionStart(session: Session, err: *BsonError) bool {
    return mongoc.mongoc_client_session_start_transaction(session, null, err);
}

/// # Adds Session's Transaction Metadata
pub fn transactionAppend(
    session: Session,
    opts: [*c]Bson,
    err: *BsonError
) bool {
    return mongoc.mongoc_client_session_append(session, opts, err);
}

/// # Commits the Current Transaction
pub fn transactionCommit(session: Session, err: *BsonError) bool {
    return mongoc.mongoc_client_session_commit_transaction(session, null, err);
}

/// # Aborts the Current Transaction
pub fn transactionAbort(session: Session, err: *BsonError) bool {
    return mongoc.mongoc_client_session_abort_transaction(session, err);
}

//##############################################################################
//# BSON DOCUMENT -------------------------------------------------------------#
//##############################################################################

/// # Returns a New, Empty BSON Document
pub fn bsonNew() [*c]Bson { return @ptrCast(bson.bson_new()); }

/// # Destroys a BSON Document
pub fn bsonDestroy(doc: [*c]Bson) void { bson.bson_destroy(@ptrCast(doc)); }

/// # Checks BSON for Structure Correctness
pub fn bsonValidate(doc: [*c]Bson) ?usize {
    var offset: usize = 0;
    const flag = bson.BSON_VALIDATE_NONE;
    const is_valid = bson.bson_validate(@ptrCast(doc), flag, &offset);
    return if (is_valid) offset else null;
}

/// # Parses a JSON String into a BSON Document
pub fn bsonFromJSON(doc: [*c]Bson, json_data: Str, err: *BsonError) bool {
    return bson.bson_init_from_json(
        @ptrCast(doc),
        @as(StrC, json_data.ptr),
        @intCast(json_data.len),
        @ptrCast(err)
    );
}

/// # Converts BSON Document into a JSON-Formatted String
pub fn bsonToJSON(doc: BsonC) [*c]u8 {
    var len: usize = 0;
    const mode = mongoc.BSON_JSON_MODE_RELAXED;
    const max_len = mongoc.BSON_MAX_LEN_UNLIMITED;
    const opts = mongoc.bson_json_opts_new(mode, max_len);
    defer mongoc.bson_json_opts_destroy(opts);

    return bson.bson_as_json_with_opts(
        @ptrCast(doc),
        @ptrCast(&len),
        @ptrCast(opts)
    );
}

/// # Adds a New Sub Document to the Given Parent Document
pub fn bsonAddDoc(doc: [*c]Bson, name: Str, value: [*c]Bson) bool {
    return bson.bson_append_document(
        @ptrCast(doc),
        @as(StrC, name.ptr),
        @intCast(name.len),
        @ptrCast(value),
    );
}

/// # Adds a New Array Property to the Given Document
pub fn bsonAddArray(doc: [*c]Bson, name: Str, value: [*c]Bson) bool {
    return bson.bson_append_array(
        @ptrCast(doc),
        @as(StrC, name.ptr),
        @intCast(name.len),
        @ptrCast(value)
    );
}

/// # Adds a New Null Property to the Given Document
pub fn bsonAddNull(doc: [*c]Bson, name: Str) bool {
    return bson.bson_append_null(
        @ptrCast(doc),
        @as(StrC, name.ptr),
        @intCast(name.len)
    );
}

/// # Adds a New Boolean Property to the Given Document
pub fn bsonAddBool(doc: [*c]Bson, name: Str, value: bool) bool {
    return bson.bson_append_bool(
        @ptrCast(doc),
        @as(StrC, name.ptr),
        @intCast(name.len),
        value,
    );
}

/// # Adds a New Int32 Number Property to the Given Document
pub fn bsonAddInt32(doc: [*c]Bson, name: Str, value: i32) bool {
    return bson.bson_append_int32(
        @ptrCast(doc),
        @as(StrC, name.ptr),
        @intCast(name.len),
        value,
    );
}

/// # Adds a New Int64 Number Property to the Given Document
pub fn bsonAddInt64(doc: [*c]Bson, name: Str, value: i64) bool {
    return bson.bson_append_int64(
        @ptrCast(doc),
        @as(StrC, name.ptr),
        @intCast(name.len),
        value,
    );
}

/// # Adds a New Float64 Number Property to the Given Document
pub fn bsonAddFloat64(doc: [*c]Bson, name: Str, value: f64) bool {
    return bson.bson_append_double(
        @ptrCast(doc),
        @as(StrC, name.ptr),
        @intCast(name.len),
        value,
    );
}

/// # Adds a New String Property to the Given Document
pub fn bsonAddString(doc: [*c]Bson, name: Str, value: Str) bool {
    return bson.bson_append_utf8(
        @ptrCast(doc),
        @as(StrC, name.ptr),
        @intCast(name.len),
        @as(StrC, value.ptr),
        @intCast(value.len)
    );
}

/// # Extracts BSON Value from a Given Key
pub fn bsonGetNumeric(doc: BsonC, key: StrZ) ?i64 {
    var iter: bson.bson_iter_t = undefined;

    if (bson.bson_iter_init_find(&iter, @ptrCast(doc), @as(StrC, key))) {
        return switch (bson.bson_iter_type(&iter)) {
            bson.BSON_TYPE_INT32 => bson.bson_iter_int32(&iter),
            bson.BSON_TYPE_INT64 => bson.bson_iter_int64(&iter),
            else => null,
        };
    }

    return null;
}

/// # Frees Strings or Memory Blocks
pub fn bsonFree(data: ?*anyopaque) void { bson.bson_free(data); }

//##############################################################################
//# BSON ITERATION ------------------------------------------------------------#
//##############################################################################

/// # Possible Types of a BSON Element
pub const Tag = enum {
    utf8,
    double,
    document,
    array,
    boolean,
    int32,
    int64,
    nul,
    other
};

/// # Initializes an Iterator Over a BSON Document
pub fn iterInit(iter: *Iter, doc: BsonC) bool {
    return bson.bson_iter_init(@ptrCast(iter), @ptrCast(doc));
}

/// # Advances the Iterator to the Next Element
pub fn iterNext(iter: *Iter) bool {
    return bson.bson_iter_next(@ptrCast(iter));
}

/// # Positions a New Iterator Over the Current Document/Array Element
pub fn iterRecurse(iter: *const Iter, child: *Iter) bool {
    return bson.bson_iter_recurse(@ptrCast(iter), @ptrCast(child));
}

/// # Returns the Type Tag of the Current Element
pub fn iterTypeTag(iter: *const Iter) Tag {
    return switch (bson.bson_iter_type(@ptrCast(iter))) {
        bson.BSON_TYPE_UTF8 => .utf8,
        bson.BSON_TYPE_DOUBLE => .double,
        bson.BSON_TYPE_DOCUMENT => .document,
        bson.BSON_TYPE_ARRAY => .array,
        bson.BSON_TYPE_BOOL => .boolean,
        bson.BSON_TYPE_INT32 => .int32,
        bson.BSON_TYPE_INT64 => .int64,
        bson.BSON_TYPE_NULL => .nul,
        else => .other
    };
}

/// # Returns the Key of the Current Element
pub fn iterKey(iter: *const Iter) StrC {
    return bson.bson_iter_key(@ptrCast(iter));
}

/// # Returns the Current Element's UTF-8 String Value
/// **Remarks:** Only valid when the type tag is `utf8`.
pub fn iterUtf8(iter: *const Iter) Str {
    const str = bson.bson_iter_utf8(@ptrCast(iter), null);
    return std.mem.span(@as([*:0]const u8, @ptrCast(str)));
}

/// # Returns the Current Element's Boolean Value
/// **Remarks:** Only valid when the type tag is `bool`.
pub fn iterBool(iter: *const Iter) bool {
    return bson.bson_iter_bool(@ptrCast(iter));
}

/// # Returns the Current Element's Numeric Value Coerced into an Int64
/// **Remarks:** Only valid for numeric type tags.
pub fn iterAsInt64(iter: *const Iter) i64 {
    return bson.bson_iter_as_int64(@ptrCast(iter));
}

/// # Returns the Current Element's Numeric Value Coerced into a Double
/// **Remarks:** Only valid for numeric type tags.
pub fn iterAsDouble(iter: *const Iter) f64 {
    return bson.bson_iter_as_double(@ptrCast(iter));
}
