const std = @import("std");

const utils = @import("utils.zig");

const CDBGenerator = @import("CDBGenerator.zig");
const RemoveDir = @import("RemoveDir.zig");
const CoverageParser = @import("CoverageParser.zig");
const LOCCounter = @import("LOCCounter.zig");
const ArrayList = @import("array_list.zig").ArrayList;

pub const FmtPaths = struct {
    zig: []const []const u8,
    cxx: []const []const u8,
};

pub const FmtStepConfig = struct {
    paths: FmtPaths,
    formatter: union(enum) {
        /// Can error if clang-format is not found or is not the right version
        version: []const u8,
        artifact: *std.Build.Step.Compile,
    },
};

pub fn addFmt(b: *std.Build, config: FmtStepConfig) !struct {
    fmt: *std.Build.Step,
    fmt_check: *std.Build.Step,
} {
    const formatter, const checker = blk: switch (config.formatter) {
        .version => |version| {
            const clang_format_path = try b.findProgram(&.{"clang-format"}, &.{});
            if (!std.mem.containsAtLeast(u8, b.run(&.{ clang_format_path, "--version" }), 1, version)) {
                std.log.warn(
                    "Skipping clang-format configuration as v{s} is required but could not be found",
                    .{version},
                );
                return error.MismatchedClangFormatVersion;
            }
            break :blk .{
                b.addSystemCommand(&.{clang_format_path}),
                b.addSystemCommand(&.{clang_format_path}),
            };
        },
        .artifact => |artifact| .{ b.addRunArtifact(artifact), b.addRunArtifact(artifact) },
    };

    const zig_fmt = b.addFmt(.{ .paths = config.paths.zig });
    formatter.addArg("-i");
    formatter.addArgs(config.paths.cxx);
    const fmt_step = b.step("fmt", "Format all project files");
    fmt_step.dependOn(&formatter.step);
    fmt_step.dependOn(&zig_fmt.step);

    const zig_fmt_check = b.addFmt(.{ .paths = config.paths.zig, .check = true });
    checker.addArgs(&.{ "--dry-run", "--Werror" });
    checker.addArgs(config.paths.cxx);
    const fmt_check_step = b.step("fmt-check", "Check formatting of all project files");
    fmt_check_step.dependOn(&checker.step);
    fmt_check_step.dependOn(&zig_fmt_check.step);

    return .{
        .fmt = fmt_step,
        .fmt_check = fmt_check_step,
    };
}

pub const StaticAnalysisConfig = struct {
    cppcheck: *std.Build.Step.Compile,
    cdb_gen: *CDBGenerator,
    /// Example: "--suppress=*:*llvm/*"
    extra_suppress_patterns: ?[]const []const u8 = null,
    suppressions: ?[]const []const u8 = &.{
        "checkersReport",
        "unmatchedSuppression",
        "missingIncludeSystem",
        "unusedFunction",
        "functionStatic",
    },
    ignore_paths: ?[]const std.Build.LazyPath = null,
};

pub fn addCppcheck(b: *std.Build, config: StaticAnalysisConfig) *std.Build.Step {
    const check_step = b.step("check", "Run static analysis on all project files");
    const cppcheck_run = b.addRunArtifact(config.cppcheck);

    const installed_cppcheck_cache_path = b.cache_root.join(b.allocator, &.{"cppcheck"}) catch @panic("OOM");
    cppcheck_run.addArg("--inline-suppr");
    cppcheck_run.addPrefixedFileArg("--project=", config.cdb_gen.getCdbPath());
    const cppcheck_cache = cppcheck_run.addPrefixedOutputDirectoryArg(
        "--cppcheck-build-dir=",
        installed_cppcheck_cache_path,
    );
    cppcheck_run.addArg("--check-level=exhaustive");
    cppcheck_run.addArgs(&.{ "--error-exitcode=1", "--enable=all" });
    cppcheck_run.addArgs(&.{
        "--suppress=*:magic_enum.hpp",
        "--suppress=*:.zig-cache/*",
    });

    if (config.extra_suppress_patterns) |extra_suppress_patterns| {
        cppcheck_run.addArgs(extra_suppress_patterns);
    }

    if (config.suppressions) |suppressions| for (suppressions) |suppression| {
        cppcheck_run.addArg(b.fmt("--suppress={s}", .{suppression}));
    };

    if (config.ignore_paths) |ignore_paths| for (ignore_paths) |ignore_path| {
        cppcheck_run.addPrefixedDirectoryArg("-i", ignore_path);
    };

    const cppcheck_cache_install = b.addInstallDirectory(.{
        .source_dir = cppcheck_cache,
        .install_dir = .{ .custom = ".." },
        .install_subdir = installed_cppcheck_cache_path,
    });

    cppcheck_cache_install.step.dependOn(&config.cppcheck.step);
    check_step.dependOn(&cppcheck_cache_install.step);
    check_step.dependOn(&cppcheck_run.step);
    return check_step;
}

