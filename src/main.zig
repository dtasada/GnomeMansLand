//! Program entry point

const rl = @import("raylib");
const std = @import("std");
const rg = @import("raygui");
const Game = @import("Game.zig");

/// Set up Raylib window and corresponding settings
fn setupRaylib() void {
    const screenWidth = 1280;
    const screenHeight = 720;

    rl.setConfigFlags(.{
        .window_highdpi = true,
        .vsync_hint = true,
        .window_resizable = true,
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
    var game = try Game.init(alloc);

    defer alloc.destroy(game);
    defer game.deinit();

    // Main game loop here
    try game.loop();
}
