//! Utility library for common (shared) functionality between different modules.

const std = @import("std");
const rl = @import("raylib");
const s2s = @import("s2s");

const socket_packet = @import("socket_packet");

/// Returns null-terminated string from `text`.
/// Caller must `@ptrCast()` to cast to a `[:0]const u8`.
/// Caller owns memory.
pub inline fn toSentinel(text: []const u8, buf: [:0]u8) void {
    const n = @min(text.len, buf.len - 1);
    @memcpy(buf[0..n], text[0..n]);
    buf[n] = 0;
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
pub fn print(comptime fmt: []const u8, args: anytype, comptime color: Color) void {
    var buf: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&buf);
    var stdout = &stdout_writer.interface;

    stdout.print(
        switch (color) {
            .white => "",
            .red => "\x1b[0;31m",
            .green => "\x1b[0;34m",
            .blue => "\x1b[0;32m",
            .yellow => "\x1b[0;33m",
        } ++ fmt ++ "\x1b[0m",
        args,
    ) catch |err| std.debug.print("Couldn't stdout.print(): {}\n", .{err});

    stdout.flush() catch |err| std.debug.print("Couldn't stdout.flush(): {}\n", .{err});
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

/// Gets descriptor field from a JSON object and converts it to a `socket_packet.Descriptor`.
/// `source` is either
pub fn getDescriptor(
    object: @FieldType(std.json.Value, "object"),
    comptime source: enum { server, client },
) !socket_packet.Descriptor {
    const descriptor_obj = object.get("descriptor") orelse
        return printErr(
            error.InvalidMessage,
            "Received message from " ++ @tagName(source) ++ " without a descriptor!",
            .{},
            .yellow,
        );

    return std.meta.stringToEnum(socket_packet.Descriptor, descriptor_obj.string) orelse
        printErr(
            error.InvalidMessage,
            "Received message with invalid descriptor {s} from " ++ @tagName(source) ++ ".\n",
            .{descriptor_obj.string},
            .yellow,
        );
}
