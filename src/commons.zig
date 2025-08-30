const std = @import("std");

pub fn upper(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var out = try allocator.alloc(u8, s.len);
    for (s, 0..) |ch, i| {
        out[i] = std.ascii.toUpper(ch);
    }
    return out;
}
