const std = @import("std");
const builtin = @import("builtin");
const zon = @import("build.zig.zon");

pub const CDBGenerator = @import("build/CDBGenerator.zig");
pub const RemoveDir = @import("build/RemoveDir.zig");
pub const LOCCounter = @import("build/LOCCounter.zig");
pub const CoverageParser = @import("build/CoverageParser.zig");
const ProjectPaths = @import("build/ProjectPaths.zig");

pub const Dependency = @import("third-party/Dependency.zig");
pub const KcovBuilder = @import("third-party/kcov/KcovBuilder.zig");

pub const utils = @import("build/utils.zig");
pub const builders = @import("build/builders.zig");
pub const cppcheck = @import("third-party/cppcheck.zig");
pub const fmt = @import("third-party/fmt.zig");
pub const catch2 = @import("third-party/catch2.zig");
pub const zlib = @import("third-party/zlib.zig");
pub const zstd = @import("third-party/zstd.zig");
pub const libarchive = @import("third-party/libarchive.zig");

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const building_for_dep = b.option(bool, "building_for_dep", "Build for a dependency") orelse false;
    const run_cdb_gen = b.option(bool, "run_cdb_gen", "Run cdb generation") orelse true;

    const cdb_gen_opt: ?*CDBGenerator = if (run_cdb_gen) CDBGenerator.init(b) else null;
    var compiler_flags: std.ArrayList([]const u8) = .empty;
    try compiler_flags.appendSlice(b.allocator, &utils.base_cxx_flags);
    try compiler_flags.append(b.allocator, "-DMAGIC_ENUM_RANGE_MAX=255");
    const dist_flags: []const []const u8 = &.{ "-DNDEBUG", "-DSTDX_DIST" };

    if (b.option(bool, "profile", "Enable chromium tracing") orelse false) {
        try compiler_flags.append(b.allocator, "-DSTDX_PROFILE");
    }

    if (run_cdb_gen) try compiler_flags.appendSlice(b.allocator, &.{
        "-gen-cdb-fragment-path",
        b.cache_root.join(b.allocator, &.{CDBGenerator.cdb_frags_dirname}) catch @panic("OOM"),
    });

    switch (optimize) {
        .Debug => try compiler_flags.appendSlice(b.allocator, &.{ "-g", "-DSTDX_DEBUG" }),
        .ReleaseSafe => try compiler_flags.appendSlice(b.allocator, &.{"-DSTDX_RELEASE"}),
        .ReleaseFast, .ReleaseSmall => try compiler_flags.appendSlice(b.allocator, dist_flags),
    }

    const install_tests_only = b.option(
        bool,
        "install-tests-only",
        "Install tests without running them (default: false)",
    ) orelse false;

    var cdb_steps: std.ArrayList(*std.Build.Step) = .empty;
    const artifacts = try addArtifacts(b, .{
        .target = target,
        .optimize = optimize,
        .cxx_flags = compiler_flags.items,
        .cdb_steps = if (run_cdb_gen) &cdb_steps else null,
        .install_tests_only = install_tests_only,
        .building_for_dep = building_for_dep,
    });

    if (cdb_gen_opt) |cdb_gen| {
        for (cdb_steps.items) |cdb_step| cdb_gen.step.dependOn(cdb_step);
    }

    if (!building_for_dep) {
        const cppcheck_dep = try cppcheck.build(b, .{
            .target = b.graph.host,
            .optimize = .ReleaseFast,
        });

        try addTooling(b, .{
            .cdb_gen = cdb_gen_opt,
            .cppcheck = cppcheck_dep.artifact,
        });

        if (artifacts.tests) |tests| try CoverageParser.addStep(b, &[_]KcovBuilder.RunKcovConfig{
            .{
                .artifact = tests.harness_tests,
                .include_patterns = &.{ProjectPaths.harness},
            },
            .{
                .artifact = tests.stdx_tests,
                .include_patterns = &.{
                    try b.build_root.join(b.allocator, &.{ProjectPaths.src}),
                    try b.build_root.join(b.allocator, &.{ProjectPaths.include}),
                },
            },
        });
    }
}

