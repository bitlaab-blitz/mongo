# mongo

**High-level MongoDB Wrapper**

Mongo is a lightweight wrapper over the C-based [libmongoc](https://github.com/mongodb/mongo-c-driver) library, offering low-level, efficient, and thread-safe access to MongoDB without heavy abstractions.

**libmongoc** is thread-safe for most operations, but `mongoc_client_t` is not. Always use a client pool when working across threads.

## Platform Support

Mongo currently supports only Linux on **aarch64** and **x86_64** architectures.

## Dependency

Mongo uses `libbson2.a` and `libmongoc2.a` (Static Libraries) along with the necessary header files.

No additional step is required to use this project as a package dependency.

## Documentation

For most up-to-date documentation see - [**Mongo Documentation**](https://bitlaabmongo.web.app/).