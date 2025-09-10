const Game = @import("../Game.zig");

pub fn openSettings(game: *Game) void {
    game.state = .lobby_settings;
}

pub fn openLobby(game: *Game) void {
    game.state = .lobby;
}
