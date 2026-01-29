//! Program entry point

const std = @import("std");

const commons = @import("commons");

const Game = @import("game");

pub fn main(init: std.process.Init) !void {
    // Create game object
    var game = Game.init(init.gpa, init.io) catch |err| switch (err) {
        error.UnexpectedToken => return commons.printErr(
            err,
            "Error parsing `settings.json`. Please check JSON syntax.",
            .{},
            .red,
        ),
        error.UnknownField => return commons.printErr(
            err,
            "Error parsing `settings.json`. Please check that the configuration is in the expected structure",
            .{},
            .red,
        ),
        else => return err,
    };
    defer game.deinit(init.gpa);

    // Main game loop here
    try game.loop();
}
