const std = @import("std");

const Dependency = @import("Dependency.zig");
const Config = Dependency.Config;

/// Compiles spdlog from source as a static library
/// https://github.com/gabime/spdlog
pub fn build(b: *std.Build, config: Config) Dependency {
    const upstream = b.dependency("spdlog", .{});
    const mod = b.createModule(.{
        .target = config.target,
        .optimize = config.optimize,
        .link_libcpp = true,
    });

    const include = upstream.path("include");
    mod.addCSourceFiles(.{
        .root = upstream.path("src"),
        .files = &.{
            "async.cpp",
            "bundled_fmtlib_format.cpp",
            "cfg.cpp",
            "color_sinks.cpp",
            "file_sinks.cpp",
            "spdlog.cpp",
            "stdout_sinks.cpp",
        },
        .flags = &.{ "-std=c++11", "-DSPDLOG_COMPILED_LIB" },
    });
    mod.addIncludePath(include);

    const lib = b.addLibrary(.{
        .name = "spdlog",
        .root_module = mod,
    });
    lib.installHeadersDirectory(include, "", .{});

    return .{
        .upstream = upstream,
        .artifact = lib,
    };
}
