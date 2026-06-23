const std = @import("std");

const Dependency = @import("../Dependency.zig");
const Config = Dependency.Config;
const Artifact = Dependency.Artifact;
const AbseilBuilder = @import("../abseil/AbseilBuilder.zig");

const re2 = @import("sources/re2.zig");

pub fn build(b: *std.Build, abseil: *AbseilBuilder) ?Dependency {
    const upstream = b.lazyDependency("re2", .{}) orelse return null;
    const mod = b.createModule(.{
        .target = abseil.metadata.config.target,
        .optimize = abseil.metadata.config.optimize,
        .link_libcpp = true,
    });
    Dependency.addFrameworkSearchPaths(mod, abseil.metadata.config.target);

    const root = upstream.path("");
    mod.addIncludePath(root);

    mod.addCSourceFiles(.{
        .root = root,
        .files = &re2.sources,
        .flags = &.{"-std=c++17"},
    });

    mod.linkLibrary(abseil.base.base);
    mod.linkLibrary(abseil.strings.strings);
    mod.linkLibrary(abseil.strings.str_format_internal);
    mod.linkLibrary(abseil.hash.hash);
    mod.linkLibrary(abseil.container.raw_hash_set);
    mod.linkLibrary(abseil.synchronization.synchronization);
    mod.linkLibrary(abseil.log.message);
    mod.linkLibrary(abseil.log.globals);

    const lib = b.addLibrary(.{
        .name = "re2",
        .root_module = mod,
    });

    for (re2.public_includes) |inc| {
        lib.installHeader(root.path(b, inc), inc);
    }
    return .{ .upstream = upstream, .artifact = lib };
}
