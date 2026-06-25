const std = @import("std");
const builtin = @import("builtin");
const zon = @import("build.zig.zon");

pub const CDBGenerator = @import("build/CDBGenerator.zig");
pub const RemoveDir = @import("build/RemoveDir.zig");
pub const LOCCounter = @import("build/LOCCounter.zig");
pub const CoverageParser = @import("build/CoverageParser.zig");
pub const Packager = @import("build/Packager.zig");
pub const ArrayList = @import("build/array_list.zig").ArrayList;
const ProjectPaths = @import("build/ProjectPaths.zig");

pub const Dependency = @import("third-party/Dependency.zig");
pub const KcovBuilder = @import("third-party/kcov/KcovBuilder.zig");
pub const GTestBuilder = @import("third-party/fuzztest/GTestBuilder.zig");
pub const AbseilBuilder = @import("third-party/abseil/AbseilBuilder.zig");
pub const FuzztestBuilder = @import("third-party/fuzztest/FuzztestBuilder.zig");

pub const utils = @import("build/utils.zig");
pub const builders = @import("build/builders.zig");
pub const steps = @import("build/steps.zig");
pub const cppcheck = @import("third-party/cppcheck.zig");
pub const fmt = @import("third-party/fmt.zig");
pub const catch2 = @import("third-party/catch2.zig");
pub const zlib = @import("third-party/zlib.zig");
pub const zstd = @import("third-party/zstd.zig");
pub const spdlog = @import("third-party/spdlog.zig");
pub const libarchive = @import("third-party/libarchive.zig");
pub const re2 = @import("third-party/fuzztest/re2.zig");

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const building_for_dep = b.option(bool, "building_for_dep", "Build for a dependency") orelse false;
    const run_cdb_gen = b.option(bool, "run_cdb_gen", "Run cdb generation") orelse true;
    const packaging = b.option(bool, "packaging", "Don't compile catch2 or cppcheck") orelse false;

    const cdb_gen_opt: ?*CDBGenerator = if (run_cdb_gen) CDBGenerator.init(b) else null;
    var compiler_flags: ArrayList([]const u8) = .init(b);
    compiler_flags.appendSlice(&utils.base_cxx_flags);
    compiler_flags.append("-DMAGIC_ENUM_RANGE_MAX=255");
    const dist_flags: []const []const u8 = &.{ "-DNDEBUG", "-DSTDX_DIST" };

    const profile = b.option(bool, "profile", "Enable chromium tracing") orelse false;
    if (profile) compiler_flags.append(builders.stdx_profile_define);
    if (run_cdb_gen) CDBGenerator.addCdbFlags(b, &compiler_flags.wrapped);

    switch (optimize) {
        .Debug => compiler_flags.appendSlice(&.{ "-g", "-DSTDX_DEBUG" }),
        .ReleaseSafe => compiler_flags.appendSlice(&.{"-DSTDX_RELEASE"}),
        .ReleaseFast, .ReleaseSmall => compiler_flags.appendSlice(dist_flags),
    }

    const install_tests_only = b.option(
        bool,
        "install-tests-only",
        "Install tests without running them (default: false)",
    ) orelse false;

    var cdb_steps: ArrayList(*std.Build.Step) = .init(b);
    const artifacts = try addArtifacts(b, .{
        .target = target,
        .optimize = optimize,
        .cxx_flags = compiler_flags.wrapped.items,
        .cdb_steps = if (run_cdb_gen) &cdb_steps else null,
        .install_tests_only = install_tests_only,
        .building_for_dep = building_for_dep,
        .packaging = packaging,
        .profile = profile,
    });

    if (cdb_gen_opt) |cdb_gen| {
        for (cdb_steps.wrapped.items) |cdb_step| cdb_gen.step.dependOn(cdb_step);
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

const FuzztestArtifacts = struct {
    abseil: *AbseilBuilder,
    gtest_builder: *GTestBuilder,
    re2_dep: Dependency,
    fuzztest_builder: ?*FuzztestBuilder,
};

/// Installs fuzztest and dependents
fn installFuzztest(b: *std.Build, config: Dependency.Config) FuzztestArtifacts {
    const gtest = GTestBuilder.build(b, config);
    b.installArtifact(gtest.gtest);
    b.installArtifact(gtest.gtest_main);
    b.installArtifact(gtest.gmock);

    const abseil = AbseilBuilder.init(b, config);
    abseil.build();
    const groups = .{
        abseil.base,      abseil.numeric,   abseil.strings,
        abseil.time,      abseil.debugging, abseil.synchronization,
        abseil.profiling, abseil.hash,      abseil.crc,
        abseil.container, abseil.status,    abseil.log,
        abseil.flags,     abseil.random,
    };
    inline for (groups) |group| {
        inline for (std.meta.fields(@TypeOf(group))) |field| {
            b.installArtifact(@field(group, field.name));
        }
    }

    const re2_dep = re2.build(b, abseil);
    b.installArtifact(re2_dep.artifact);

    var artifacts: FuzztestArtifacts = .{
        .abseil = abseil,
        .gtest_builder = gtest,
        .re2_dep = re2_dep,
        .fuzztest_builder = null,
    };

    if (FuzztestBuilder.canFuzz(config.target)) {
        const fuzztest: *FuzztestBuilder = .build(b, abseil, gtest, re2_dep);
        b.installArtifact(fuzztest.fuzztest);
        artifacts.fuzztest_builder = fuzztest;
    }
    return artifacts;
}

const TestArtifacts = struct {
    const FuzzTests = struct {
        sample: *std.Build.Step.Compile,
    };

    harness_tests: *std.Build.Step.Compile = undefined,
    stdx_tests: *std.Build.Step.Compile = undefined,
    fuzz_tests: ?FuzzTests,

    pub fn configure(
        self: *const TestArtifacts,
        b: *std.Build,
        config: struct {
            cdb_steps: ?*ArrayList(*std.Build.Step),
            test_install_dir: ?[]const u8 = "tests",
            fuzz_install_dir: ?[]const u8 = "fuzz",
            install_only: bool,
        },
    ) !void {
        if (config.cdb_steps) |cdb| {
            cdb.append(&self.stdx_tests.step);
            if (self.fuzz_tests) |fuzz_tests| {
                cdb.append(&fuzz_tests.sample.step);
            }
        }

        const test_artifacts = [_]*std.Build.Step.Compile{
            self.harness_tests,
            self.stdx_tests,
        };

        const test_step = b.step("test", "Run all unit tests");
        for (test_artifacts) |artifact| {
            _ = utils.ExecutableBehavior.installArtifact(
                b,
                artifact,
                test_step,
                config.test_install_dir,
                config.install_only,
            );
        }

        if (self.fuzz_tests) |fuzz_tests| {
            const fuzz_artifacts = [_]*std.Build.Step.Compile{
                fuzz_tests.sample,
            };

            const fuzz_step = b.step("fuzz", "Run all fuzz tests");
            for (fuzz_artifacts) |artifact| {
                _ = utils.ExecutableBehavior.installArtifact(
                    b,
                    artifact,
                    fuzz_step,
                    config.fuzz_install_dir,
                    config.install_only,
                );
            }
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

    const nlohmann_json = b.dependency("nlohmann_json", .{});
    const nlohmann_json_inc = nlohmann_json.path("single_include");

    const system_includes = [_]std.Build.LazyPath{
        magic_enum_inc, unordered_dense_inc,
        gsl_inc,        nlohmann_json_inc,
    };

    const dep_config: Dependency.Config = .{
        .target = target,
        .optimize = config.optimize,
    };

    const dependecies = [_]Dependency{
        fmt.build(b, dep_config),
        spdlog.build(b, dep_config),
    };

    var link_libraries: ArrayList(*std.Build.Step.Compile) = .init(b);
    for (dependecies) |dep| {
        b.installArtifact(dep.artifact);
        link_libraries.append(dep.artifact);
    }

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
            .link_libraries = link_libraries.wrapped.items,
        }),
    });
    for (dependecies) |dep| libstdx.installLibraryHeaders(dep.artifact);

    libstdx.installConfigHeader(config_h);
    for (system_includes) |system_include| {
        libstdx.installHeadersDirectory(system_include, "", .{
            .include_extensions = null,
            .exclude_extensions = &.{".txt"},
        });
    }
    libstdx.installHeadersDirectory(b.path(ProjectPaths.include), "", .{
        .include_extensions = &.{".hh"},
    });

    return libstdx;
}

