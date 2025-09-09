const std = @import("std");

pub inline fn getCString(text: []const u8) [:0]const u8 {
    return @ptrCast(text.ptr[0..text.len :0]);
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
