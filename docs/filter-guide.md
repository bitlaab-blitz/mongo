# MongoDB Filter Query Guide

This document lists commonly used MongoDB filter query operators with descriptions and usage examples.

---

## Equality and Comparison Operators

| Operator       | Description                                                | Example                                                  |
|----------------|------------------------------------------------------------|----------------------------------------------------------|
| `$eq`          | Matches values that are equal to a specified value.        | `{ "status": { "$eq": "A" } }`                           |
| `$ne`          | Matches values not equal to a specified value.             | `{ "status": { "$ne": "A" } }`                           |
| `$gt`          | Matches values greater than a specified value.             | `{ "age": { "$gt": 25 } }`                               |
| `$gte`         | Matches values greater than or equal to a specified value. | `{ "age": { "$gte": 18 } }`                              |
| `$lt`          | Matches values less than a specified value.                | `{ "age": { "$lt": 65 } }`                               |
| `$lte`         | Matches values less than or equal to a specified value.    | `{ "age": { "$lte": 30 } }`                              |

---

## Logical Operators

| Operator       | Description                                                | Example                                                  |
|----------------|------------------------------------------------------------|----------------------------------------------------------|
| `$and`         | Joins query clauses with logical AND.                      | `{ "$and": [ { "age": { "$gt": 18 } }, { "age": { "$lt": 60 } } ] }` |
| `$or`          | Joins query clauses with logical OR.                       | `{ "$or": [ { "status": "A" }, { "qty": { "$lt": 30 } } ] }` |
| `$nor`         | Joins query clauses with NOR.                              | `{ "$nor": [ { "price": 1.99 }, { "qty": { "$lt": 20 } } ] }` |
| `$not`         | Inverts the effect of a query expression.                  | `{ "price": { "$not": { "$gt": 1.99 } } }`               |

---

## Element Operators

| Operator       | Description                                                | Example                                                  |
|----------------|------------------------------------------------------------|----------------------------------------------------------|
| `$exists`      | Matches documents with the specified field.                | `{ "middle_name": { "$exists": true } }`                 |
| `$type`        | Matches documents where field is of specified type.        | `{ "score": { "$type": "double" } }`                     |

---

## Evaluation Operators

| Operator       | Description                                                | Example                                                  |
|----------------|------------------------------------------------------------|----------------------------------------------------------|
| `$expr`        | Allows use of aggregation expressions in filters.          | `{ "$expr": { "$gt": [ "$spent", "$budget" ] } }`        |
| `$regex`       | Matches strings using regular expressions.                 | `{ "name": { "$regex": "^J" } }`                         |
| `$text`        | Performs text search on indexed fields.                    | `{ "$text": { "$search": "coffee" } }`                   |
| `$mod`         | Matches numbers divisible by a specified value.            | `{ "qty": { "$mod": [ 4, 0 ] } }`                        |

---

## Array Operators

| Operator       | Description                                                | Example                                                  |
|----------------|------------------------------------------------------------|----------------------------------------------------------|
| `$in`          | Matches any of the values specified in an array.           | `{ "status": { "$in": ["A", "B"] } }`                    |
| `$nin`         | Matches none of the values specified in an array.          | `{ "status": { "$nin": ["D", "E"] } }`                   |
| `$all`         | Matches arrays that contain all elements specified.        | `{ "tags": { "$all": ["red", "blank"] } }`              |
| `$elemMatch`   | Matches documents with array fields matching multiple conditions. | `{ "results": { "$elemMatch": { "$gt": 80, "$lt": 85 } } }` |
| `$size`        | Matches arrays with the specified number of elements.      | `{ "tags": { "$size": 3 } }`                             |

---

## Geospatial Operators (Advanced Use)

| Operator       | Description                                                |
|----------------|------------------------------------------------------------|
| `$geoWithin`   | Matches geometries within a certain shape.                 |
| `$geoIntersects` | Matches geometries that intersect with a specified shape. |
| `$near`        | Returns documents ordered by proximity.                    |

---

## Bitwise Operators

| Operator       | Description                                                |
|----------------|------------------------------------------------------------|
| `$bitsAllClear`| Matches documents where all specified bits are clear (0).  |
| `$bitsAllSet`  | Matches documents where all specified bits are set (1).    |
| `$bitsAnyClear`| Matches documents where any specified bits are clear (0).  |
| `$bitsAnySet`  | Matches documents where any specified bits are set (1).    |

---

## Comments and Hints

| Operator       | Description                                                |
|----------------|------------------------------------------------------------|
| `$comment`     | Attaches a comment to a query. Useful for profiling.       |
| `$hint`        | Forces query optimizer to use a specific index.            |
| `$natural`     | Forces natural order traversal.                            |

---

> **Note**: All examples use MongoDB Extended JSON format and can be passed as BSON in drivers like C, Zig, or JavaScript.




