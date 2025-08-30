const std = @import("std");
const SharedGameData = @import("SharedGameData.zig");

const Self = @This();

players: std.ArrayList(SharedGameData.Player),

pub fn init(alloc: std.mem.Allocator) !Self {
    return .{
        .players = try .initCapacity(alloc, 8),
    };
}

pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
    self.players.deinit(alloc);
}
