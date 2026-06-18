const std = @import("std");

const ProjectPaths = @import("ProjectPaths.zig");

const utils = @import("utils.zig");
const catch2 = @import("../third-party/catch2.zig");
const libarchive = @import("../third-party/libarchive.zig");

pub const stdx_profile_define = "-DSTDX_PROFILE";

pub const BuildStrappedTestConfig = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    libstdx: *std.Build.Step.Compile,
    libcatch2: *std.Build.Step.Compile,
    /// The test hook is added automatically
    cxx_files: []const []const u8,
    cxx_flags: []const []const u8,
    profile: bool,
    /// Catch2 and libstdx are added automatically
    link_libraries: []const *std.Build.Step.Compile = &.{},
    include_paths: []const std.Build.LazyPath = &.{},
    config_headers: []const *std.Build.Step.ConfigHeader = &.{},
    system_include_paths: []const std.Build.LazyPath = &.{},
    executable_config: utils.CreateExecutableConfig,
    /// The builder who has stdx as a dependency, defaulting to `b`
    asking_builder: ?*std.Build = null,
};

/// Build's a zig-harness-driven catch2 test artifact
///
/// Call this with stdx's builder
pub fn strappedTest(b: *std.Build, config: BuildStrappedTestConfig) *std.Build.Step.Compile {
    const link_libraries = std.mem.concat(b.allocator, *std.Build.Step.Compile, &.{
        config.link_libraries,
        &.{ config.libstdx, config.libcatch2 },
    }) catch @panic("OOM");

    const test_exe = utils.createExecutable(config.asking_builder orelse b, .{
        .target = config.target,
        .optimize = config.optimize,
        .zig_main = b.path(ProjectPaths.harness ++ "main.zig"),
        .include_paths = config.include_paths,
        .config_headers = config.config_headers,
        .system_include_paths = config.system_include_paths,
        .cxx = .{
            .files = config.cxx_files,
            .flags = config.cxx_flags,
        },
        .link_libraries = link_libraries,
    }, config.executable_config);

    test_exe.root_module.addCSourceFile(.{
        .file = b.path(ProjectPaths.harness ++ "runner.cc"),
        .flags = config.cxx_flags,
    });

    if (config.profile) {
        test_exe.root_module.c_macros.append(b.allocator, stdx_profile_define) catch @panic("OOM");
    }
    return test_exe;
}

/// Call with stdx's builder
pub fn compressor(b: *std.Build) *std.Build.Step.Compile {
    const libarchive_dep = libarchive.build(b, .{
        .target = b.graph.host,
        .optimize = .ReleaseFast,
    });

    const headers = b.addTranslateC(.{
        .root_source_file = b.path(ProjectPaths.compressor ++ "c.h"),
        .target = b.graph.host,
        .optimize = .ReleaseFast,
    });
    headers.addIncludePath(libarchive_dep.artifact.getEmittedIncludeTree());

    const compressor_exe = utils.createExecutable(b, .{
        .zig_main = b.path(ProjectPaths.compressor ++ "main.zig"),
        .target = b.graph.host,
        .optimize = .ReleaseFast,
        .link_libraries = &.{libarchive_dep.artifact},
        .imports = &.{
            .{
                .name = "c",
                .module = headers.createModule(),
            },
        },
    }, .{
        .name = "compressor",
        .behavior = .standalone,
    });

    if (b.graph.host.result.os.tag != .macos) return compressor_exe;
    if (b.graph.environ_map.get("SDKROOT")) |sdkroot| {
        const mod = compressor_exe.root_module;
        mod.addFrameworkPath(.{ .cwd_relative = b.fmt("{s}/System/Library/Frameworks", .{sdkroot}) });
        mod.addSystemIncludePath(.{ .cwd_relative = b.fmt("{s}/usr/include", .{sdkroot}) });
    }
    return compressor_exe;
}
