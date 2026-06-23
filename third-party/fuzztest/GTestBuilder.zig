const std = @import("std");

const Dependency = @import("../Dependency.zig");
const Config = Dependency.Config;
const Artifact = Dependency.Artifact;

const Self = @This();

const Metadata = struct {
    upstream: *std.Build.Dependency,
    config: Config,
};

const flags = [_][]const u8{"-std=c++17"};

b: *std.Build,
metadata: Metadata,

gtest: Artifact = undefined,
gtest_main: Artifact = undefined,
gmock: Artifact = undefined,

pub fn build(b: *std.Build, config: Config) *Self {
    const upstream = b.dependency("googletest", .{});

    const self = b.allocator.create(Self) catch @panic("OOM");
    self.* = .{
        .b = b,
        .metadata = .{
            .upstream = upstream,
            .config = config,
        },
    };

    self.gtest = self.buildArtifact(.{
        .name = "gtest",
        .root = upstream.path("googletest"),
        .source = "src/gtest-all.cc",
    });
    self.gtest_main = self.buildArtifact(.{
        .name = "gtest_main",
        .root = upstream.path("googletest"),
        .source = "src/gtest_main.cc",
    });
    self.gmock = self.buildArtifact(.{
        .name = "gmock",
        .root = upstream.path("googlemock"),
        .source = "src/gmock-all.cc",
    });
    self.gmock.root_module.linkLibrary(self.gtest);

    return self;
}

fn buildArtifact(self: *const Self, config: struct {
    name: []const u8,
    root: std.Build.LazyPath,
    source: []const u8,
}) Artifact {
    const b = self.b;
    const mod = b.createModule(.{
        .target = self.metadata.config.target,
        .optimize = self.metadata.config.optimize,
        .link_libcpp = true,
    });

    const include = config.root.path(b, "include");
    mod.addCSourceFile(.{
        .file = config.root.path(b, config.source),
        .flags = &flags,
    });
    mod.addIncludePath(include);
    mod.addIncludePath(config.root);

    const artifact = b.addLibrary(.{
        .name = config.name,
        .root_module = mod,
    });
    artifact.installHeadersDirectory(include, "", .{});
    return artifact;
}
