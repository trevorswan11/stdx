const std = @import("std");

const Self = @This();

step: std.Build.Step,
doomed_path: std.Build.LazyPath,

pub fn init(b: *std.Build, doomed_path: std.Build.LazyPath) *Self {
    const remove_dir = b.allocator.create(Self) catch @panic("OOM");
    remove_dir.* = .{
        .step = .init(.{
            .id = .custom,
            .name = b.fmt("RemoveDir {s}", .{doomed_path.getDisplayName()}),
            .owner = b,
            .makeFn = make,
        }),
        .doomed_path = doomed_path.dupe(b),
    };
    return remove_dir;
}

fn make(step: *std.Build.Step, _: std.Build.Step.MakeOptions) !void {
    const self: *Self = @fieldParentPtr("step", step);

    const b = step.owner;
    const io = b.graph.io;

    step.clearWatchInputs();
    try step.addWatchInput(self.doomed_path);

    const full_doomed_path = try self.doomed_path.getPath4(b, step);

    b.build_root.handle.deleteTree(io, full_doomed_path.sub_path) catch |err| {
        if (b.build_root.path) |base| {
            return step.fail("unable to recursively delete path '{s}/{s}': {s}", .{
                base, full_doomed_path.sub_path, @errorName(err),
            });
        } else {
            return step.fail("unable to recursively delete path '{s}': {s}", .{
                full_doomed_path.sub_path, @errorName(err),
            });
        }
    };
}