const TestArtifacts = struct {
    harness_tests: *std.Build.Step.Compile = undefined,
    stdx_tests: *std.Build.Step.Compile = undefined,

    pub fn configure(
        self: *const TestArtifacts,
        b: *std.Build,
        cdb_steps: ?*std.ArrayList(*std.Build.Step),
        install_dir: ?[]const u8,
        install_only: bool,
    ) !void {
        if (cdb_steps) |cdb| {
            try cdb.append(b.allocator, &self.stdx_tests.step);
        }

        const artifacts = [_]*std.Build.Step.Compile{
            self.harness_tests,
            self.stdx_tests,
        };

        const test_step = b.step("test", "Run all unit tests");
        for (artifacts) |artifact| {
            _ = utils.ExecutableBehavior.installArtifact(
                b,
                artifact,
                test_step,
                install_dir,
                install_only,
            );
        }
    }
};

const version_str = zon.version;
const version = std.SemanticVersion.parse(version_str) catch @compileError("Malformed version");

fn buildStdx(b: *std.Build, config: struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    cxx_flags: []const []const u8,
}) !*std.Build.Step.Compile {
    const target = config.target;
    const config_h = b.addConfigHeader(.{ .include_path = "stdx/config.h" }, .{
        .STDX_VERSION_STR = version_str,
        .STDX_VERSION_MAJOR = @as(i64, version.major),
        .STDX_VERSION_MINOR = @as(i64, version.minor),
        .STDX_VERSION_PATCH = @as(i64, version.patch),
        .STDX_VERSION_PRE = version.pre orelse "",
        .STDX_WINDOWS = target.result.os.tag == .windows,
        .STDX_LINUX = target.result.os.tag == .linux,
        .STDX_APPLE = target.result.os.tag == .macos,
    });

    const magic_enum = b.dependency("magic_enum", .{});
    const magic_enum_inc = magic_enum.path("include");

    const unordered_dense = b.dependency("unordered_dense", .{});
    const unordered_dense_inc = unordered_dense.path("include");

    const gsl = b.dependency("gsl", .{});
    const gsl_inc = gsl.path("include");

    const system_includes = [_]std.Build.LazyPath{
        magic_enum_inc,
        unordered_dense_inc,
        gsl_inc,
    };

    const fmt_dep = fmt.build(b, .{
        .target = target,
        .optimize = config.optimize,
    });

    // Shared core functionality
    const libstdx = b.addLibrary(.{
        .name = "stdx",
        .root_module = utils.createModule(b, .{
            .target = target,
            .optimize = config.optimize,
            .include_paths = &.{b.path(ProjectPaths.include)},
            .system_include_paths = &system_includes,
            .cxx = .{
                .files = try utils.collectFiles(b, ProjectPaths.src, .{}),
                .flags = config.cxx_flags,
            },
            .config_headers = &.{config_h},
            .link_libraries = &.{fmt_dep.artifact},
        }),
    });

    libstdx.installConfigHeader(config_h);
    for (system_includes) |system_include| {
        libstdx.installHeadersDirectory(system_include, "", .{
            .include_extensions = null,
            .exclude_extensions = &.{".txt"},
        });
    }
    libstdx.installLibraryHeaders(fmt_dep.artifact);
    libstdx.installHeadersDirectory(b.path(ProjectPaths.include), "", .{
        .include_extensions = &.{".hh"},
    });

    return libstdx;
}

fn addArtifacts(b: *std.Build, config: struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    cxx_flags: []const []const u8,
    cdb_steps: ?*std.ArrayList(*std.Build.Step),
    behavior: ?utils.ExecutableBehavior = null,
    auto_install: bool = true,
    install_tests_only: bool = true,
    building_for_dep: bool = true,
}) !struct {
    libstdx: *std.Build.Step.Compile,
    tests: ?TestArtifacts,
} {
    const libstdx = try buildStdx(b, .{
        .optimize = config.optimize,
        .target = config.target,
        .cxx_flags = config.cxx_flags,
    });

    if (config.auto_install) b.installArtifact(libstdx);
    if (config.cdb_steps) |cdb_steps| try cdb_steps.append(b.allocator, &libstdx.step);

    var tests: ?TestArtifacts = null;
    if (!config.building_for_dep) {
        const test_install_dir: ?[]const u8 = if (config.auto_install) "tests" else null;

        // The test harness has standalone tests of its own
        const harness_tests = b.addTest(.{
            .name = "harness",
            .root_module = b.createModule(.{
                .root_source_file = b.path(ProjectPaths.harness ++ "main.zig"),
                .optimize = config.optimize,
                .target = config.target,
                .link_libc = true,
            }),
        });

        const harness_step = b.step("test-harness", "Build/run test harness' tests");
        _ = utils.ExecutableBehavior.installArtifact(
            b,
            harness_tests,
            harness_step,
            test_install_dir,
            config.install_tests_only,
        );

        const stdx_tests = builders.strappedTest(b, .{
            .target = config.target,
            .optimize = config.optimize,
            .libstdx = libstdx,
            .cxx_files = try utils.collectFiles(b, ProjectPaths.tests, .{}),
            .cxx_flags = config.cxx_flags,
            .include_paths = &.{
                b.path(ProjectPaths.include),
                b.path(ProjectPaths.tests),
            },
            .executable_config = .{
                .name = "stdx",
                .behavior = config.behavior orelse .{
                    .installable = .{
                        .cmd_name = "test-stdx",
                        .cmd_desc = "Build/run stdx's unit tests",
                        .install_dir = test_install_dir,
                        .install_only = config.install_tests_only,
                    },
                },
            },
        });

        tests = .{
            .harness_tests = harness_tests,
            .stdx_tests = stdx_tests,
        };
        try tests.?.configure(b, config.cdb_steps, test_install_dir, config.install_tests_only);
    }

    return .{ .libstdx = libstdx, .tests = tests };
}

