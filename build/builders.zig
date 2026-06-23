const std = @import("std");

const ProjectPaths = @import("ProjectPaths.zig");
const Dependency = @import("../third-party/Dependency.zig");
const ArrayList = @import("array_list.zig").ArrayList;

const utils = @import("utils.zig");
const catch2 = @import("../third-party/catch2.zig");
const libarchive = @import("../third-party/libarchive.zig");

pub const stdx_profile_define = "-DSTDX_PROFILE";

fn BuildHarnessTestConfig(Stdx: type) type {
    return struct {
        target: std.Build.ResolvedTarget,
        optimize: std.builtin.OptimizeMode,
        stdx: Stdx,
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
}

fn makeGetLib(data: anytype, comptime accessors: struct {
    artifact_name: []const u8,
    field_name: ?[]const u8 = null,
}) *std.Build.Step.Compile {
    return switch (data) {
        .dep => |d| d.artifact(accessors.artifact_name),
        .internal => |i| @field(
            i,
            accessors.field_name orelse std.fmt.comptimePrint("lib{s}", .{accessors.artifact_name}),
        ),
    };
}

pub const BuildStrappedTestConfig = BuildHarnessTestConfig(union(enum) {
    const Self = @This();

    dep: *std.Build.Dependency,
    internal: struct {
        stdx_builder: *std.Build,
        libstdx: *std.Build.Step.Compile,
        libcatch2: *std.Build.Step.Compile,
    },

    pub fn getLibstdx(self: Self) *std.Build.Step.Compile {
        return makeGetLib(self, .{ .artifact_name = "stdx" });
    }

    pub fn getLibcatch2(self: Self) *std.Build.Step.Compile {
        return makeGetLib(self, .{ .artifact_name = "catch2" });
    }

    pub fn getStdxBuilder(self: Self) *std.Build {
        return switch (self) {
            .dep => |d| d.builder,
            .internal => |i| i.stdx_builder,
        };
    }
});

/// Build's a zig-harness-driven catch2 test artifact
pub fn strappedTest(b: *std.Build, config: BuildStrappedTestConfig) *std.Build.Step.Compile {
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
        .files = &.{ "runner.cc", "allocator.cc" },
        .flags = config.cxx_flags,
    });

    if (config.profile) {
        test_exe.root_module.c_macros.append(b.allocator, stdx_profile_define) catch @panic("OOM");
    }
    return test_exe;
}

pub const BuildFuzzTestConfig = BuildHarnessTestConfig(union(enum) {
    const Self = @This();

    dep: *std.Build.Dependency,
    internal: struct {
        stdx_builder: *std.Build,
        libstdx: *std.Build.Step.Compile,
        libfuzztest: *std.Build.Step.Compile,
        libgtest: *std.Build.Step.Compile,
    },

    pub fn getLibstdx(self: Self) *std.Build.Step.Compile {
        return makeGetLib(self, .{ .artifact_name = "stdx" });
    }

    pub fn getLibfuzztest(self: Self) *std.Build.Step.Compile {
        return makeGetLib(self, .{ .artifact_name = "fuzztest" });
    }

    pub fn getLibgtest(self: Self) *std.Build.Step.Compile {
        return makeGetLib(self, .{ .artifact_name = "gtest" });
    }

    pub fn getStdxBuilder(self: Self) *std.Build {
        return switch (self) {
            .dep => |d| d.builder,
            .internal => |i| i.stdx_builder,
        };
    }
});

const fuzz_dropped_flags: []const []const u8 = &.{
    "-Wpedantic",
    "-Wconversion",
    "-Wextra",
    "-Werror",
};

fn fuzzCxxFlags(b: *std.Build, flags: []const []const u8) []const []const u8 {
    var out: ArrayList([]const u8) = .fromSlice(b, &.{});
    outer: for (flags) |flag| {
        for (fuzz_dropped_flags) |dropped| {
            if (std.mem.eql(u8, flag, dropped)) continue :outer;
        }
        out.append(flag);
    }
    return out.items();
}

/// Builds a fuzztest/gtest-driven fuzz test artifact
///
/// Assumes that you are on a target that can fuzz test
pub fn fuzzTest(b: *std.Build, config: BuildFuzzTestConfig) *std.Build.Step.Compile {
    var link_libraries: ArrayList(*std.Build.Step.Compile) = .fromSlice(b, config.link_libraries);
    link_libraries.appendSlice(&.{
        config.stdx.getLibstdx(),
        config.stdx.getLibfuzztest(),
        config.stdx.getLibgtest(),
    });
    const filtered_flags = fuzzCxxFlags(b, config.cxx_flags);

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
            .flags = filtered_flags,
        },
        .link_libraries = link_libraries.items(),
    }, config.executable_config);
    Dependency.addFrameworkSearchPaths(test_exe.root_module, config.target);

    test_exe.root_module.addCSourceFiles(.{
        .root = harness_path,
        .files = &.{ "fuzzer.cc", "allocator.cc" },
        .flags = filtered_flags,
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
    Dependency.addFrameworkSearchPaths(compressor_exe.root_module, b.graph.host);
    return compressor_exe;
}
