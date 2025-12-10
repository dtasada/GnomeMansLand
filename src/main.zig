//! Program entry point

const std = @import("std");

const commons = @import("commons");

const Game = @import("game");

pub fn main() !void {
    // Create allocator for game object
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    // Create game object
    var game = Game.init(alloc) catch |err| switch (err) {
        error.UnexpectedToken => return commons.printErr(
            err,
            "Error parsing `settings.json`. Please check JSON syntax.\n",
            .{},
            .red,
        ),
        error.UnknownField => return commons.printErr(
            err,
            "Error parsing `settings.json`. Please check that the configuration is in the expected structure\n",
            .{},
            .red,
        ),
        else => return err,
    };
    defer game.deinit(alloc);

    // Main game loop here
    try game.loop();
}
