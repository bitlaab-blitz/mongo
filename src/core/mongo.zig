//! # High-level MongoDB Wrapper
//! **Remarks:** HiRedis is single-threaded, but Redox ensures thread safety.
//! =
//! TODO: make thread safe if possible
//! **libmongoc** is thread-safe for most operations, but `mongoc_client_t` is not. Always use a client pool when working across threads.

const std = @import("std");
const fmt = std.fmt;
const mem = std.mem;
const Mutex = std.Thread.Mutex;
const Allocator = mem.Allocator;
const ArrayList = std.ArrayList;

const lib_mongo = @import("../binding/lib_mongo.zig");


const Str = []const u8;
const StrC = [*c]const u8;

const Error = error { NotFound, UnknownType, InvalidCommand, OperationFailed };

const Keys = []const Str;

//##############################################################################
//# SYNCHRONOUS WRAPPER -------------------------------------------------------#
//##############################################################################

pub fn init() void {
    lib_mongo.init();
}