const std = @import("std");

/// Returns null-terminated string from `text`.
/// Caller must `@ptrCast()` to cast to a `[:0]const u8`.
/// Caller owns memory.
pub inline fn toSentinel(text: []const u8, buf: [:0]u8) void {
    const n = @min(text.len, buf.len - 1);
    @memcpy(buf[0..n], text[0..n]);
    buf[n] = 0;
    // return buf[0..n :0];
}

pub fn v2(T: type) type {
    return struct {
        const Self = @This();
        x: T,
        y: T,

        pub fn init(x: T, y: T) Self {
            return .{ .x = x, .y = y };
        }
    };
}

pub const v2f = v2(f32);
pub const v2u = v2(u32);

pub fn upper(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var out = try allocator.alloc(u8, s.len);
    for (s, 0..) |ch, i| {
        out[i] = std.ascii.toUpper(ch);
    }
    return out;
}

pub fn print(
    comptime text: []const u8,
    args: anytype,
    color: enum { white, red, green, blue, yellow },
) void {
    switch (color) {
        .white => {},
        .red => std.debug.print("\x1b[0;31m", .{}),
        .green => std.debug.print("\x1b[0;34m", .{}),
        .blue => std.debug.print("\x1b[0;34m", .{}),
        .yellow => std.debug.print("\x1b[0;33m", .{}),
    }
    std.debug.print(text, args);
    std.debug.print("\x1b[0m", .{});
}
