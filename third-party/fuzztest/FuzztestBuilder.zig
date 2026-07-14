const std = @import("std");

const Dependency = @import("../Dependency.zig");
const Config = Dependency.Config;
const Artifact = Dependency.Artifact;
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

pub fn canFuzz(target: std.Build.ResolvedTarget) bool {
    return target.result.os.tag != .windows;
}

pub fn build(
    b: *std.Build,
    abseil: Dependency,
    gtest: *GTestBuilder,
    re2: Dependency,
) *Self {
    const upstream = b.dependency("fuzztest", .{});

    const self = b.allocator.create(Self) catch @panic("OOM");
    self.* = .{
        .b = b,
        .metadata = .{
            .upstream = upstream,
            .config = gtest.metadata.config,
            .root = upstream.path(""),
        },
    };

    self.fuzztest = self.buildCore(abseil, re2, gtest);
    b.installArtifact(self.fuzztest);
    self.fuzztest_gtest_main = self.buildGtestMain(gtest);
    b.installArtifact(self.fuzztest_gtest_main);

    return self;
}

fn buildCore(
    self: *const Self,
    abseil: Dependency,
    re2: Dependency,
    gtest: *GTestBuilder,
) Artifact {
    const b = self.b;
    const mod = self.addModule(&fuzztest_mod.sources);
    mod.addIncludePath(re2.upstream.path(""));

    const link_libs = [_]Artifact{ abseil.artifact, re2.artifact, gtest.gtest };
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
