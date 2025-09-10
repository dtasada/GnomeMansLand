const std = @import("std");

const rl = @import("raylib");

const ui = @import("../ui.zig");
const states = @import("states.zig");

const Game = @import("../Game.zig");

const Self = @This();

buttons: ui.ButtonSet,

pub fn init(alloc: std.mem.Allocator) !Self {
    return .{
        .buttons = try ui.ButtonSet.initGeneric(
            alloc,
            .{ .top_left_x = 24, .top_left_y = 128 },
            &[_][]const u8{"Back"},
        ),
    };
}

pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
    defer self.buttons.deinit(alloc);
}

pub fn update(self: *Self, game: *Game) !void {
    rl.beginDrawing();
    rl.clearBackground(.black);

    try self.buttons.update(.{
        .{ states.openLobby, .{game} },
    });

    rl.endDrawing();
}
