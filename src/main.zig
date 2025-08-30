const rl = @import("raylib");
const std = @import("std");
const rg = @import("raygui");
const Camera = @import("rcamera.zig");
const Light = @import("light.zig");
const Settings = @import("settings.zig");
const WorldGen = @import("worldgen.zig");
const Server = @import("server.zig");
const Client = @import("client.zig");
const Game = @import("game.zig");

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
    rl.setTargetFPS(60);
    rl.disableCursor();
    rl.hideCursor();
}

pub fn main() !void {
    setupRaylib();
    defer rl.closeWindow();

    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();

    const alloc = gpa.allocator();

    var game = try Game.init(alloc);
    defer alloc.destroy(game);
    defer game.deinit();

    try game.loop();
}
