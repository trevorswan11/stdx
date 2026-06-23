const std = @import("std");

const Dependency = @import("../Dependency.zig");
const Config = Dependency.Config;
const Artifact = Dependency.Artifact;

const algorithm = @import("sources/abseil/algorithm.zig");
const base = @import("sources/abseil/base.zig");
const cleanup = @import("sources/abseil/cleanup.zig");
const container = @import("sources/abseil/container.zig");
const crc = @import("sources/abseil/crc.zig");
const debugging = @import("sources/abseil/debugging.zig");
const flags = @import("sources/abseil/flags.zig");
const functional = @import("sources/abseil/functional.zig");
const hash = @import("sources/abseil/hash.zig");
const log = @import("sources/abseil/log.zig");
const memory = @import("sources/abseil/memory.zig");
const meta = @import("sources/abseil/meta.zig");
const numeric = @import("sources/abseil/numeric.zig");
const profiling = @import("sources/abseil/profiling.zig");
const random = @import("sources/abseil/random.zig");
const status = @import("sources/abseil/status.zig");
const strings = @import("sources/abseil/strings.zig");
const synchronization = @import("sources/abseil/synchronization.zig");
const time = @import("sources/abseil/time.zig");
const types = @import("sources/abseil/types.zig");
const utility = @import("sources/abseil/utility.zig");

const Self = @This();

const Metadata = struct {
    upstream: *std.Build.Dependency,
    config: Config,
    root: std.Build.LazyPath,
};

const Interfaces = struct {};

const Artifacts = struct {};

b: *std.Build,
metadata: Metadata,

interfaces: Interfaces = .{},
artifacts: Artifacts = .{},

pub fn init(b: *std.Build, config: Config) ?*Self {
    const upstream = b.lazyDependency("abseil", .{}) orelse return null;

    const self = b.allocator.create(Self) catch @panic("OOM");
    self.* = .{
        .b = b,
        .metadata = .{
            .upstream = upstream,
            .config = config,
            .root = upstream.path("absl"),
        },
    };
    return self;
}

pub fn build(self: *Self) void {
    
}

/// Adds a library to the build graph that can be linked against
fn addLibrary(self: *const Self, config: struct {
    name: []const u8,
    root: std.Build.LazyPath,
    sources: []const []const u8,
    link_libraries: []const Artifact = &.{},
    extra_include_paths: []const std.Build.LazyPath = &.{},
    config_headers: []const *std.Build.Step.ConfigHeader = &.{},
}) Artifact {
    const b = self.b;
    const mod = b.createModule(.{
        .target = self.metadata.config.target,
        .optimize = self.metadata.config.optimize,
        .link_libc = true,
        .link_libcpp = true,
    });

    mod.addCSourceFiles(.{
        .root = config.root,
        .files = config.sources,
        .flags = &compile_flags,
    });
    mod.addIncludePath(config.root);
    for (config.extra_include_paths) |inc| mod.addIncludePath(inc);
    for (config.config_headers) |header| mod.addConfigHeader(header);
    for (config.link_libraries) |link| mod.linkLibrary(link);

    const lib = b.addLibrary(.{
        .name = b.fmt("absl_{s}", config.name),
        .root_module = mod,
    });

    lib.installHeadersDirectory(config.root, "absl", .{
        .include_extensions = &.{ ".h", ".inc" },
    });
    for (config.link_libraries) |link| lib.installLibraryHeaders(link);

    for (config.extra_include_paths) |inc| lib.installHeadersDirectory(inc, "absl", .{
        .include_extensions = &.{ ".h", ".inc" },
    });
    for (config.config_headers) |header| lib.installConfigHeader(header);

    return lib;
}

/// Adds the passed headers to a cached directory to include
fn addInterface(self: *const Self, config: struct {
    name: []const u8,
    root: std.Build.LazyPath,
    include_files: []const []const u8,
    include_directories: []const []const u8,
}) std.Build.LazyPath {
    std.debug.assert(config.include_paths.len > 0 or config.include_directories.len > 0);
    const b = self.b;
    const write_files = b.addWriteFiles();

    for (config.include_files) |inc| {
        write_files.addCopyFile(config.root.path(b, inc), inc);
    }

    for (config.include_directories) |inc| {
        write_files.addCopyDirectory(config.root.path(b, inc), inc, .{});
    }

    return write_files.getDirectory();
}

const compile_flags = [_][]const u8{
    "std=c++23",
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
