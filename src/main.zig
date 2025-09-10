//! Program entry point

const rl = @import("raylib");
const std = @import("std");

const commons = @import("commons.zig");

const Game = @import("Client/Game.zig");

/// Set up Raylib window and corresponding settings
fn setupRaylib() void {
    const screenWidth = 1280;
    const screenHeight = 720;

    rl.setConfigFlags(.{
        .window_highdpi = true,
        .vsync_hint = true,
        .window_topmost = true,
        .msaa_4x_hint = true,
    });

    rl.initWindow(screenWidth, screenHeight, "Gnome Man's Land");
    rl.setExitKey(.null);
    rl.setTargetFPS(165);
}

pub fn main() !void {
    setupRaylib();
    defer rl.closeWindow();

    // Create allocator for game object
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();

    const alloc = gpa.allocator();

    // Create game object
    var game = Game.init(alloc) catch |err| switch (err) {
        error.UnexpectedToken => {
            commons.print("Error parsing `settings.json`. Please check JSON syntax.\n", .{}, .red);
            return;
        },
        error.UnknownField => {
            commons.print("Error parsing `settings.json`. Please check that the configuration is in the expected structure\n", .{}, .red);
            return;
        },
        else => return err,
    };

    defer game.deinit(alloc);

    // Main game loop here
    try game.loop();
}
