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
alloc: std.mem.Allocator,

/// Initializes all states and defaults to Lobby.
pub fn init(alloc: std.mem.Allocator, settings: Client.Settings) !Self {
    return .{
        .type = .lobby,
        .lobby = try Lobby.init(alloc, .{}),
        .lobby_settings = try LobbySettings.init(alloc),
        .server_setup = try ServerSetup.init(alloc, settings),
        .client_setup = try ClientSetup.init(alloc, settings),
        .in_game = try InGame.init(alloc),
        .alloc = alloc,
    };
}

/// Deinitializes all states.
pub fn deinit(self: *Self) void {
    self.client_setup.deinit(self.alloc);
    self.server_setup.deinit(self.alloc);
    self.lobby.deinit(self.alloc);
    self.lobby_settings.deinit(self.alloc);
    self.in_game.deinit(self.alloc);
}

/// Updates the current active state.
pub fn update(self: *Self, game: *Game) !void {
    switch (self.type) {
        .lobby => try self.lobby.update(game),
        .lobby_settings => try self.lobby_settings.update(self),
        .client_setup => try self.client_setup.update(game),
        .server_setup => try self.server_setup.update(game),
        .game => try self.in_game.update(game),
    }
}

pub fn openSettings(self: *Self) void {
    self.type = .lobby_settings;
}

pub fn openLobby(self: *Self) void {
    self.lobby.reinit(self.alloc) catch |err| {
        commons.print("Could not reinitalize lobby: {}\n", .{err}, .red);
        return;
    };
    self.type = .lobby;
}

pub fn clientSetup(self: *Self) void {
    self.type = .client_setup;
}

pub fn serverSetup(self: *Self) void {
    self.type = .server_setup;
}

/// Creates client and opens game.
/// If a server exists locally, the game data map will point to the server map.
/// Else, the client expects to receive a map payload from a remote server.
pub fn openGame(self: *Self, game: *Game) !void {
    std.debug.assert(self.lobby.nickname_input.getBody().len != 0);

    try game.initClient(
        self.lobby.nickname_input.getBody(),
        if (game.server) |s| s.game_data.map else null,
    );
    self.type = .game;
}

/// (Re)initializes server. Starts a thread for `waitForServer`
pub fn hostServer(self: *Self, game: *Game) !void {
    try game.initServer();

    const t = try std.Thread.spawn(.{}, waitForServer, .{ self, game });
    t.detach();
}

/// Waits for server to finish generating world, then opens the game locally.
fn waitForServer(self: *Self, game: *Game) !void {
    const server = game.server.?;
    while (!server.mapFinishedGenerating() or !server.mapChunksReady())
        try game.server.?.threaded.io().sleep(.fromMilliseconds(200), .awake);

    try self.openGame(game);
}