fn addTooling(b: *std.Build, config: struct {
    cdb_gen: ?*CDBGenerator,
    cppcheck: *std.Build.Step.Compile,
}) !void {
    const tooling_sources = try ProjectPaths.collectCXXToolingFiles(b);
    try addFmtStep(b, tooling_sources);

    if (config.cdb_gen) |cdb_gen| {
        const cdb_step = b.step("cdb", "Generate " ++ CDBGenerator.cdb_filename);
        cdb_step.dependOn(&cdb_gen.step);
        b.getInstallStep().dependOn(&cdb_gen.step);

        const check_step = utils.addStaticAnalysisStep(b, .{
            .tooling_sources = tooling_sources,
            .cppcheck = config.cppcheck,
            .cdb_gen = cdb_gen,
        });
        check_step.dependOn(&cdb_gen.step);
    }

    const counted_extensions = [_][]const u8{ ".cc", ".hh", ".zig" };
    const counted_files = try std.mem.concat(b.allocator, []const u8, &.{
        try utils.collectFiles(b, "build", .{
            .allowed_extensions = &counted_extensions,
            .extra_files = &.{"build.zig"},
        }),
        try utils.collectFiles(b, "include", .{ .allowed_extensions = &counted_extensions }),
        try utils.collectFiles(b, "src", .{ .allowed_extensions = &counted_extensions }),
        try utils.collectFiles(b, "tests", .{ .allowed_extensions = &counted_extensions }),
    });

    const cloc: *LOCCounter = .init(b, counted_files);
    const cloc_step = b.step("cloc", "Count lines of code across the project");
    cloc_step.dependOn(&cloc.step);
}

fn addFmtStep(b: *std.Build, tooling_sources: []const []const u8) !void {
    const zig_paths = try std.mem.concat(b.allocator, []const u8, &.{
        try utils.collectFiles(b, "build", .{
            .allowed_extensions = &.{".zig"},
            .extra_files = &.{
                "build.zig",
                "build.zig.zon",
            },
        }),
        try utils.collectFiles(b, "tools", .{ .allowed_extensions = &.{".zig"} }),
    });
    const build_fmt = b.addFmt(.{ .paths = zig_paths });
    const build_fmt_check = b.addFmt(.{ .paths = zig_paths, .check = true });

    const clang_format_version = "21.1.8";
    const clang_format_path = b.findProgram(&.{"clang-format"}, &.{}) catch return;
    if (!std.mem.containsAtLeast(u8, b.run(&.{ clang_format_path, "--version" }), 1, clang_format_version)) {
        std.log.err("Skipping clang-format as v{s} is required but could not be found", .{clang_format_version});
        return;
    }

    const formatter = b.addSystemCommand(&.{clang_format_path});
    formatter.addArg("-i");
    formatter.addArgs(tooling_sources);
    const fmt_step = b.step("fmt", "Format all project files");
    fmt_step.dependOn(&formatter.step);
    fmt_step.dependOn(&build_fmt.step);

    const fmt_check = b.addSystemCommand(&.{clang_format_path});
    fmt_check.addArgs(&.{ "--dry-run", "--Werror" });
    fmt_check.addArgs(tooling_sources);
    const fmt_check_step = b.step("fmt-check", "Check formatting of all project files");
    fmt_check_step.dependOn(&fmt_check.step);
    fmt_check_step.dependOn(&build_fmt_check.step);
}
