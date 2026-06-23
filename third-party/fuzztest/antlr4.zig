const std = @import("std");

const Dependency = @import("../Dependency.zig");
const Config = Dependency.Config;
const Artifact = Dependency.Artifact;

const antlr4 = @import("sources/antlr4.zig");

pub fn build(b: *std.Build, config: Config) ?Dependency {
    const upstream = b.lazyDependency("antlr4", .{}) orelse return null;
    const mod = b.createModule(.{
        .target = config.target,
        .optimize = config.optimize,
        .link_libcpp = true,
    });

    const root = upstream.path(antlr4.root);
    for (antlr4.includes) |inc| mod.addIncludePath(root.path(b, inc));
    if (config.target.result.os.tag.isDarwin()) {
        Dependency.addFrameworkSearchPaths(mod, config.target);
        mod.linkFramework("CoreFoundation", .{});
    }

    mod.addCSourceFiles(.{
        .root = root,
        .files = &antlr4.sources,
        .flags = &.{
            "-std=c++17",
            "-Wno-overloaded-virtual",
            "-Wno-dollar-in-identifier-extension",
            "-Wno-four-char-constants",
            "-DANTLR4CPP_STATIC",
        },
    });

    const lib = b.addLibrary(.{
        .name = "antlr4_static",
        .root_module = mod,
    });
    lib.installHeadersDirectory(root.path(b, "src"), "antlr4-runtime", .{});
    return .{ .upstream = upstream, .artifact = lib };
}
