# Change Log

All notable changes to this project will be documented in this file.
This project adheres to the [Semantic Version](https://semver.org/) guideline.

## [Version] - yyyy-mm-dd

Here we write upgrading notes and make them as straightforward as possible.

### Added
- A short description for added item 1
- A short description for added item 2
- A short description for added item n

### Changed
- A short description for changed item 1
- A short description for changed item 2
- A short description for changed item n

### Fixed
- A short description for fixed item 1
- A short description for fixed item 2
- A short description for fixed item n


## [v1.7.0] - 2026-10-18

Major performance and correctness overhaul: direct BSON encoding/decoding, copy-free property appends and several memory/race bug fixes, better documentation, and Zig-0.17.0 version support.

### Added

- `toBsonDoc()` - Converts a Zig structure (including nested structs, arrays, tagged unions and optionals) directly into a BSON document.
- `bsonFreeJson()` - Frees strings returned by `bsonToJsonString()`.
- Direct BSON-to-structure cursor decoding - `Iterator.next()` no longer converts documents through JSON; supports nested structs, arrays, tagged unions and `jsonic`-style field defaults.
- `indexModelCreateCompound()` - Creates a compound index model over multiple fields with individual sort orders.
- `Collection.renameWith()` - Renames a collection with an optional `drop_target` flag to overwrite the destination.

### Changed

- `bsonAddProp()` and `bsonSetProp()` no longer require an allocator; keys and string values are appended by length without intermediate copies.
- `bsonToJsonString()` no longer requires an allocator and returns a driver-owned string; free it with `bsonFreeJson()` instead of `heap.free()`.
- `bsonBuild()` formatted input limit is now 4096 bytes (was 8192); use `bsonBuildLarge()` for larger input.
- Driver initialization/cleanup is reference-counted, allowing multiple `Mongo` instances to coexist.
- `indexModelCreate()` builds key/option documents directly instead of parsing JSON.
- `indexModelCreate()` and `indexModelCreateCompound()` return `Error.OutOfMemory` instead of a NULL model handle when the driver fails to allocate the model.
- `deleteIndex()` treats an already-missing index or collection as a successful no-op (server codes 26/27).
- The BSON decoder no longer rejects integer types wider than the IEEE 754 2^53 boundary at compile time; instead, fractional doubles error out and double-typed values beyond the 2^53 exact-integer range error out for such types (int32/int64-typed values remain exact).

### Fixed

- Double-free / use-after-free in `Iterator.next()` (documents are cursor-owned and ephemeral).
- Memory leak of the `count_documents()` reply.
- Memory leaks in `bsonBuild()` / `bsonBuildLarge()` error paths.
- Silent empty-document bug in `bsonBuild()` when parsing failed with debug mode disabled.
- Race condition in `resetPool()` (pool access is now mutex-protected).
- `find()`, `findIndexes()` and `aggregate()` now return an error instead of a null cursor.
- `hasCollection()` now distinguishes a failed existence check from a missing collection.
- `drop()` now reports `OperationFailed` instead of the misleading `DoesNotExists`.
- `resetPool()` now returns `Error.OperationFailed` and keeps the previous pool intact instead of storing a NULL pool when replacement fails.
- Driver `init()`/`cleanUp()` and the global log handler are now mutex-protected, closing init/cleanup and log-handler races between concurrent `Mongo` instances; the handler is only installed/uninstalled by the first/last debug-mode instance.
- `insertMany()` guards against a NULL BSON document on allocation failure and treats empty input as a successful no-op.

## [v1.6.1] - 2026-03-29

Minor refactoring with atomic connection pool reset capabilities.

## [v1.6.0] - 2026-02-24

Minor refactoring with connection pool reset capabilities.

### Added

- `resetPool()` for resetting the pool when `FailedToExecCommand` error occurs.

## [v1.5.2] - 2026-01-28

BSON builder for arbitrarily large input data

### Added

- `bsonBuildLarge()` - Heap allocated BSON builder.

## [v1.5.1] - 2026-01-15

CRUD update improvements.

### Changed

- From now on `updateOne()` and `updateMany()` will return `matchedCount` rather then the `modifiedCount`

## [v1.5.0] - 2025-12-07

Enhanced BSON query building capabilities.

### Added

- `bsonAddDoc()` - For adding a sub-document to a parent document.
- `bsonAddProp()` - For adding an extra runtime property to a given document.
- `bsonSetProp()` - Same as `bsonAddProp()`, except NOP when value is `null`.
- `bsonToJsonString()` - For BSON to stringified JSON representation.


## [v1.4.0] - 2025-11-21

Major API level changes for ACID transaction support.

### Added

- `AcidSession` and `Database` structures are public now for better agent code structuring.
- `append()` on AcidSession structure.
- `bsonNew()` for creating empty bson document.

### Changed

- `insertOne()`, `insertMany()`, `updateOne()`, `updateMany()`, `deleteOne()`, and `deleteMany()` function signatures for ACID support.

## [v1.3.0] - 2025-10-17

Bug fixes and better error logging for `bsonBuild()`.

### Changed
- `bsonBuild()` now expects 3 parameters.

### Fixed
- Double free memory BUG

## [v1.2.1] - 2025-09-15

Minor code changes required for Jsonic v1.2.0.

## [v1.2.0] - 2025-09-13

Minor code changes required for Zig v0.15.1 breaking changes.

## [v1.1.2] - 2025-08-31

Minor BUG fix for `insertOne()` function.

## [v1.1.1] - 2025-08-07

Minor BUG fix for C's `NULL` pointer.

## [v1.1.0] - 2025-08-05

Minor BUG fix with debug logging improvements.

### Changed
- Function signature of `databaseWith()`
- Internal terminal logging based on debug mode

## [v1.0.2] - 2025-08-05

Minor improvements.

### Added
- Error variant for `insertOne()` and `insertMany()` for duplicate keys.

## [v1.0.1] - 2025-08-04

Minor BUG fix.

### Changed
- Swap `comptimePrint` with `buffPrintZ` with 4KB limit

## [v1.0.0] - 2025-08-03

Initial barebones implementation.
