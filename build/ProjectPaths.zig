const std = @import("std");

const utils = @import("utils.zig");

pub const include = "include/";
pub const src = "src/";
pub const tests = "tests/";
pub const tools = "tools/";
pub const harness = tools ++ "harness/";
pub const compressor = tools ++ "compressor/";
pub const build = "build/";

pub fn collectToolingPaths(b: *std.Build) !struct {
    zig_paths: []const []const u8,
    cxx_paths: []const []const u8,
} {
    const zig_paths = try std.mem.concat(b.allocator, []const u8, &.{
        try utils.collectFiles(b, build, .{
            .allowed_extensions = &.{".zig"},
            .extra_files = &.{
                "build.zig",
                "build.zig.zon",
            },
        }),
        try utils.collectFiles(b, tools, .{ .allowed_extensions = &.{".zig"} }),
    });

    const cxx_paths = try std.mem.concat(b.allocator, []const u8, &.{
        try utils.collectFiles(b, include, .{ .allowed_extensions = &.{".hh"} }),
        try utils.collectFiles(b, src, .{ .allowed_extensions = &.{".cc"} }),
        try utils.collectFiles(b, tests, .{ .allowed_extensions = &.{ ".hh", ".cc" } }),
    });

    return .{ .zig_paths = zig_paths, .cxx_paths = cxx_paths };
}
