<h1 align="center">stdx</h1>

<p align="center">
<img src="https://img.shields.io/badge/C%2B%2B-23-blue?logo=c%2B%2B&logoColor=white" alt="C++23" /> <a href="https://ziglang.org/download/"><img src="https://img.shields.io/badge/Zig-0.16.0-orange?logo=zig" alt="Zig 0.16.0"/></a> <a href="LICENSE"><img src="https://img.shields.io/github/license/trevorswan11/stdx" alt="License" /></a> <a href="https://github.com/trevorswan11/stdx/actions/workflows/ci.yml"><img src="https://github.com/trevorswan11/stdx/actions/workflows/ci.yml/badge.svg" alt="CI" /></a> <img src="https://raw.githubusercontent.com/trevorswan11/stdx/coverage/coverage.svg" alt="Coverage" />
</p>

Stdx is a comprehensive and ever-expanding C++ standard library extension library, additionally featuring multiple utilities for Zig-build powered C++ projects. This library is closely tied to my other C++ work and development is typically done in tandem.

## Getting Started

### Installation

#### For Nix Users

This is by far the easiest way to get started with development. Just run `nix develop` to get started and automatically get the correct Zig version as well as some other important development tools. Note that this provides optional preconfigured tools such as LLDB, Clangd, and ZLS to further enhance the developer experience.

#### For Others

All you need to get started with stdx development is git and a valid 0.16.0 Zig installation, which can be found [here](https://ziglang.org/download/).

### Development

#### Building as a Static Library

```sh
git clone https://github.com/trevorswan11/stdx
cd stdx
zig build
```

#### Adding stdx to a Project

Run the following in an environment where you have a C++ oriented `build.zig`:

```sh
zig fetch --save git+https://github.com/trevorswan11/stdx.git
```

At this point you can use the library in your `build.zig` via:

```zig
const profile = b.option(bool, "profile", "Enable chromium tracing") orelse false;
const stdx_dep = b.dependency("stdx", .{
    .target = b.graph.host,
    .optimize = optimize,
    .profile = profile,
    .building_for_dep = true,
    .run_cdb_gen = false,
});
const libstdx = stdx_dep.artifact("stdx");
```

## Dependencies

To reduce shared complexity across different projects, stdx provides the following fully-wired dependencies via the Zig build system:

- [Catch2](https://github.com/catchorg/Catch2)'s amalgamated source code is compiled from source for test running. It is automatically configured in the project's build script and links statically to the test builds.
- [cppcheck](https://cppcheck.sourceforge.io/) is compiled from source for static analysis. It is licensed under the GNU GPLv3, but the associated compiled artifacts are neither linked with output artifacts nor shipped with releases.
- [magic_enum](https://github.com/Neargye/magic_enum) is used as a utility to reflect on enum values. Is is licensed under the permissive MIT License.
- [fmt](https://github.com/fmtlib/fmt) is used as a formatting utility in place of std::format, which is not as performant or feature-full. Is is licensed under the permissive MIT License.
- [unordered_dense](https://github.com/martinus/unordered_dense) provides a vastly improved hash map/set implementation that is used over the inefficient C++ standard implementation. Is is licensed under the permissive MIT License.
- [gsl](https://github.com/microsoft/gsl) is used for enforcing best practices and supporting the standard template library. Is is licensed under the permissive MIT License.
- [kcov](https://github.com/SimonKagstrom/kcov) is used for test coverage reporting. The licensing of this tool and its dependencies are not explicitly listed here as they are not shipped with releases of stdx. It has multiple dependencies, but they are all fetched lazily as kcov is only supported on Linux, MacOS, and FreeBSD:
  - [curl](https://github.com/curl/curl) is required by all builds of kcov and is used for pulling the resulting badge. It has a single extra dependency which is chosen for cross-platform support:
    - [mbedtls](https://github.com/Mbed-TLS/mbedtls)
  - [binutils](https://sourceware.org/pub/binutils) is required for all kcov builds
  - [elfutils](https://github.com/Techatrix/elfutils) is required on linux only. It has a single extra dependency:
    - [argp-standalone](https://github.com/argp-standalone/argp-standalone)
  - [libdwarf-code](https://github.com/davea42/libdwarf-code) is required on MacOS only.
- [libarchive](https://github.com/libarchive/libarchive) is used for packaging releases, making use of [zlib](https://github.com/madler/zlib) and [zstd](https://github.com/facebook/zstd) to create `zip` and `zst` archives. It is license under the BSD 2-Clause License, but the associated compiled artifacts are neither linked with output artifacts nor shipped with releases.

## License

Distributed under the MIT License. See `LICENSE` for more information.

## Contact

[![LinkedIn](https://img.shields.io/badge/linkedin-%230077B5.svg?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/trevorswan11/) [![Gmail](https://img.shields.io/badge/Gmail-D14836?style=for-the-badge&logo=gmail&logoColor=white)](mailto:trevor.swan@case.edu)

Project Link: [https://github.com/trevorswan11/stdx](https://github.com/trevorswan11/stdx)
