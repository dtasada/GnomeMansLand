const std = @import("std");

const rl = @import("raylib");

const Game = @import("game");
const State = @import("State.zig");

const ui = @import("ui.zig");

const Self = @This();

buttons: ui.ButtonSet,

pub fn init(alloc: std.mem.Allocator) !Self {
    return .{
        .buttons = try ui.ButtonSet.initGeneric(
            alloc,
            .{ .top_left_x = 24, .top_left_y = 128 },
            &.{"Back"},
        ),
    };
}

pub fn deinit(self: *const Self, alloc: std.mem.Allocator) void {
    defer self.buttons.deinit(alloc);
}

pub fn update(self: *const Self, state: *State) !void {
    rl.beginDrawing();
    rl.clearBackground(.black);

    try self.buttons.update(.{
        .{ State.openLobby, .{state} },
    });

    rl.endDrawing();
}
