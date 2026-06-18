const std = @import("std");

const CDBGenerator = @import("CDBGenerator.zig");
const ProjectPaths = @import("ProjectPaths.zig");

const catch2 = @import("../third-party/catch2.zig");
const libarchive = @import("../third-party/libarchive.zig");

pub const base_cxx_flags = [_][]const u8{
    "-std=c++23",
    "-Wall",
    "-Wextra",
    "-Werror",
    "-Wpedantic",
    "-Wconversion",
    "-Wshadow",
    "-Wno-gnu-statement-expression",
    "-Wno-gnu-statement-expression-from-macro-expansion",
};

pub const ExecutableBehavior = union(enum) {
    /// Meant for user facing potentially runnable commands
    installable: struct {
        cmd_name: []const u8,
        cmd_desc: []const u8,
        install_dir: ?[]const u8 = null,
        install_only: bool = false,
    },

    /// Meant for internal tools and intermediate artifacts
    standalone: void,

    pub fn installArtifact(
        b: *std.Build,
        artifact: *std.Build.Step.Compile,
        parent_step: *std.Build.Step,
        install_dir: ?[]const u8,
        install_only: bool,
    ) ?*std.Build.Step.Run {
        var runner: ?*std.Build.Step.Run = null;
        if (!install_only) {
            runner = b.addRunArtifact(artifact);
            runner.?.step.dependOn(b.getInstallStep());
            parent_step.dependOn(&runner.?.step);
        }

        if (install_dir) |override| {
            const install = b.addInstallArtifact(artifact, .{
                .dest_dir = .{
                    .override = .{ .custom = override },
                },
            });
            parent_step.dependOn(&install.step);
        }
        return runner;
    }
};

pub fn getGitInfo(b: *std.Build) []const u8 {
    const git_hash = std.mem.trimEnd(u8, b.run(&.{ "git", "rev-parse", "HEAD" }), " \r\n");
    var out_code: u8 = undefined;
    const git_tag_raw = b.runAllowFail(&.{ "git", "describe", "--tags", "--abbrev=0" }, &out_code, .ignore) catch "";
    const git_tag = std.mem.trimEnd(u8, git_tag_raw, " \r\n");
    return b.fmt("git-{s}{s}{s}", .{ git_hash, if (git_tag_raw.len == 0) "" else "-", git_tag });
}

pub const CreateModuleConfig = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    zig_main: ?std.Build.LazyPath = null,
    include_paths: ?[]const std.Build.LazyPath = null,
    system_include_paths: ?[]const std.Build.LazyPath = null,
    config_headers: ?[]const *std.Build.Step.ConfigHeader = null,
    source_root: ?std.Build.LazyPath = null,
    link_libraries: ?[]const *std.Build.Step.Compile = null,
    system_libraries: ?struct {
        search_paths: []const std.Build.LazyPath,
        libs: []const []const u8,
    } = null,
    imports: ?[]const struct {
        name: []const u8,
        module: *std.Build.Module,
    } = null,
    cxx: ?struct {
        files: []const []const u8,
        flags: []const []const u8,
    } = null,
};

pub fn createModule(b: *std.Build, config: CreateModuleConfig) *std.Build.Module {
    const mod = b.createModule(.{
        .root_source_file = config.zig_main,
        .target = config.target,
        .optimize = config.optimize,
        .link_libc = true,
        .link_libcpp = true,
    });

    if (config.include_paths) |include_paths| for (include_paths) |inc_path| {
        mod.addIncludePath(inc_path);
    };

    if (config.system_include_paths) |system_includes| for (system_includes) |inc_path| {
        mod.addSystemIncludePath(inc_path);
    };

    if (config.config_headers) |config_headers| for (config_headers) |header| {
        mod.addConfigHeader(header);
    };

    if (config.link_libraries) |link_libraries| for (link_libraries) |lib| {
        mod.linkLibrary(lib);
    };

    if (config.cxx) |cxx| mod.addCSourceFiles(.{
        .root = config.source_root,
        .files = cxx.files,
        .flags = cxx.flags,
        .language = .cpp,
    });

    if (config.system_libraries) |libs| {
        for (libs.search_paths) |path| {
            mod.addLibraryPath(path);
        }

        for (libs.libs) |lib| {
            mod.linkSystemLibrary(lib, .{
                .preferred_link_mode = .static,
            });
        }
    }

    if (config.imports) |imports| for (imports) |import| {
        mod.addImport(import.name, import.module);
    };

    return mod;
}

pub const CreateExecutableConfig = struct {
    name: []const u8,
    behavior: ExecutableBehavior = .standalone,
};

pub fn createExecutable(
    b: *std.Build,
    module_config: CreateModuleConfig,
    executable_config: CreateExecutableConfig,
) *std.Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = executable_config.name,
        .root_module = createModule(b, module_config),
    });

    switch (executable_config.behavior) {
        .installable => |config| {
            const step = b.step(config.cmd_name, config.cmd_desc);
            if (ExecutableBehavior.installArtifact(
                b,
                exe,
                step,
                config.install_dir,
                config.install_only,
            )) |run| {
                if (b.args) |args| {
                    run.addArgs(args);
                }
            }
        },
        .standalone => {},
    }

    return exe;
}

