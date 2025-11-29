//! Container for game data owned by the client
const std = @import("std");
const rl = @import("raylib");
const commons = @import("commons");

const socket_packet = @import("socket_packet");

const Settings = @import("client").Settings;

const Player = @import("server").GameData.Player;

pub const Map = @import("Map.zig");

const Self = @This();

map: ?Map,
players: std.ArrayList(Player),

pub fn init(alloc: std.mem.Allocator) !Self {
    return .{
        .map = null,
        .players = try std.ArrayList(Player).initCapacity(alloc, 1),
    };
}

pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
    if (self.map) |*map|
            map.deinit(alloc);

    self.players.deinit(alloc);
}
