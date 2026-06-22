const std = @import("std");

const ProjectPaths = @import("ProjectPaths.zig");
const ArrayList = @import("array_list.zig").ArrayList;

const utils = @import("utils.zig");
const catch2 = @import("../third-party/catch2.zig");
const libarchive = @import("../third-party/libarchive.zig");

pub const stdx_profile_define = "-DSTDX_PROFILE";

pub const BuildHarnessTestConfig = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    stdx: union(enum) {
        dep: *std.Build.Dependency,
        internal: struct {
            stdx_builder: *std.Build,
            libstdx: *std.Build.Step.Compile,
            libcatch2: *std.Build.Step.Compile,
        },

        pub fn getLibstdx(self: @This()) *std.Build.Step.Compile {
            return switch (self) {
                .dep => |d| d.artifact("stdx"),
                .internal => |i| i.libstdx,
            };
        }

        pub fn getLibcatch2(self: @This()) *std.Build.Step.Compile {
            return switch (self) {
                .dep => |d| d.artifact("catch2"),
                .internal => |i| i.libcatch2,
            };
        }

        pub fn getStdxBuilder(self: @This()) *std.Build {
            return switch (self) {
                .dep => |d| d.builder,
                .internal => |i| i.stdx_builder,
            };
        }
    },
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
};

/// Build's a zig-harness-driven catch2 test artifact
pub fn strappedTest(b: *std.Build, config: BuildHarnessTestConfig) *std.Build.Step.Compile {
    var link_libraries: ArrayList(*std.Build.Step.Compile) = .fromSlice(b, config.link_libraries);
    link_libraries.appendSlice(&.{ config.stdx.getLibstdx(), config.stdx.getLibcatch2() });

    const stdx_builder = config.stdx.getStdxBuilder();
    const harness_path = stdx_builder.path(ProjectPaths.harness);
    const test_exe = utils.createExecutable(b, .{
        .target = config.target,
        .optimize = config.optimize,
        .zig_main = harness_path.path(stdx_builder, "main.zig"),
        .include_paths = config.include_paths,
        .config_headers = config.config_headers,
        .system_include_paths = config.system_include_paths,
        .cxx = .{
            .files = config.cxx_files,
            .flags = config.cxx_flags,
        },
        .link_libraries = link_libraries.items(),
    }, config.executable_config);

    test_exe.root_module.addCSourceFiles(.{
        .root = harness_path,
        .files = &.{ "runner.cc", "allocator.cc", "listener.cc" },
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
