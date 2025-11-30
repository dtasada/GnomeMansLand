//! Container for game data owned by the client
const std = @import("std");
const rl = @import("raylib");
const commons = @import("commons");

const socket_packet = @import("socket_packet");

const Settings = @import("client").Settings;

const Player = @import("server").GameData.Player;

pub const Map = @import("Map.zig");

const Self = @This();

map: Map,
players: std.ArrayList(Player) = .{},

/// Initializes game data. `host_is_local` determines whether the Map will be fetched in the future,
/// or if it should be memcopied from the host server.
pub fn init(
    alloc: std.mem.Allocator,
    host_is_local: union(enum) {
        no: commons.v2u,
        yes: *@import("server").GameData.Map,
    },
) !Self {
    return .{
        .map = switch (host_is_local) {
            .no => |map_size| try Map.init(alloc, map_size),
            .yes => |server_map| try Map.initFromExisting(alloc, server_map),
        },
    };
}

pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
    self.map.deinit(alloc);
    self.players.deinit(alloc);
}
