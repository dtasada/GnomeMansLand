const Game = @import("../Game.zig");
const Client = @import("../Client.zig");
const Server = @import("../../server/Server.zig");

const std = @import("std");

const socket_packet = @import("../../socket_packet.zig");

pub const Lobby = @import("Lobby.zig");
pub const LobbySettings = @import("LobbySettings.zig");
pub const ClientSetup = @import("ClientSetup.zig");
pub const ServerSetup = @import("ServerSetup.zig");

pub fn openSettings(game: *Game) void {
    game.state = .lobby_settings;
}

pub fn openLobby(game: *Game) void {
    game.state = .lobby;
}

pub fn clientSetup(game: *Game) void {
    game.state = .client_setup;
}

pub fn serverSetup(game: *Game) void {
    game.state = .server_setup;
}

/// Creates client and opens game
pub fn openGame(game: *Game) void {
    if (game.lobby.nickname_input.len != 0) { // only if nickname isn't empty
        if (game.client) |client| client.deinit(game.alloc);

        game.client = Client.init(
            game.alloc,
            game.settings,
            socket_packet.ClientConnect.init(game.lobby.nickname_input.inner_text.body),
        ) catch null;

        if (game.client) |_| game.state = .game;
    }
}

pub fn hostServer(game: *Game) !void {
    if (game.server) |server| server.deinit(game.alloc);

    game.server = Server.init(game.alloc, game.settings.server) catch return;

    if (game.server) |_| {
        const wait_for_server_thread = try std.Thread.spawn(.{}, waitForServer, .{game});
        wait_for_server_thread.detach();
    }
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
                    openGame(game);
                    return;
                }
            }

            std.Thread.sleep(200 * std.time.ns_per_ms);
        }
    }
}
