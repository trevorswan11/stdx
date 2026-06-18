const std = @import("std");

const CoverageInfo = struct {
    percent_covered: []const u8,
};
const ParsedCovInfo = std.json.Parsed(CoverageInfo);

const Self = @This();

step: std.Build.Step,
report: std.Build.LazyPath,
curl: *std.Build.Step.Run,

pub fn init(
    b: *std.Build,
    report: std.Build.LazyPath,
    curl: *std.Build.Step.Run,
) *Self {
    const self = b.allocator.create(Self) catch @panic("OOM");
    self.* = .{
        .step = .init(.{
            .id = .custom,
            .name = "coverage-parse",
            .owner = b,
            .makeFn = coverageParse,
        }),
        .report = report,
        .curl = curl,
    };
    return self;
}

fn coverageParse(step: *std.Build.Step, _: std.Build.Step.MakeOptions) !void {
    const self: *Self = @fieldParentPtr("step", step);

    const b = step.owner;
    const allocator = b.allocator;

    const json_path = try self.report.path(b, "kcov-merged/coverage.json").getPath4(b, step);
    const contents = try b.build_root.handle.readFileAlloc(
        b.graph.io,
        json_path.sub_path,
        allocator,
        .unlimited,
    );

    const parsed: ParsedCovInfo = try std.json.parseFromSlice(
        CoverageInfo,
        allocator,
        contents,
        .{ .ignore_unknown_fields = true },
    );

    const precise_percentage = parsed.value.percent_covered;
    const last_dot = std.mem.lastIndexOfScalar(u8, precise_percentage, '.');
    const percentage = if (last_dot) |dot| precise_percentage[0..dot] else precise_percentage;
    self.curl.addArg("-s");
    self.curl.addArg(b.fmt("https://img.shields.io/badge/Coverage-{s}%25-pink", .{percentage}));
    std.log.info("Test Coverage: {s}%", .{percentage});
}
