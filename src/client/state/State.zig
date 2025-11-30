//! Object that contains all game UIs and states such as the in-game struct, lobby uis, etc.

const Game = @import("game");
const Client = @import("client");
const Server = @import("server");

const std = @import("std");

const socket_packet = @import("socket_packet");
const commons = @import("commons");

pub const Lobby = @import("Lobby.zig");
pub const LobbySettings = @import("LobbySettings.zig");
pub const ClientSetup = @import("ClientSetup.zig");
pub const ServerSetup = @import("ServerSetup.zig");
pub const InGame = @import("InGame.zig");
pub const ui = @import("ui.zig");

const Self = @This();

const Type = enum {
    lobby,
    game,
    lobby_settings,
    client_setup,
    server_setup,
};

type: Type,
lobby: Lobby,
lobby_settings: LobbySettings,
client_setup: ClientSetup,
server_setup: ServerSetup,
in_game: InGame,

/// Initializes all states and defaults to Lobby.
pub fn init(alloc: std.mem.Allocator, settings: Client.Settings) !Self {
    return .{
        .type = .lobby,
        .lobby = try Lobby.init(alloc),
        .lobby_settings = try LobbySettings.init(alloc),
        .server_setup = try ServerSetup.init(alloc, settings),
        .client_setup = try ClientSetup.init(alloc, settings),
        .in_game = try InGame.init(alloc),
    };
}

/// Deinitializes all states.
pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
    self.client_setup.deinit(alloc);
    self.server_setup.deinit(alloc);
    self.lobby.deinit(alloc);
    self.lobby_settings.deinit(alloc);
    self.in_game.deinit(alloc);
}

/// Updates the current active state.
pub fn update(self: *Self, game: *Game) !void {
    switch (self.type) {
        .lobby => try self.lobby.update(game),
        .lobby_settings => try self.lobby_settings.update(game),
        .client_setup => try self.client_setup.update(game),
        .server_setup => try self.server_setup.update(game),
        .game => try self.in_game.update(game),
    }
}

pub fn openSettings(self: *Self) void {
    self.type = .lobby_settings;
}

pub fn openLobby(self: *Self, game: *Game) void {
    self.lobby.reinit(game.alloc) catch @panic("unimplemented");
    self.type = .lobby;
}

pub fn clientSetup(self: *Self) void {
    self.type = .client_setup;
}

pub fn serverSetup(self: *Self) void {
    self.type = .server_setup;
}

/// Creates client and opens game normally.
pub fn openGameRemote(self: *Self, game: *Game) !void {
    if (self.lobby.nickname_input.len != 0) { // only if nickname isn't empty
        try game.reinitClient(self.lobby.nickname_input.getBody());
        self.type = .game;
    } else @panic("unimplemented");
}

/// Creates client and opens game, copying map data directly from local server
pub fn openGameLocal(self: *Self, game: *Game) !void {
    if (self.lobby.nickname_input.len != 0) { // only if nickname isn't empty
        try game.reinitClient(self.lobby.nickname_input.getBody());

        // Perform the memory copy
        game.client.?.game_data.map = try Game.GameData.Map.initFromExisting(
            game.alloc,
            game.server.?.game_data.map,
        );

        self.type = .game;
    } else @panic("unimplemented");
}

/// (Re)initializes server. Starts a thread for `waitForServer`
pub fn hostServer(self: *Self, game: *Game) !void {
    try game.reinitServer();

    const t = try std.Thread.spawn(.{}, waitForServer, .{ self, game });
    t.detach();
}

/// Waits for server to finish generating world, then opens the game locally.
fn waitForServer(self: *Self, game: *Game) !void {
    while (!game.server.?.game_data.map.finished_generating.load(.monotonic)) : (std.Thread.sleep(200 * std.time.ns_per_ms)) {}
    try self.openGameLocal(game);
}
