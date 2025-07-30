# Developer Guide

If you are using previous release of Mongo for some reason, you can generate documentation for that release by following these steps:

- Install [Material for MkDocs](https://squidfunk.github.io/mkdocs-material/getting-started/) on your platform.

- Download and extract `Source code (zip)` for your target release at [**Mongo Repo**](https://github.com/bitlaab-blitz/mongo)

- Now, `cd` into your release directory and run:

```sh
mkdocs serve --dev-addr=0.0.0.0:3001
```

## Generate Code Documentation

To generate Zig's API documentation, navigate to your project directory and run:

```sh
zig build-lib -femit-docs=docs/zig-docs src/root.zig
```

Now, clean up any unwanted generated file and make sure to link `zig-docs/index.html` to your `reference.md` file.

## Build MongoDB C Driver from Source

To build the MongoDB C Driver's static libraries, follow these steps:

### Install the Required Dependencies

```sh
sudo apt update
sudo apt install libsasl2-dev libsnappy-dev libzstd-dev zlib1g-dev
```

### Download and Extract the Driver

```sh
wget https://github.com/mongodb/mongo-c-driver/releases/download/2.0.2/mongo-c-driver-2.0.2.tar.gz
tar -xzf mongo-c-driver-2.0.2.tar.gz
cd mongo-c-driver-2.0.2
```

### Build the Static Libraries

```sh
mkdir custom-build && cd custom-build

cmake .. \
  -DENABLE_SRV=OFF \
  -DENABLE_STATIC=ON \
  -DENABLE_SHARED=OFF \
  -DCMAKE_INSTALL_PREFIX=../install \
  -DCMAKE_BUILD_TYPE=Release

cmake --build . --target install
```

This produces the static library on the `../install` directory.

Now, Copy the `libbson2.a` and `libmongoc2.a` and paste it into your project's lib directory. Copy **bson** and **mongoc** header directory and and paste it into your your project's lib directory.

**Remarks:** Make sure to build this for both `aarch64` and `x86_64` platforms.
