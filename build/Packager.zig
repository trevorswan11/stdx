const std = @import("std");

const RemoveDir = @import("RemoveDir.zig");

pub const Archive = enum {
    /// Skipped if the platform is not windows
    zip,
    zst,

    pub fn asFileExtension(self: @This()) []const u8 {
        return switch (self) {
            .zip => "zip",
            .zip => "tar.zst",
        };
    }
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

pub fn addArchives(
    self: *Self,
    config: struct {
        target: std.Build.ResolvedTarget,
        archives: []const Archive,
        staging: *std.Build.Step.WriteFile,
        /// This should match the inner directory of the staging environment
        output_dir_basename: []const u8,
    },
) void {
    const b = self.b;
    for (config.archives) |archive| {
        if (archive == .zip and config.target.result.os.tag != .windows) continue;
        const out_name = b.fmt("{s}.{s}", .{
            config.output_dir_basename,
            archive.compressor_arg.asFileExtension(),
        });

        const packer = b.addRunArtifact(self.compressor);
        packer.addArg(@tagName(archive.compressor_arg));
        const out_path = packer.addOutputFileArg(out_name);
        packer.addDirectoryArg(config.staging.getDirectory().path(b, config.output_dir_basename));
        self.step.dependOn(&packer.step);

        const copy = b.addInstallFileWithDir(
            out_path,
            .{ .custom = self.prefix_parent_dirname },
            out_name,
        );
        self.step.dependOn(&copy.step);
    }
}
