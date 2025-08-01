/*
 * Copyright 2009-present MongoDB, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */


#if !defined(MONGOC_INSIDE) && !defined(MONGOC_COMPILATION)
#error "Only <mongoc/mongoc.h> can be included directly."
#endif

// clang-format off

#ifndef MONGOC_VERSION_H
#define MONGOC_VERSION_H


/**
 * MONGOC_MAJOR_VERSION:
 *
 * MONGOC major version component (e.g. 1 if %MONGOC_VERSION is 1.2.3)
 */
#define MONGOC_MAJOR_VERSION (2)


/**
 * MONGOC_MINOR_VERSION:
 *
 * MONGOC minor version component (e.g. 2 if %MONGOC_VERSION is 1.2.3)
 */
#define MONGOC_MINOR_VERSION (0)


/**
 * MONGOC_MICRO_VERSION:
 *
 * MONGOC micro version component (e.g. 3 if %MONGOC_VERSION is 1.2.3)
 */
#define MONGOC_MICRO_VERSION (2)


/**
 * MONGOC_PRERELEASE_VERSION:
 *
 * MONGOC prerelease version component (e.g. pre if %MONGOC_VERSION is 1.2.3-pre)
 */
#define MONGOC_PRERELEASE_VERSION ()


/**
 * MONGOC_VERSION:
 *
 * MONGOC version.
 */
#define MONGOC_VERSION (2.0.2)


/**
 * MONGOC_VERSION_S:
 *
 * MONGOC version, encoded as a string, useful for printing and
 * concatenation.
 */
#define MONGOC_VERSION_S "2.0.2"


/**
 * MONGOC_VERSION_HEX:
 *
 * MONGOC version, encoded as an hexadecimal number, useful for
 * integer comparisons.
 */
#define MONGOC_VERSION_HEX (MONGOC_MAJOR_VERSION << 24 | \
                          MONGOC_MINOR_VERSION << 16 | \
                          MONGOC_MICRO_VERSION << 8)


/**
 * MONGOC_CHECK_VERSION:
 * @major: required major version
 * @minor: required minor version
 * @micro: required micro version
 *
 * Compile-time version checking. Evaluates to %TRUE if the version
 * of MONGOC is greater than or equal to the required one.
 */
#define MONGOC_CHECK_VERSION(major,minor,micro)   \
        (MONGOC_MAJOR_VERSION > (major) || \
         (MONGOC_MAJOR_VERSION == (major) && MONGOC_MINOR_VERSION > (minor)) || \
         (MONGOC_MAJOR_VERSION == (major) && MONGOC_MINOR_VERSION == (minor) && \
          MONGOC_MICRO_VERSION >= (micro)))

#endif /* MONGOC_VERSION_H */
