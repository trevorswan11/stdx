const std = @import("std");

const Dependency = @import("Dependency.zig");
const Config = Dependency.Config;
const ArrayList = @import("../build/array_list.zig").ArrayList;

const abseil = @import("sources/abseil.zig");

/// Compiles zlib from source as a static library
/// https://github.com/allyourcodebase/abseil
pub fn build(b: *std.Build, config: Config) Dependency {
    const upstream = b.dependency("abseil", .{});
    const root = upstream.path(".");
    const absl = root.path(b, "absl");

    const mod = b.createModule(.{
        .target = config.target,
        .optimize = config.optimize,
        .link_libc = true,
        .link_libcpp = true,
    });

    switch (config.target.result.os.tag) {
        .windows => mod.linkSystemLibrary("dbghelp", .{}),
        .macos => Dependency.addFrameworkSearchPaths(mod, config.target),
        else => {}, 
    }

    mod.addIncludePath(root);
    mod.addCSourceFiles(.{
        .root = absl,
        .files = &abseil.sources,
        .flags = &compile_flags,
        .language = .cpp,
    });

    if (config.target.result.os.tag == .windows) {
        mod.addCSourceFiles(.{
            .root = absl,
            .files = &abseil.sources_win32,
            .language = .cpp,
        });
    }

    const lib = b.addLibrary(.{
        .name = "abseil",
        .root_module = mod,
    });

    lib.installHeadersDirectory(
        absl,
        "absl",
        .{ .include_extensions = &.{ ".h", ".inc" } },
    );
    b.installArtifact(lib);
    return .{ .upstream = upstream, .artifact = lib };
}

const compile_flags = [_][]const u8{
    "-std=c++23",
    "-Wall",
    "-Wmost",
    "-Wextra",
    "-Wc++98-compat-extra-semi",
    "-Wcast-qual",
    "-Wconversion",
    "-Wdeprecated-pragma",
    "-Wfloat-overflow-conversion",
    "-Wfloat-zero-conversion",
    "-Wfor-loop-analysis",
    "-Wformat-security",
    "-Wgnu-redeclared-enum",
    "-Winfinite-recursion",
    "-Winvalid-constexpr",
    "-Wliteral-conversion",
    "-Wmissing-declarations",
    "-Wnullability-completeness",
    "-Woverlength-strings",
    "-Wpointer-arith",
    "-Wself-assign",
    "-Wshadow-all",
    "-Wshorten-64-to-32",
    "-Wsign-conversion",
    "-Wstring-conversion",
    "-Wtautological-overlap-compare",
    "-Wtautological-unsigned-zero-compare",
    "-Wthread-safety",
    "-Wundef",
    "-Wuninitialized",
    "-Wunreachable-code",
    "-Wunused-comparison",
    "-Wunused-local-typedefs",
    "-Wunused-result",
    "-Wvla",
    "-Wwrite-strings",
    "-Wno-float-conversion",
    "-Wno-implicit-float-conversion",
    "-Wno-implicit-int-float-conversion",
    "-Wno-unknown-warning-option",
    "-Wno-unused-command-line-argument",
    "-DNOMINMAX",
};