fn addArtifacts(b: *std.Build, config: struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    cxx_flags: []const []const u8,
    cdb_steps: ?*ArrayList(*std.Build.Step),
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
    if (config.cdb_steps) |cdb_steps| cdb_steps.append(&libstdx.step);

    var catch2_dep: ?Dependency = null;
    if (!config.packaging) {
        catch2_dep = catch2.build(b, .{
            .target = config.target,
            .optimize = config.optimize,
        });
        b.installArtifact(catch2_dep.?.artifact);
    }

    const fuzztest_artifacts = installFuzztest(b, .{
        .target = config.target,
        .optimize = config.optimize,
    });

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
        .stdx = .{
            .internal = .{
                .stdx_builder = b,
                .libstdx = libstdx,
                .libcatch2 = catch2_dep.?.artifact,
            },
        },
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

    var sample_fuzz_test: ?*std.Build.Step.Compile = null;
    if (fuzztest_artifacts.fuzztest_builder) |fuzztest_builder| {
        sample_fuzz_test = builders.fuzzTest(b, .{
            .target = config.target,
            .optimize = config.optimize,
            .stdx = .{
                .internal = .{
                    .stdx_builder = b,
                    .libstdx = libstdx,
                    .libfuzztest = fuzztest_builder.fuzztest,
                    .libgtest = fuzztest_artifacts.gtest_builder.gtest,
                },
            },
            .cxx_files = &.{ProjectPaths.fuzz_tests ++ "sample.cc"},
            .cxx_flags = config.cxx_flags,
            .profile = config.profile,
            .include_paths = &.{b.path(ProjectPaths.include)},
            .executable_config = .{
                .name = "sample",
                .behavior = config.behavior orelse .{
                    .installable = .{
                        .cmd_name = "fuzz-sample",
                        .cmd_desc = "Run the sample fuzz test",
                        .install_dir = "fuzz",
                        .install_only = config.install_tests_only,
                    },
                },
            },
        });
    }

    const tests: TestArtifacts = .{
        .harness_tests = harness_tests,
        .stdx_tests = stdx_tests,
        .fuzz_tests = if (sample_fuzz_test) |sample| .{
            .sample = sample,
        } else null,
    };
    try tests.configure(b, .{
        .cdb_steps = config.cdb_steps,
        .install_only = config.install_tests_only,
    });

    return .{ .libstdx = libstdx, .tests = tests };
}

fn addTooling(b: *std.Build, config: struct {
    cdb_gen: ?*CDBGenerator,
    cppcheck: ?*std.Build.Step.Compile,
}) !void {
    const paths = try ProjectPaths.collectToolingPaths(b);
    _ = steps.addFmt(b, .{
        .paths = paths,
        .formatter = .{ .version = "21.1.8" },
    }) catch {};

    if (config.cdb_gen) |cdb_gen| {
        if (config.cppcheck) |cppcheck_art| {
            const check_step = steps.addCppcheck(b, .{
                .cppcheck = cppcheck_art,
                .cdb_gen = cdb_gen,
            });
            check_step.dependOn(&cdb_gen.step);
        }
    }

    var counted_files: ArrayList([]const u8) = .init(b);
    counted_files.appendSlice(paths.zig);
    counted_files.appendSlice(paths.cxx);
    _ = LOCCounter.init(b, counted_files.wrapped.items);
}
