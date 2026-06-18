# stdx

Stdx is a comprehensive C++ standard library extension library, featuring multiple utilities for Zig-build powered C++ projects as well. This library is closely tied to my other C++ projects and development is typically done in tandem.

To reduce shared complexity across different projects, stdx provides the following fully-wired dependencies via the Zig build system:

- [Catch2](https://github.com/catchorg/Catch2)'s amalgamated source code is compiled from source for test running. It is automatically configured in the project's build script and links statically to the test builds.
- [cppcheck](https://cppcheck.sourceforge.io/) is compiled from source for static analysis. It is licensed under the GNU GPLv3, but the associated compiled artifacts are neither linked with output artifacts nor shipped with releases.
- [magic_enum](https://github.com/Neargye/magic_enum) is used as a utility to reflect on enum values. Is is licensed under the permissive MIT License.
- [fmt](https://github.com/fmtlib/fmt) is used as a formatting utility in place of std::format, which is not as performant or feature-full. Is is licensed under the permissive MIT License.
- [unordered_dense](https://github.com/martinus/unordered_dense) provides a vastly improved hash map/set implementation that is used over the inefficient C++ standard implementation. Is is licensed under the permissive MIT License.
- [gsl](https://github.com/microsoft/gsl) is used for enforcing best practices and supporting the standard template library. Is is licensed under the permissive MIT License.
- [kcov](https://github.com/SimonKagstrom/kcov) is used for test coverage reporting. The licensing of this tool and its dependencies are not explicitly listed here as they are not shipped with releases of ghoti. It has multiple dependencies, but they are all fetched lazily as kcov is only supported on Linux, MacOS, and FreeBSD:
    - [curl](https://github.com/curl/curl) is required by all builds of kcov and is used for pulling the resulting badge. It has a single extra dependency which is chosen for cross-platform support:
        - [mbedtls](https://github.com/Mbed-TLS/mbedtls)
    - [binutils](https://sourceware.org/pub/binutils) is required for all kcov builds
    - [elfutils](https://github.com/Techatrix/elfutils) is required on linux only. It has a single extra dependency:
        - [argp-standalone](https://github.com/argp-standalone/argp-standalone)
    - [libdwarf-code](https://github.com/davea42/libdwarf-code) is required on MacOS only.
- [libarchive](https://github.com/libarchive/libarchive) is used for packaging releases, making use of [zlib](https://github.com/madler/zlib) and [zstd](https://github.com/facebook/zstd) to create `zip` and `zst` archives. It is license under the BSD 2-Clause License, but the associated compiled artifacts are neither linked with output artifacts nor shipped with releases.