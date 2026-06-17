const std = @import("std");

const utils = @import("utils.zig");

const LOCResult = struct {
    counts: std.StringHashMap(struct {
        line_count: usize,
        frequency: usize,
    }),
    total_line_count: usize,
    file_count: usize,

    pub fn init(allocator: std.mem.Allocator) LOCResult {
        return .{
            .counts = .init(allocator),
            .total_line_count = 0,
            .file_count = 0,
        };
    }

    // Adds a file to the counts, grouping by un-dotted extension
    pub fn logFile(self: *LOCResult, file_path: []const u8, line_count: usize) !void {
        const ext = std.Io.Dir.path.extension(file_path)[1..];
        const gop = try self.counts.getOrPut(ext);

        if (gop.found_existing) {
            gop.value_ptr.line_count += line_count;
            gop.value_ptr.frequency += 1;
        } else {
            gop.value_ptr.* = .{
                .line_count = line_count,
                .frequency = 1,
            };
        }
        self.file_count += 1;
        self.total_line_count += line_count;
    }

    pub fn print(self: *const LOCResult, io: std.Io) !void {
        const stdout_handle = std.Io.File.stdout();
        var stdout_buf: [1024]u8 = undefined;
        var stdout_writer = stdout_handle.writer(io, &stdout_buf);
        const stdout = &stdout_writer.interface;

        try stdout.print("Scanned {d} total files:\n", .{self.file_count});

        var count_iter = self.counts.iterator();
        while (count_iter.next()) |entry| {
            try stdout.print("  {d} total {s} files: {d} LOC\n", .{
                entry.value_ptr.frequency,
                entry.key_ptr.*,
                entry.value_ptr.line_count,
            });
        }
        try stdout.print("Total: {d} LOC\n", .{self.total_line_count});

        try stdout.flush();
    }
};

const Self = @This();

step: std.Build.Step,
counted_files: []const []const u8,

pub fn init(b: *std.Build, counted_files: []const []const u8) *Self {
    const self = b.allocator.create(Self) catch @panic("OOM");
    self.* = .{
        .step = .init(.{
            .id = .custom,
            .name = "cloc",
            .owner = b,
            .makeFn = count,
        }),
        .counted_files = counted_files,
    };
    return self;
}

fn count(step: *std.Build.Step, _: std.Build.Step.MakeOptions) !void {
    const b = step.owner;
    const io = b.graph.io;
    const self: *Self = @fieldParentPtr("step", step);

    const build_dir = b.build_root.handle;
    const buffer = try b.allocator.alloc(u8, 100 * 1024);
    var result: LOCResult = .init(b.allocator);

    for (self.counted_files) |file| {
        const contents = try build_dir.readFile(io, file, buffer);
        var it = std.mem.tokenizeAny(u8, contents, "\r\n");

        var lines: usize = 0;
        while (it.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\n\r");
            if (trimmed.len > 0 and !std.mem.startsWith(u8, trimmed, "//")) {
                lines += 1;
            }
        }
        try result.logFile(file, lines);
    }

    try result.print(io);
}
