const std = @import("std");

const Dependency = @import("../Dependency.zig");
const Config = Dependency.Config;
const Artifact = Dependency.Artifact;

const re2 = @import("sources/re2.zig");

pub fn build(b: *std.Build, abseil: Dependency, config: Config) Dependency {
    const upstream = b.dependency("re2", .{});
    const mod = b.createModule(.{
        .target = config.target,
        .optimize = config.optimize,
        .link_libcpp = true,
    });
    Dependency.addFrameworkSearchPaths(mod, config.target);

    const root = upstream.path("");
    mod.addSystemIncludePath(root);

    mod.addCSourceFiles(.{
        .root = root,
        .files = &re2.sources,
        .flags = &.{"-std=c++17"},
    });

    mod.linkLibrary(abseil.artifact);
    const lib = b.addLibrary(.{
        .name = "re2",
        .root_module = mod,
    });
    lib.installLibraryHeaders(abseil.artifact);

    for (re2.public_includes) |inc| {
        lib.installHeader(root.path(b, inc), inc);
    }
    b.installArtifact(lib);
    return .{ .upstream = upstream, .artifact = lib };
}
