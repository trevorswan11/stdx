const std = @import("std");

const Dependency = @import("../Dependency.zig");
const Config = Dependency.Config;
const Artifact = Dependency.Artifact;
const AbseilBuilder = @import("../abseil/AbseilBuilder.zig");

const re2 = @import("sources/re2.zig");

pub fn build(b: *std.Build, abseil: *AbseilBuilder) Dependency {
    const upstream = b.dependency("re2", .{});
    const mod = b.createModule(.{
        .target = abseil.metadata.config.target,
        .optimize = abseil.metadata.config.optimize,
        .link_libcpp = true,
    });
    Dependency.addFrameworkSearchPaths(mod, abseil.metadata.config.target);

    const root = upstream.path("");
    mod.addSystemIncludePath(root);

    mod.addCSourceFiles(.{
        .root = root,
        .files = &re2.sources,
        .flags = &.{"-std=c++17"},
    });

    const link_libs = [_]Artifact{
        abseil.base.base,
        abseil.strings.strings,
        abseil.strings.str_format_internal,
        abseil.hash.hash,
        abseil.container.raw_hash_set,
        abseil.synchronization.synchronization,
        abseil.log.message,
        abseil.log.globals,
    };

    const lib = b.addLibrary(.{
        .name = "re2",
        .root_module = mod,
    });
    for (link_libs) |link_lib| {
        mod.linkLibrary(link_lib);
        lib.installLibraryHeaders(link_lib);
    }

    for (re2.public_includes) |inc| {
        lib.installHeader(root.path(b, inc), inc);
    }
    return .{ .upstream = upstream, .artifact = lib };
}