# MongoDB Query Options Guide

This document lists common options available for MongoDB query operations (e.g., `find`, `aggregate`, `count_documents`, etc.) with descriptions and examples.

---

## General Query Options

| Option         | Type     | Description                                                                 | Example                                  |
|----------------|----------|-----------------------------------------------------------------------------|------------------------------------------|
| `limit`        | Integer  | Limits the number of documents returned.                                     | `{ "limit": 10 }`                         |
| `skip`         | Integer  | Skips the specified number of documents before returning.                    | `{ "skip": 5 }`                           |
| `sort`         | Document | Specifies the sort order for results.                                        | `{ "sort": { "age": -1 } }`               |
| `projection`   | Document | Limits the fields returned in each document.                                 | `{ "projection": { "name": 1, "_id": 0 } }`|
| `hint`         | String / Document | Forces MongoDB to use a specific index.                            | `{ "hint": "age_1" }` or `{ "hint": { "age": 1 } }` |
| `comment`      | String   | Attaches a comment to the query for debugging and profiling.                 | `{ "comment": "user search operation" }`  |

---

## Cursor Behavior

| Option         | Type     | Description                                                                 | Example                                  |
|----------------|----------|-----------------------------------------------------------------------------|------------------------------------------|
| `batchSize`    | Integer  | Specifies the number of documents returned per batch.                       | `{ "batchSize": 100 }`                   |
| `noCursorTimeout` | Boolean | Prevents server from closing cursor after timeout period.              | `{ "noCursorTimeout": true }`           |
| `tailable`     | Boolean  | Makes cursor tail the oplog or capped collection.                          | `{ "tailable": true }`                  |
| `awaitData`    | Boolean  | Use with `tailable` to wait for new data before returning.                  | `{ "awaitData": true }`                  |

---

## Aggregation-Specific Options

| Option         | Type     | Description                                                                 | Example                                  |
|----------------|----------|-----------------------------------------------------------------------------|------------------------------------------|
| `allowDiskUse` | Boolean  | Allows MongoDB to use temporary disk files during aggregation.              | `{ "allowDiskUse": true }`               |
| `maxTimeMS`    | Integer  | Specifies the maximum execution time in milliseconds.                       | `{ "maxTimeMS": 5000 }`                  |
| `collation`    | Document | Specifies collation (e.g., case-insensitivity).                             | `{ "collation": { "locale": "en", "strength": 1 } }` |
| `bypassDocumentValidation` | Boolean | Bypasses schema validation when performing write stages.     | `{ "bypassDocumentValidation": true }`   |
| `readConcern`  | Document | Specifies the level of isolation for read operations.                       | `{ "readConcern": { "level": "majority" } }` |

---

## Count/Find Options (Specific)

| Option         | Type     | Description                                                                 | Example                                  |
|----------------|----------|-----------------------------------------------------------------------------|------------------------------------------|
| `readPreference` | Document | Specifies preferred replica read behavior.                              | `{ "readPreference": { "mode": "secondary" } }` |
| `max`          | Document | Specifies upper bound index key values for the query.                      | `{ "max": { "age": 30 } }`               |
| `min`          | Document | Specifies lower bound index key values for the query.                      | `{ "min": { "age": 18 } }`               |
| `returnKey`    | Boolean  | Returns only index keys in result documents.                               | `{ "returnKey": true }`                  |
| `showRecordId` | Boolean  | Includes the internal storage engine record ID.                            | `{ "showRecordId": true }`              |

---

## Write Options (for insert/update/delete)

| Option         | Type     | Description                                                                 | Example                                  |
|----------------|----------|-----------------------------------------------------------------------------|------------------------------------------|
| `writeConcern` | Document | Controls acknowledgment of write operations.                                | `{ "writeConcern": { "w": "majority", "j": true } }` |
| `upsert`       | Boolean  | Insert the document if it does not exist.                                   | `{ "upsert": true }`                     |
| `multi`        | Boolean  | Update/delete multiple documents.                                           | `{ "multi": true }`                      |

---

## Session and Transaction Options

| Option         | Type     | Description                                                                 | Example                                  |
|----------------|----------|-----------------------------------------------------------------------------|------------------------------------------|
| `session`      | Object   | Associates operation with a logical session.                                | `{ "session": <session-object> }`        |
| `txnNumber`    | Integer  | Transaction number used in session-based transactions.                      | `{ "txnNumber": 1 }`                     |
| `startTransaction` | Boolean | Begins a multi-statement transaction.                                | `{ "startTransaction": true }`           |
| `autocommit`   | Boolean  | Must be false for transactions.                                             | `{ "autocommit": false }`                |

---

## Notes

- These options can be passed as **BSON documents** in drivers like C, Zig, or JavaScript.
- Many options are mutually exclusive or context-specific. Refer to MongoDB official docs for version-specific behavior.