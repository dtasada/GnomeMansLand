//! Utility library for common (shared) functionality between different modules.

const std = @import("std");
const rl = @import("raylib");

/// Returns null-terminated string from `text`.
/// Caller must `@ptrCast()` to cast to a `[:0]const u8`.
/// Caller owns memory.
pub inline fn toSentinel(text: []const u8, buf: [:0]u8) void {
    const n = @min(text.len, buf.len - 1);
    @memcpy(buf[0..n], text[0..n]);
    buf[n] = 0;
    // return buf[0..n :0];
}

/// 2-dimensional vector type.
pub fn v2(comptime T: type) type {
    return struct {
        const Self = @This();
        x: T,
        y: T,

        pub fn init(x: T, y: T) Self {
            return .{ .x = x, .y = y };
        }

        pub fn format(self: Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
            try writer.print("v2(x={}, y={})", .{ self.x, self.y });
        }
    };
}

pub const v2f = v2(f32);
pub const v2u = v2(u32);

const Color = enum { white, red, green, blue, yellow };

/// Prints `text` formatted with `args` to standard I/O. Formats the message with `Color`
pub fn print(comptime text: []const u8, args: anytype, color: Color) void {
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

/// Prints an error `err` with `text` formatted with `args` to standard I/O, and returns `err`.
/// Formats the message with `Color`.
pub inline fn printErr(
    err: anytype,
    comptime text: []const u8,
    args: anytype,
    color: Color,
) @TypeOf(err) {
    print(text, args, color);
    return err;
}

/// Sub-container for server-specific configuration
pub const ServerSettings = struct {
    max_players: u32,
    port: u16,
    polling_rate: u64,

    world_generation: struct {
        resolution: [2]u32,
        seed: ?u32 = null,
        octaves: i32,
        persistence: f32,
        lacunarity: f32,
        frequency: f32,
        amplitude: f32,
    },
};
