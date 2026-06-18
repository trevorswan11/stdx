const std = @import("std");
const builtin = @import("builtin");
const zon = @import("build.zig.zon");

pub const CDBGenerator = @import("build/CDBGenerator.zig");
pub const RemoveDir = @import("build/RemoveDir.zig");
pub const LOCCounter = @import("build/LOCCounter.zig");
pub const CoverageParser = @import("build/CoverageParser.zig");
pub const Packager = @import("build/Packager.zig");
const ProjectPaths = @import("build/ProjectPaths.zig");

pub const Dependency = @import("third-party/Dependency.zig");
pub const KcovBuilder = @import("third-party/kcov/KcovBuilder.zig");

pub const utils = @import("build/utils.zig");
pub const builders = @import("build/builders.zig");
pub const steps = @import("build/steps.zig");
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
    const packaging = b.option(bool, "packaging", "Don't compile catch2 or cppcheck") orelse false;

    const cdb_gen_opt: ?*CDBGenerator = if (run_cdb_gen) CDBGenerator.init(b) else null;
    var compiler_flags: std.ArrayList([]const u8) = .empty;
    try compiler_flags.appendSlice(b.allocator, &utils.base_cxx_flags);
    try compiler_flags.append(b.allocator, "-DMAGIC_ENUM_RANGE_MAX=255");
    const dist_flags: []const []const u8 = &.{ "-DNDEBUG", "-DSTDX_DIST" };

    const profile = b.option(bool, "profile", "Enable chromium tracing") orelse false;
    if (profile) try compiler_flags.append(b.allocator, builders.stdx_profile_define);

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
        .packaging = packaging,
        .profile = profile,
    });

    if (cdb_gen_opt) |cdb_gen| {
        for (cdb_steps.items) |cdb_step| cdb_gen.step.dependOn(cdb_step);
    }

    const kcov_builder = KcovBuilder.build(b, .{
        .target = target,
        .optimize = .ReleaseFast,
    });

    if (kcov_builder) |kcov| {
        b.installArtifact(kcov.curl.execurl);
        b.installArtifact(kcov.kcov_exe);
    }

    var cppcheck_art: ?*std.Build.Step.Compile = null;
    if (!packaging) {
        // It never makes sense to build cppcheck for a package build
        const cppcheck_dep = try cppcheck.build(b, .{
            .target = b.graph.host,
            .optimize = .ReleaseFast,
        });

        cppcheck_art = cppcheck_dep.artifact;
        b.installArtifact(cppcheck_art.?);
    }

    // Always build compressor so it's accessible to the outside world
    const compressor = builders.compressor(b);
    b.installArtifact(compressor);

    if (!building_for_dep) {
        try addTooling(b, .{
            .cdb_gen = cdb_gen_opt,
            .cppcheck = cppcheck_art,
        });

        if (artifacts.tests) |tests| if (kcov_builder) |kcov| try steps.addCoverage(b, .{
            .curl = kcov.curl.execurl,
            .kcov = kcov.kcov_exe,
            .run_configs = &.{
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
    install_tests_only: bool = true,
    building_for_dep: bool = true,
    packaging: bool = false,
    profile: bool,
}) !struct {
    libstdx: *std.Build.Step.Compile,
    tests: ?TestArtifacts,
} {
    const libstdx = try buildStdx(b, .{
        .optimize = config.optimize,
        .target = config.target,
        .cxx_flags = config.cxx_flags,
    });
    b.installArtifact(libstdx);
    if (config.cdb_steps) |cdb_steps| try cdb_steps.append(b.allocator, &libstdx.step);

    var catch2_dep: ?Dependency = null;
    if (!config.packaging) {
        catch2_dep = catch2.build(b, .{
            .target = config.target,
            .optimize = config.optimize,
        });
        b.installArtifact(catch2_dep.?.artifact);
    }

    if (config.building_for_dep or catch2_dep == null) {
        return .{ .libstdx = libstdx, .tests = null };
    }

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
        "tests",
        config.install_tests_only,
    );

    const stdx_tests = builders.strappedTest(b, .{
        .target = config.target,
        .optimize = config.optimize,
        .libstdx = libstdx,
        .libcatch2 = catch2_dep.?.artifact,
        .cxx_files = try utils.collectFiles(b, ProjectPaths.tests, .{}),
        .cxx_flags = config.cxx_flags,
        .profile = config.profile,
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
                    .install_dir = "tests",
                    .install_only = config.install_tests_only,
                },
            },
        },
    });

    const tests: TestArtifacts = .{
        .harness_tests = harness_tests,
        .stdx_tests = stdx_tests,
    };
    try tests.configure(b, config.cdb_steps, "tests", config.install_tests_only);

    return .{ .libstdx = libstdx, .tests = tests };
}

fn addTooling(b: *std.Build, config: struct {
    cdb_gen: ?*CDBGenerator,
    cppcheck: ?*std.Build.Step.Compile,
}) !void {
    _ = steps.addFmt(b, .{
        .paths = try ProjectPaths.collectToolingPaths(b),
        .formatter = .{ .version = "21.1.8" },
    }) catch {};

    if (config.cdb_gen) |cdb_gen| {
        const cdb_step = b.step("cdb", "Generate " ++ CDBGenerator.cdb_filename);
        cdb_step.dependOn(&cdb_gen.step);
        b.getInstallStep().dependOn(&cdb_gen.step);

        if (config.cppcheck) |cppcheck_art| {
            const check_step = steps.addCppcheck(b, .{
                .cppcheck = cppcheck_art,
                .cdb_gen = cdb_gen,
            });
            check_step.dependOn(&cdb_gen.step);
        }
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
