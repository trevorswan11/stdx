const std = @import("std");

const KcovBuilder = @import("../third-party/kcov/KcovBuilder.zig");
const RemoveDir = @import("RemoveDir.zig");

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

/// Adds coverage reporting on supported platforms for all test artifacts
pub fn addStep(b: *std.Build, configs: []const KcovBuilder.RunKcovConfig) !void {
    const kcov = KcovBuilder.build(b, .{
        .target = b.graph.host,
        .optimize = .ReleaseFast,
    }) orelse return;

    var reports: std.ArrayList(KcovBuilder.RunKcovReport) = .empty;
    for (configs) |config| {
        try reports.append(b.allocator, try kcov.runKcov(config));
    }

    const coverage = b.step("coverage", "Generate coverage report");
    for (reports.items) |report| {
        coverage.dependOn(&report.runner.step);
    }
    const merged = kcov.mergeKcovReports(reports.items);

    const install_merged = b.option(
        bool,
        "install-merged",
        "install merged kcov report",
    ) orelse false;
    if (install_merged) {
        const merged_output_dirname = "merged";
        const install = b.addInstallDirectory(.{
            .source_dir = merged.output_dir,
            .install_dir = .prefix,
            .install_subdir = merged_output_dirname,
        });

        const remove: *RemoveDir = .init(b, .{
            .cwd_relative = b.pathJoin(&.{
                b.install_prefix,
                merged_output_dirname,
            }),
        });
        install.step.dependOn(&remove.step);
        coverage.dependOn(&install.step);
    }

    const curl = b.addRunArtifact(kcov.curl.execurl);
    curl.addArg("-o");
    const badge_file = curl.addOutputFileArg("coverage.svg");
    const install = b.addInstallFile(badge_file, "coverage.svg");
    curl.has_side_effects = true;

    const parser: *Self = .init(b, merged.output_dir, curl);
    parser.step.dependOn(&merged.runner.step);
    curl.step.dependOn(&parser.step);
    coverage.dependOn(&curl.step);
    coverage.dependOn(&install.step);
}
