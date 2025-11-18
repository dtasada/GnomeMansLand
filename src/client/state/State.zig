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

state: enum {
    lobby,
    game,
    lobby_settings,
    client_setup,
    server_setup,
},

lobby: Lobby,
lobby_settings: LobbySettings,
client_setup: ClientSetup,
server_setup: ServerSetup,
in_game: InGame,

pub fn init(alloc: std.mem.Allocator, settings: Client.Settings) !Self {
    return .{
        .state = .lobby,
        .lobby = try Lobby.init(alloc),
        .lobby_settings = try LobbySettings.init(alloc),
        .server_setup = try ServerSetup.init(alloc, settings),
        .client_setup = try ClientSetup.init(alloc, settings),
        .in_game = try InGame.init(alloc),
    };
}

pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
    self.client_setup.deinit(alloc);
    self.server_setup.deinit(alloc);
    self.lobby.deinit(alloc);
    self.lobby_settings.deinit(alloc);
    self.in_game.deinit(alloc);
}

pub fn update(self: *Self, game: *Game) !void {
    switch (self.state) {
        .lobby => try self.lobby.update(game.alloc, self),
        .lobby_settings => try self.lobby_settings.update(game),
        .client_setup => try self.client_setup.update(game),
        .server_setup => try self.server_setup.update(game),
        .game => try self.in_game.update(game),
    }
}

pub fn openSettings(self: *Self) void {
    self.state = .lobby_settings;
}

pub fn openLobby(game: *Game) void {
    game.state.lobby.reinit(game.alloc) catch {};
    game.state.state = .lobby;
}

pub fn clientSetup(self: *Self) void {
    self.state = .client_setup;
}

pub fn serverSetup(self: *Self) void {
    self.state = .server_setup;
}

/// Creates client and opens game
pub fn openGame(game: *Game) !void {
    if (game.state.lobby.nickname_input.len != 0) { // only if nickname isn't empty
        if (game.client) |client| client.deinit(game.alloc);

        game.client = try Client.init(
            game.alloc,
            game.settings,
            socket_packet.ClientConnect.init(game.state.lobby.nickname_input.inner_text.body),
        );

        game.state.state = .game;
    }
}

pub fn hostServer(game: *Game) !void {
    if (game.server) |s| s.deinit(game.alloc);

    game.server = try Server.init(game.alloc, game.settings.server);

    const t = try std.Thread.spawn(.{}, waitForServer, .{game});
    t.detach();
}

fn waitForServer(game: *Game) !void {
    var chunk_thread: ?std.Thread = null;
    if (game.server) |server| {
        while (true) {
            if (server.game_data.world_data.finished_generating.load(.monotonic)) {
                if (chunk_thread == null) {
                    chunk_thread = try socket_packet.WorldDataChunk.init(
                        server.alloc,
                        &server.game_data.world_data,
                        server.socket_packets.world_data_chunks,
                    );
                }

                if (server.game_data.world_data.network_chunks_ready.load(.monotonic)) {
                    if (chunk_thread) |t| t.join();
                    try openGame(game);
                    return;
                }
            }

            std.Thread.sleep(200 * std.time.ns_per_ms);
        }
    }
}
