const std = @import("std");

const utils = @import("utils.zig");

const RemoveDir = @import("RemoveDir.zig");

pub const Archive = enum {
    /// Skipped if the platform is not windows
    zip,
    zst,

    pub fn asFileExtension(self: @This()) []const u8 {
        return switch (self) {
            .zip => "zip",
            .zst => "tar.zst",
        };
    }
};

/// Somewhat comprehensive list of target queries, not generally applicable
pub const base_target_queries: []const std.Target.Query = &.{
    .{ .cpu_arch = .x86_64, .os_tag = .macos },
    .{ .cpu_arch = .aarch64, .os_tag = .macos },

    .{ .cpu_arch = .x86, .os_tag = .linux },
    .{ .cpu_arch = .x86_64, .os_tag = .linux },
    .{ .cpu_arch = .aarch64, .os_tag = .linux },
    .{ .cpu_arch = .powerpc, .os_tag = .linux },
    .{ .cpu_arch = .powerpc64, .os_tag = .linux },
    .{ .cpu_arch = .powerpc64le, .os_tag = .linux },
    .{ .cpu_arch = .riscv32, .os_tag = .linux },
    .{ .cpu_arch = .riscv64, .os_tag = .linux },
    .{ .cpu_arch = .loongarch64, .os_tag = .linux },

    .{ .cpu_arch = .x86_64, .os_tag = .freebsd },
    .{ .cpu_arch = .aarch64, .os_tag = .freebsd },
    .{ .cpu_arch = .powerpc64, .os_tag = .freebsd },
    .{ .cpu_arch = .powerpc64le, .os_tag = .freebsd },
    .{ .cpu_arch = .riscv64, .os_tag = .freebsd },

    .{ .cpu_arch = .x86, .os_tag = .netbsd },
    .{ .cpu_arch = .x86_64, .os_tag = .netbsd },
    .{ .cpu_arch = .aarch64, .os_tag = .netbsd },

    .{ .cpu_arch = .x86, .os_tag = .windows },
    .{ .cpu_arch = .x86_64, .os_tag = .windows },
    .{ .cpu_arch = .aarch64, .os_tag = .windows },
};

const Self = @This();

b: *std.Build,
step: *std.Build.Step,
compressor: *std.Build.Step.Compile,
prefix_parent_dirname: []const u8,

pub fn init(b: *std.Build, config: struct {
    compressor: *std.Build.Step.Compile,
    step_name: []const u8 = "package",
    prefix_parent_dirname: []const u8 = "package",
}) *Self {
    const self = b.allocator.create(Self) catch @panic("OOM");
    self.* = .{
        .b = b,
        .step = b.step(config.step_name, "Package artifacts for a new release"),
        .compressor = config.compressor,
        .prefix_parent_dirname = config.prefix_parent_dirname,
    };

    const cleaner: *RemoveDir = .init(b, .{
        .cwd_relative = b.pathJoin(&.{ b.install_prefix, self.prefix_parent_dirname }),
    });
    self.compressor.step.dependOn(&cleaner.step);

    return self;
}

pub const CopyPath = struct {
    source: std.Build.LazyPath,
    /// Local to the enclosing archive directory
    destination: []const u8,
    kind: enum { file, dir } = .file,
};

/// Modifies the output filename to include the version and to be stripped
pub fn configureExe(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    version_str: []const u8,
    artifact: *std.Build.Step.Compile,
) void {
    artifact.out_filename = utils.tryAppendExe(
        b.allocator,
        target,
        b.fmt("{s}-{s}", .{ artifact.name, version_str }),
    );
    artifact.root_module.strip = true;
}

pub fn addArchives(
    self: *Self,
    config: struct {
        target: std.Build.ResolvedTarget,
        archives: []const Archive = &.{ .zip, .zst },
        copy_paths: []const CopyPath,
        /// This should match the inner directory of the staging environment
        output_dir_basename: []const u8,
    },
) void {
    const b = self.b;
    const staging = b.addWriteFiles();
    for (config.copy_paths) |copy| {
        switch (copy.kind) {
            .file => {
                _ = staging.addCopyFile(
                    copy.source,
                    b.fmt("{s}/{s}", .{ config.output_dir_basename, copy.destination }),
                );
            },
            .dir => {
                _ = staging.addCopyDirectory(
                    copy.source,
                    b.fmt("{s}/{s}", .{ config.output_dir_basename, copy.destination }),
                    .{},
                );
            },
        }
    }

    for (config.archives) |archive| {
        if (archive == .zip and config.target.result.os.tag != .windows) continue;
        const out_name = b.fmt("{s}.{s}", .{
            config.output_dir_basename,
            archive.asFileExtension(),
        });

        const packer = b.addRunArtifact(self.compressor);
        packer.addArg(@tagName(archive));
        const out_path = packer.addOutputFileArg(out_name);
        packer.addDirectoryArg(staging.getDirectory().path(b, config.output_dir_basename));
        self.step.dependOn(&packer.step);

        const copy = b.addInstallFileWithDir(
            out_path,
            .{ .custom = self.prefix_parent_dirname },
            out_name,
        );
        self.step.dependOn(&copy.step);
    }
}
