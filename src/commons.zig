//! Utility library for common (shared) functionality between different modules.

const std = @import("std");

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

/// Prints `text` formatted with `args` to stdlog. Formats the message with `Color`
pub inline fn print(comptime fmt: []const u8, args: anytype, comptime color: Color) void {
    switch (color) {
        .white => std.log.info(fmt, args),
        .blue => std.log.info("\x1b[0;32m" ++ fmt ++ "\x1b[0m", args),
        .green => std.log.info("\x1b[0;34m" ++ fmt ++ "\x1b[0m", args),
        .yellow => std.log.warn("\x1b[0;33m" ++ fmt ++ "\x1b[0m", args),
        .red => std.log.err("\x1b[0;31m" ++ fmt ++ "\x1b[0m", args),
    }
}

/// Prints an error `err` with `text` formatted with `args` to standard I/O, and returns `err`.
/// Formats the message with `color`.
/// Has no inherent functionality, but is used as a syntax sugar for returning an error while
/// also printing something.
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
