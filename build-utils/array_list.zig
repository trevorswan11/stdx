const std = @import("std");

/// A thin wrapper around a `std.ArrayList` that ignores allocation failure
pub fn ArrayList(T: type) type {
    return struct {
        const Self = @This();
        const Wrapped = std.ArrayList(T);

        b: *std.Build,
        wrapped: Wrapped = .empty,

        pub fn init(b: *std.Build) Self {
            return .{ .b = b };
        }

        pub fn append(self: *Self, item: T) void {
            self.wrapped.append(self.b.allocator, item) catch @panic("OOM");
        }

        pub fn appendSlice(self: *Self, slice: []const T) void {
            self.wrapped.appendSlice(self.b.allocator, slice) catch @panic("OOM");
        }

        pub fn clone(self: *Self) Self {
            return .{
                .b = self.b,
                .wrapped = self.wrapped.clone(self.b.allocator) catch @panic("OOM"),
            };
        }

        pub fn fromSlice(b: *std.Build, slice: []const T) Self {
            var self: Self = .init(b);
            self.appendSlice(slice);
            return self;
        }
    };
}
