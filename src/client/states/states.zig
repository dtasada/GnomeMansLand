const Game = @import("../Game.zig");

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
