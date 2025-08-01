# How to use

First, import Redox on your Zig source file.

```zig
const Mongo = @import("mongo").Mongo;
```

# WIP - TODO








## Initial Setup

Let's initialize an Redox instance.

```zig
var gpa_mem = std.heap.DebugAllocator(.{}).init;
defer std.debug.assert(gpa_mem.deinit() == .ok);
const heap = gpa_mem.allocator();

var redox = try Redox.Sync.init("127.0.0.1", 6379);
defer redox.deinit();
```

## Insert a New Record

Replaces the existing record if the key already exists.

```zig
try redox.set("foo", "bar", .Default);
```

Inserts the record only if the key already exists.

```zig
try redox.set("foo", "bar", .IfExists);
```

Inserts the record only if the key does not exist.

```zig
try redox.set("foo2", "bar2", .IfNotExists);
```

## Insert a New Record with Ttl

Same as `redox.set()`, with an additional time-to-live (TTL) value in seconds. The record is automatically deleted after this period.

```zig
try redox.setWith("foo", "bar", .Default, 30);
```

## Extract a Record by the Given Key

```zig
const rec = try redox.get("foo");
defer rec.free();
std.debug.print("Value: {s}\n", .{rec.value()});
```

## Delete a Record by the Given Key

```zig
try redox.remove("foo2");
```

## Scan Partially Matched Keys

```zig
const keys = try redox.scan(heap, "foo:*", 10);
defer Redox.Sync.free(heap, keys);

for (keys) |key| { std.debug.print("key: {s}\n", .{key}); }
```

## Show Human-Readable Error Message

Shows the most recent error that occurred on the HiRedis instance.

```zig
std.debug.print("Redis error: {s}\n", .{redox.errMsg()});
```

**Remarks:** Currently, only the string data structure is supported, and only the synchronous interface is implemented.










