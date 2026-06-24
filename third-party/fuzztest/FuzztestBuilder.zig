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
) *Self {
    const upstream = b.dependency("fuzztest", .{});

    const self = b.allocator.create(Self) catch @panic("OOM");
    self.* = .{
        .b = b,
        .metadata = .{
            .upstream = upstream,
            .config = absl.metadata.config,
            .root = upstream.path(""),
        },
    };

    self.fuzztest = self.buildCore(absl, re2, gtest);
    self.fuzztest_gtest_main = self.buildGtestMain(gtest);

    return self;
}

fn buildCore(
    self: *const Self,
    absl: *AbseilBuilder,
    re2: Dependency,
    gtest: *GTestBuilder,
) Artifact {
    const b = self.b;
    const mod = self.addModule(&fuzztest_mod.sources);
    mod.addIncludePath(re2.upstream.path(""));

    const link_libs = [_]Artifact{
        absl.synchronization.synchronization,
        absl.strings.cord,
        absl.container.raw_hash_set,
        absl.status.statusor,
        absl.log.message,
        absl.log.globals,
        absl.random.seed_sequences,
        absl.random.distributions,
        absl.debugging.stacktrace,
        re2.artifact,
        gtest.gtest,
        absl.debugging.failure_signal_handler,
        absl.flags.parse,
    };

    const lib = b.addLibrary(.{
        .name = "fuzztest",
        .root_module = mod,
    });
    for (link_libs) |link_lib| {
        mod.linkLibrary(link_lib);
        lib.installLibraryHeaders(link_lib);
    }

    lib.installHeadersDirectory(self.metadata.root.path(b, "fuzztest"), "fuzztest", .{});
    lib.installHeadersDirectory(self.metadata.root.path(b, "common"), "common", .{});
    return lib;
}

fn buildGtestMain(
    self: *const Self,
    gtest: *GTestBuilder,
) Artifact {
    const mod = self.addModule(&fuzztest_mod.gtest_main_sources);

    mod.linkLibrary(self.fuzztest);
    mod.linkLibrary(gtest.gtest);

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

    mod.addSystemIncludePath(self.metadata.root);
    mod.addCSourceFiles(.{
        .root = self.metadata.root,
        .files = sources,
        .flags = &.{ "-std=c++17", "-DCENTIPEDE_DISABLE_RIEGELI" },
    });
    Dependency.addFrameworkSearchPaths(mod, self.metadata.config.target);
    return mod;
}
