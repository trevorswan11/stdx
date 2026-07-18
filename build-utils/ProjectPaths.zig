const std = @import("std");

const ArrayList = @import("array_list.zig").ArrayList;

const utils = @import("utils.zig");
const steps = @import("steps.zig");

pub const include = "include/";
pub const src = "src/";
pub const tests = "tests/";
pub const fuzz_tests = "fuzz/";
pub const tools = "tools/";
pub const harness = tools ++ "harness/";
pub const compressor = tools ++ "compressor/";
pub const build = "build-utils/";

pub fn collectToolingPaths(b: *std.Build) !steps.FmtPaths {
    var zig_paths: ArrayList([]const u8) = .init(b);
    try utils.collectFilesInto(b, build, .{
        .allowed_extensions = &.{".zig"},
        .extra_files = &.{
            "build.zig",
            "build.zig.zon",
        },
    }, &zig_paths);
    try utils.collectFilesInto(b, tools, .{ .allowed_extensions = &.{".zig"} }, &zig_paths);

    var cxx_paths: ArrayList([]const u8) = .init(b);
    try utils.collectFilesInto(b, include, .{ .allowed_extensions = &.{".hh"} }, &cxx_paths);
    try utils.collectFilesInto(b, src, .{ .allowed_extensions = &.{".cc"} }, &cxx_paths);
    try utils.collectFilesInto(b, tests, .{ .allowed_extensions = &.{ ".hh", ".cc" } }, &cxx_paths);
    try utils.collectFilesInto(b, fuzz_tests, .{ .allowed_extensions = &.{ ".hh", ".cc" } }, &cxx_paths);
    try utils.collectFilesInto(b, tools, .{ .allowed_extensions = &.{ ".hh", ".cc" } }, &cxx_paths);

    return .{ .zig = zig_paths.wrapped.items, .cxx = cxx_paths.wrapped.items };
}
