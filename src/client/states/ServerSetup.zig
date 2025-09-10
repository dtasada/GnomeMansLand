const std = @import("std");

const ui = @import("../ui.zig");

const Game = @import("../Game.zig");

const Self = @This();

pub fn init(alloc: std.mem.Allocator) !Self {
    _ = alloc;
    return undefined;
}

pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
    _ = self;
    _ = alloc;
}

pub fn update(self: *Self, game: *Game) !void {
    _ = self;
    _ = game;
}
