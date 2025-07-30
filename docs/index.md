# Getting Started

**High-level MongoDB Wrapper**

Mongo is a lightweight wrapper over the C-based [libmongoc](https://github.com/mongodb/mongo-c-driver) library, offering low-level, efficient, and thread-safe access to MongoDB without heavy abstractions.

**libmongoc** is thread-safe for most operations, but `mongoc_client_t` is not. Always use a client pool when working across threads.

If you need more functionality or code coverage, Please create an issue at [**Mongo Repo**](https://github.com/bitlaab-blitz/mongo) and buy us some coffee.

<!-- Buy Us Coffee -->
<a href="https://www.buymeacoffee.com/bitlaab" target="_blank">
    <img src="asset/bitlaab/coffee-btn.svg" alt="Buy Us Coffee">
</a>