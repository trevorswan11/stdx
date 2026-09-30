const std = @import("std");

pub const header_extensions = [_][]const u8{ ".hh", ".h", ".hpp", "hxx", ".inc" };

// Every artifact of every packaged target shares these directories, so each is walked once. Keyed
// by absolute path, since a consumer and its dependencies resolve relative paths differently.
var dir_digests: std.StringHashMapUnmanaged(u64) = .empty;

/// Hashes the header-like files under each directory, which may be build-root-relative or absolute
pub fn digest(b: *std.Build, dirs: []const []const u8) !u64 {
    var hasher: std.hash.Wyhash = .init(0);
    for (dirs) |dir_path| {
        const absolute = if (std.fs.path.isAbsolute(dir_path)) dir_path else b.pathFromRoot(dir_path);
        const entry = try dir_digests.getOrPut(b.graph.arena, absolute);
        if (!entry.found_existing) entry.value_ptr.* = try digestDir(b, absolute);
        hasher.update(dir_path);
        hasher.update(&std.mem.toBytes(entry.value_ptr.*));
    }
    return hasher.final();
}

fn digestDir(b: *std.Build, dir_path: []const u8) !u64 {
    const io = b.graph.io;
    var dir = std.Io.Dir.cwd().openDir(io, dir_path, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return 0,
        else => return err,
    };
    defer dir.close(io);

    var paths: std.ArrayList([]const u8) = .empty;
    var walker = try dir.walk(b.allocator);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !isHeader(entry.basename)) continue;
        try paths.append(b.allocator, b.dupe(entry.path));
    }

    // Walk order is filesystem-dependent, so sort for a stable digest
    std.mem.sort([]const u8, paths.items, {}, lessThan);

    var hasher: std.hash.Wyhash = .init(0);
    for (paths.items) |path| {
        const contents = try dir.readFileAlloc(io, path, b.allocator, .unlimited);
        defer b.allocator.free(contents);
        hasher.update(path);
        hasher.update(&std.mem.toBytes(contents.len));
        hasher.update(contents);
    }
    return hasher.final();
}

/// Adds the stamp source for `dirs` to the artifact's root module
pub fn add(b: *std.Build, artifact: *std.Build.Step.Compile, dirs: []const []const u8) !void {
    const hash = try digest(b, dirs);
    const files = b.addWriteFiles();
    const stamp = files.add("dep_stamp.cc", b.fmt("// header digest {x:0>16}\n", .{hash}));
    artifact.root_module.addCSourceFile(.{ .file = stamp, .language = .cpp });
}

pub fn isHeader(basename: []const u8) bool {
    for (header_extensions) |ext| {
        if (std.mem.endsWith(u8, basename, ext)) return true;
    }
    return false;
}

fn lessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.lessThan(u8, lhs, rhs);
}

test "header-like files" {
    try std.testing.expect(isHeader("vector.hh"));
    try std.testing.expect(isHeader("stdio.h"));
    try std.testing.expect(isHeader("table.inc"));
    try std.testing.expect(!isHeader("main.cc"));
    try std.testing.expect(!isHeader("notes.hh.txt"));
}
