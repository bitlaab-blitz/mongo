//! # Underlying MongoDB C Driver v2.0.2 API Bindings

const std = @import("std");

const bson = @cImport({ @cInclude("bson/bson.h"); });
const mongoc = @cImport({ @cInclude("mongoc/mongoc.h"); });


const Str = []const u8;
const StrZ = [:0]const u8;
const StrC = [*c]const u8;

const Error = error { FailedToConnect, FailedToExecCommand };


//##############################################################################
//# SYNCHRONOUS WRAPPER -------------------------------------------------------#
//##############################################################################

pub fn init() void {
    mongoc.mongoc_init();
}

pub fn cleanUp() void {
    mongoc.mongoc_cleanup();
}