const BuildStrappedTestConfig = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    libstdx: *std.Build.Step.Compile,
    /// The test hook is added automatically
    cxx_files: []const []const u8,
    cxx_flags: []const []const u8,
    /// Catch2 and libstdx are added automatically
    link_libraries: []const *std.Build.Step.Compile = &.{},
    include_paths: []const std.Build.LazyPath = &.{},
    config_headers: []const *std.Build.Step.ConfigHeader = &.{},
    system_include_paths: []const std.Build.LazyPath = &.{},
    executable_config: CreateExecutableConfig,
    /// The builder who has stdx as a dependency, defaulting to `b`
    asking_builder: ?*std.Build = null,
};

/// Build's a zig-harness-driven catch2 test artifact
///
/// Call this with the dependencies builder
pub fn buildStrappedTest(b: *std.Build, config: BuildStrappedTestConfig) *std.Build.Step.Compile {
    const catch2_dep = catch2.build(b, .{
        .target = config.target,
        .optimize = config.optimize,
    });

    const link_libraries = std.mem.concat(b.allocator, *std.Build.Step.Compile, &.{
        config.link_libraries,
        &.{ config.libstdx, catch2_dep.artifact },
    }) catch @panic("OOM");

    const test_exe = createExecutable(config.asking_builder orelse b, .{
        .target = config.target,
        .optimize = config.optimize,
        .zig_main = b.path(ProjectPaths.harness ++ "main.zig"),
        .include_paths = config.include_paths,
        .config_headers = config.config_headers,
        .system_include_paths = config.system_include_paths,
        .cxx = .{
            .files = config.cxx_files,
            .flags = config.cxx_flags,
        },
        .link_libraries = link_libraries,
    }, config.executable_config);

    test_exe.root_module.addCSourceFile(.{
        .file = b.path(ProjectPaths.harness ++ "runner.cc"),
        .flags = config.cxx_flags,
    });
    return test_exe;
}

pub fn buildCompressor(b: *std.Build) *std.Build.Step.Compile {
    const libarchive_dep = libarchive.build(b, .{
        .target = b.graph.host,
        .optimize = .ReleaseFast,
    });

    const headers = b.addTranslateC(.{
        .root_source_file = b.path(ProjectPaths.compressor ++ "c.h"),
        .target = b.graph.host,
        .optimize = .ReleaseFast,
    });
    headers.addIncludePath(libarchive_dep.artifact.getEmittedIncludeTree());

    const compressor = createExecutable(b, .{
        .zig_main = b.path(ProjectPaths.compressor ++ "main.zig"),
        .target = b.graph.host,
        .optimize = .ReleaseFast,
        .link_libraries = &.{libarchive_dep.artifact},
        .imports = &.{
            .{
                .name = "c",
                .module = headers.createModule(),
            },
        },
    }, .{
        .name = "compressor",
        .behavior = .standalone,
    });

    if (b.graph.host != .macos) return compressor;
    if (b.graph.environ_map.get("SDKROOT")) |sdkroot| {
        const mod = compressor.root_module;
        mod.addFrameworkPath(.{ .cwd_relative = b.fmt("{s}/System/Library/Frameworks", .{sdkroot}) });
        mod.addSystemIncludePath(.{ .cwd_relative = b.fmt("{s}/usr/include", .{sdkroot}) });
    }
    return compressor;
}

pub fn addStaticAnalysisStep(b: *std.Build, config: struct {
    tooling_sources: []const []const u8,
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
    /// Relative to build root
    ignore_paths: ?[]const []const u8 = null,
}) *std.Build.Step {
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
        cppcheck_run.addPrefixedDirectoryArg("-i", b.path(ignore_path));
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

pub const CollectFilesConfig = struct {
    allowed_extensions: []const []const u8 = &.{".cc"},
    dropped_files: ?[]const []const u8 = null,
    extra_files: ?[]const []const u8 = null,
    return_basenames_only: bool = false,
    dropped_extensions: ?[]const []const u8 = null,
};

pub fn collectFiles(
    b: *std.Build,
    directory: []const u8,
    config: CollectFilesConfig,
) ![]const []const u8 {
    const io = b.graph.io;
    var dir = try b.build_root.handle.openDir(io, directory, .{ .iterate = true });
    defer dir.close(io);

    var walker = try dir.walk(b.allocator);
    defer walker.deinit();

    var paths: std.ArrayList([]const u8) = .empty;
    outer: while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        for (config.allowed_extensions) |ext| {
            if (std.mem.endsWith(u8, entry.basename, ext)) break;
        } else continue;

        if (config.dropped_files) |drop| for (drop) |drop_file| {
            if (std.mem.eql(u8, drop_file, entry.basename)) continue;
        };

        if (config.dropped_extensions) |drop| for (drop) |drop_file| {
            if (std.mem.endsWith(u8, entry.basename, drop_file)) continue :outer;
        };

        if (config.return_basenames_only) {
            try paths.append(b.allocator, b.dupe(entry.basename));
        } else {
            const full_path = b.pathJoin(&.{ directory, entry.path });
            try paths.append(b.allocator, full_path);
        }
    }

    if (config.extra_files) |extra_files| {
        try paths.appendSlice(b.allocator, extra_files);
    }
    return paths.items;
}

pub fn tryAppendExe(b: *std.Build, raw_path: []const u8) []const u8 {
    return b.fmt("{s}{s}", .{
        raw_path,
        if (b.graph.host.result.os.tag == .windows) ".exe" else "",
    });
}
