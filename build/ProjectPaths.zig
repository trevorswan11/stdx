const std = @import("std");

const utils = @import("utils.zig");

pub const include = "include/";
pub const src = "src/";
pub const tests = "tests/";
pub const harness = "tools/harness/";
pub const compressor = "tools/compressor/";

pub fn collectCXXToolingFiles(b: *std.Build) ![]const []const u8 {
    return std.mem.concat(b.allocator, []const u8, &.{
        try utils.collectFiles(b, include, .{ .allowed_extensions = &.{".hh"} }),
        try utils.collectFiles(b, src, .{ .allowed_extensions = &.{".cc"} }),
        try utils.collectFiles(b, tests, .{ .allowed_extensions = &.{ ".hh", ".cc" } }),
    });
}
