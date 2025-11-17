//! Container for game data owned by the client
const std = @import("std");
const rl = @import("raylib");
const commons = @import("../commons.zig");

const socket_packet = @import("../socket_packet.zig");

const Settings = @import("Settings.zig");
const Player = @import("../server/GameData.zig").Player;

pub const WorldData = @import("WorldData.zig");

const GameData = @This();

world_data: ?WorldData,
players: std.ArrayList(Player),

pub fn init(alloc: std.mem.Allocator) !GameData {
    return .{
        .world_data = null,
        .players = try std.ArrayList(Player).initCapacity(alloc, 1),
    };
}

pub fn deinit(self: *GameData, alloc: std.mem.Allocator) void {
    if (self.world_data) |*world_data|
        world_data.deinit(alloc);

    self.players.deinit(alloc);
}
