const std = @import("std");

const Dependency = @import("../Dependency.zig");
const Config = Dependency.Config;
const Artifact = Dependency.Artifact;
const AbseilBuilder = @import("../abseil/AbseilBuilder.zig");
const GTestBuilder = @import("GTestBuilder.zig");

const fuzztest_mod = @import("sources/fuzztest.zig");

const Self = @This();

const Metadata = struct {
    upstream: *std.Build.Dependency,
    config: Config,
    root: std.Build.LazyPath,
};

b: *std.Build,
metadata: Metadata,

fuzztest: Artifact = undefined,
fuzztest_gtest_main: Artifact = undefined,

pub fn build(
    b: *std.Build,
    absl: *AbseilBuilder,
    gtest: *GTestBuilder,
    re2: Dependency,
) ?*Self {
    const upstream = b.lazyDependency("fuzztest", .{}) orelse return null;

    const self = b.allocator.create(Self) catch @panic("OOM");
    self.* = .{
        .b = b,
        .metadata = .{
            .upstream = upstream,
            .config = absl.metadata.config,
            .root = upstream.path(""),
        },
    };

    self.fuzztest = self.buildCore(absl, re2);
    self.fuzztest_gtest_main = self.buildGtestMain(absl, gtest);

    return self;
}

fn buildCore(
    self: *const Self,
    absl: *AbseilBuilder,
    re2: Dependency,
) Artifact {
    const b = self.b;
    const mod = self.addModule(&fuzztest_mod.sources);

    mod.linkLibrary(absl.synchronization.synchronization);
    mod.linkLibrary(absl.strings.cord);
    mod.linkLibrary(absl.container.raw_hash_set);
    mod.linkLibrary(absl.status.statusor);
    mod.linkLibrary(absl.log.message);
    mod.linkLibrary(absl.log.globals);
    mod.linkLibrary(absl.random.seed_sequences);
    mod.linkLibrary(re2.artifact);

    const lib = b.addLibrary(.{
        .name = "fuzztest",
        .root_module = mod,
    });
    lib.installHeadersDirectory(self.metadata.root.path(b, "fuzztest"), "fuzztest", .{});
    return lib;
}

fn buildGtestMain(
    self: *const Self,
    absl: *AbseilBuilder,
    gtest: *GTestBuilder,
) Artifact {
    const mod = self.addModule(&fuzztest_mod.gtest_main_sources);

    mod.linkLibrary(self.fuzztest);
    mod.linkLibrary(gtest.gtest);
    mod.linkLibrary(absl.debugging.failure_signal_handler);
    mod.linkLibrary(absl.flags.parse);

    return self.b.addLibrary(.{
        .name = "fuzztest_gtest_main",
        .root_module = mod,
    });
}

fn addModule(self: *const Self, sources: []const []const u8) *std.Build.Module {
    const b = self.b;
    const mod = b.createModule(.{
        .target = self.metadata.config.target,
        .optimize = self.metadata.config.optimize,
        .link_libcpp = true,
    });

    mod.addIncludePath(self.metadata.root);
    mod.addCSourceFiles(.{
        .root = self.metadata.root,
        .files = sources,
        .flags = &.{"-std=c++17"},
    });
    Dependency.addFrameworkSearchPaths(mod, self.metadata.config.target);
    return mod;
}
