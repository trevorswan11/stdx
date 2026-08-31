const std = @import("std");

const c = @import("c");

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const io = init.io;

    var stderr_buf: [1024]u8 = undefined;
    const stderr_handle: std.Io.File = .stderr();
    var writer = stderr_handle.writer(io, &stderr_buf);
    const stderr = &writer.interface;

    const args = try init.minimal.args.toSlice(allocator);
    if (args.len != 4) {
        try stderr.print("Usage: {s} [zip|zst] [output_file] [input_dir]\n", .{args[0]});
        try stderr.flush();
        return error.UsageError;
    }

    const format = args[1];
    const out_path = args[2];
    const in_dir = args[3];

    const archive = c.archive_write_new() orelse return error.ArchiveNewFailed;
    defer _ = c.archive_write_free(archive);

    // Zip and zstd archives are supported
    if (std.mem.eql(u8, format, "zip")) {
        _ = c.archive_write_set_format_zip(archive);
    } else if (std.mem.eql(u8, format, "zst")) {
        _ = c.archive_write_set_format_pax_restricted(archive);
        _ = c.archive_write_add_filter_zstd(archive);
    } else {
        return error.InvalidArchiveFormat;
    }

    if (c.archive_write_open_filename(archive, out_path.ptr) != c.ARCHIVE_OK) {
        try stderr.print("Open Error: {s}\n", .{c.archive_error_string(archive)});
        try stderr.flush();
        return error.ArchiveOpenFailed;
    }
    defer _ = c.archive_write_close(archive);

    // The build system guarantees that everything in the input directory is ready to be compressed
    var dir = try std.Io.Dir.cwd().openDir(io, in_dir, .{ .iterate = true });
    defer dir.close(io);
    const dir_basename = std.Io.Dir.path.basename(in_dir);
    var walker = try dir.walk(allocator);
    defer walker.deinit();

    const buf_size = 64 * 1024;
    var file_reader_buf: [buf_size]u8 = undefined;
    const input_buf = file_reader_buf[0 .. buf_size / 2];
    const output_buf = file_reader_buf[buf_size / 2 ..];

    while (try walker.next(io)) |entry| {
        if (entry.kind != .file and entry.kind != .directory) continue;
        const archive_entry = c.archive_entry_new() orelse return error.EntryNewFailed;
        defer c.archive_entry_free(archive_entry);

        // Put the files into a subdirectory so decompressing doesn't dump into cwd
        const entry_path = try std.Io.Dir.path.joinZ(allocator, &.{ dir_basename, entry.path });
        c.archive_entry_set_pathname(archive_entry, entry_path.ptr);

        // File stats for the header
        const stat = try entry.dir.statFile(io, entry.basename, .{});
        c.archive_entry_set_mtime(archive_entry, @intCast(@divTrunc(stat.mtime.nanoseconds, std.time.ns_per_s)), 0);

        if (entry.kind == .directory) {
            c.archive_entry_set_perm(archive_entry, 0o755);
            c.archive_entry_set_size(archive_entry, 0);
            c.archive_entry_set_filetype(archive_entry, 0o040000);

            // Nested items in the directory are handled naturally by the walker
            if (c.archive_write_header(archive, archive_entry) != c.ARCHIVE_OK) {
                try stderr.print("Header error: {s}\n", .{c.archive_error_string(archive)});
                try stderr.flush();
            }
            continue;
        } else {
            c.archive_entry_set_perm(archive_entry, if (looksExecutable(io, entry.dir, entry.basename)) 0o755 else 0o644);
            c.archive_entry_set_size(archive_entry, @intCast(stat.size));
            c.archive_entry_set_filetype(archive_entry, 0o100000);
        }

        if (c.archive_write_header(archive, archive_entry) != c.ARCHIVE_OK) {
            try stderr.print("Header error: {s}\n", .{c.archive_error_string(archive)});
            try stderr.flush();
            continue;
        }

        const file = try entry.dir.openFile(io, entry.basename, .{});
        defer file.close(io);
        var reader = file.reader(io, input_buf);

        while (!reader.atEnd()) {
            const bytes_read = try reader.interface.readSliceShort(output_buf);
            _ = c.archive_write_data(archive, output_buf, bytes_read);
        }
    }

    try stderr.flush();
}

/// Best-effort check for whether a file should carry the execute bit in the archive
fn looksExecutable(io: std.Io, dir: std.Io.Dir, sub_path: []const u8) bool {
    const file = dir.openFile(io, sub_path, .{}) catch return false;
    defer file.close(io);

    var reader_buf: [64]u8 = undefined;
    var out_buf: [4]u8 = undefined;
    var reader = file.reader(io, &reader_buf);
    const n = reader.interface.readSliceShort(&out_buf) catch return false;
    const magic = out_buf[0..n];

    const prefixes = [_][]const u8{
        "MZ", // Windows executable/DLL
        "#!", // shebang script
        "\x7fELF", // ELF
        "\xfe\xed\xfa\xce", "\xfe\xed\xfa\xcf", // Mach-O, big endian
        "\xce\xfa\xed\xfe", "\xcf\xfa\xed\xfe", // Mach-O, little endian
        "\xca\xfe\xba\xbe", "\xbe\xba\xfe\xca", // Mach-O universal (fat)
    };
    for (prefixes) |prefix| {
        if (std.mem.startsWith(u8, magic, prefix)) return true;
    }
    return false;
}
