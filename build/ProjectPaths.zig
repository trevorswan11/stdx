const std = @import("std");

const utils = @import("utils.zig");
const steps = @import("steps.zig");

pub const include = "include/";
pub const src = "src/";
pub const tests = "tests/";
pub const tools = "tools/";
pub const harness = tools ++ "harness/";
pub const fuzzer = tools ++ "fuzzer/";
pub const compressor = tools ++ "compressor/";
pub const fuzz = "fuzz/";
pub const build = "build/";

pub fn collectToolingPaths(b: *std.Build) !steps.FmtPaths {
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
        try utils.collectFiles(b, tools, .{ .allowed_extensions = &.{ ".hh", ".cc", ".h" } }),
    });

    return .{ .zig = zig_paths, .cxx = cxx_paths };
}
