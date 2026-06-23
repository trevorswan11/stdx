const std = @import("std");

const CDBGenerator = @import("CDBGenerator.zig");
const ArrayList = @import("array_list.zig").ArrayList;

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

pub const CollectFilesConfig = struct {
    allowed_extensions: []const []const u8 = &.{".cc"},
    dropped_files: ?[]const []const u8 = null,
    extra_files: ?[]const []const u8 = null,
    return_basenames_only: bool = false,
    dropped_extensions: ?[]const []const u8 = null,
    dropped_path_prefixes: ?[]const []const u8 = null,
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

        if (config.dropped_path_prefixes) |prefixes| for (prefixes) |prefix| {
            if (std.mem.startsWith(u8, entry.path, prefix)) continue :outer;
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

/// Appends all collected files into the passed list
pub fn collectFilesInto(
    b: *std.Build,
    directory: []const u8,
    config: CollectFilesConfig,
    buf: *ArrayList([]const u8),
) !void {
    buf.appendSlice(try collectFiles(b, directory, config));
}

pub fn tryAppendExe(
    allocator: std.mem.Allocator,
    target: std.Build.ResolvedTarget,
    raw_path: []const u8,
) []const u8 {
    if (target.result.os.tag == .windows) {
        return std.fmt.allocPrint(allocator, "{s}.exe", .{raw_path}) catch @panic("OOM");
    }
    return allocator.dupe(u8, raw_path) catch @panic("OOM");
}