pub const RunKcovConfig = struct {
    include_patterns: ?[]const []const u8 = null,
    exclude_patterns: ?[]const []const u8 = null,
    artifact: *std.Build.Step.Compile,
};

pub const RunKcovReport = struct {
    runner: *std.Build.Step.Run,
    output_dir: std.Build.LazyPath,
    generated_dirname: []const u8,
};

/// Runs kcov with the given configuration, returning the generated command and directory.
///
/// Can only error on macos if the `codesign` tool is not found.
fn runKcov(
    b: *std.Build,
    kcov: *std.Build.Step.Compile,
    config: RunKcovConfig,
) !RunKcovReport {
    var signer: ?*std.Build.Step.Run = null;
    if (b.graph.host.result.os.tag.isDarwin()) {
        const entitlements = b.addWriteFile("osx-entitlements.xml",
            \\<?xml version="1.0" encoding="UTF-8"?>
            \\<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            \\<plist version="1.0">
            \\<dict>
            \\    <key>com.apple.security.cs.debugger</key>
            \\    <true/>
            \\</dict>
            \\</plist>
        );

        const codesign = b.findProgram(&.{"codesign"}, &.{"usr"}) catch return error.CodesignNotFound;
        const run = b.addSystemCommand(&.{codesign});
        run.addArgs(&.{ "-s", "-", "--entitlements" });
        run.addFileArg(entitlements.getDirectory().path(b, "osx-entitlements.xml"));
        run.addArg("-f");
        run.addArtifactArg(kcov);

        _ = run.captureStdOut(.{});
        _ = run.captureStdErr(.{});
        signer = run;
    }

    const run = b.addRunArtifact(kcov);
    if (signer) |s| run.step.dependOn(&s.step);
    run.has_side_effects = true;
    if (config.include_patterns) |include_patterns| {
        const includes = std.mem.join(b.allocator, ",", include_patterns) catch @panic("OOM");
        run.addArg(b.fmt("--include-pattern={s}", .{includes}));
    }

    if (config.exclude_patterns) |exclude_patterns| {
        const excludes = std.mem.join(b.allocator, ",", exclude_patterns) catch @panic("OOM");
        run.addArg(b.fmt("--exclude-pattern={s}", .{excludes}));
    }

    const gendir = b.fmt("kcov-{s}", .{config.artifact.name});
    const output = run.addOutputDirectoryArg(gendir);
    run.addArtifactArg(config.artifact);
    return .{
        .runner = run,
        .output_dir = output,
        .generated_dirname = gendir,
    };
}

const MergeKcovResult = struct {
    runner: *std.Build.Step.Run,
    output_dir: std.Build.LazyPath,
};

fn mergeKcovReports(
    b: *std.Build,
    kcov: *std.Build.Step.Compile,
    reports: []const RunKcovReport,
) MergeKcovResult {
    const run = b.addRunArtifact(kcov);
    run.addArg("--merge");
    const output = run.addOutputDirectoryArg("kcov-merged");
    for (reports) |report| {
        run.addDirectoryArg(report.output_dir);
    }

    return .{ .runner = run, .output_dir = output };
}

pub const CoverageConfig = struct {
    kcov: *std.Build.Step.Compile,
    curl: *std.Build.Step.Compile,
    run_configs: []const RunKcovConfig,
};

/// Adds coverage reporting on supported platforms for all test artifacts
pub fn addCoverage(b: *std.Build, config: CoverageConfig) !void {
    var reports: ArrayList(RunKcovReport) = .init(b);
    for (config.run_configs) |run_config| {
        reports.append(try runKcov(b, config.kcov, run_config));
    }

    const coverage = b.step("coverage", "Generate coverage report");
    for (reports.wrapped.items) |report| {
        coverage.dependOn(&report.runner.step);
    }
    const merged = mergeKcovReports(b, config.kcov, reports.wrapped.items);

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

    const curl = b.addRunArtifact(config.curl);
    curl.addArg("-o");
    const badge_file = curl.addOutputFileArg("coverage.svg");
    const install = b.addInstallFile(badge_file, "coverage.svg");
    curl.has_side_effects = true;

    const parser: *CoverageParser = .init(b, merged.output_dir, curl);
    parser.step.dependOn(&merged.runner.step);
    curl.step.dependOn(&parser.step);
    coverage.dependOn(&curl.step);
    coverage.dependOn(&install.step);
}
