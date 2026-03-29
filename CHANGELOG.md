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
