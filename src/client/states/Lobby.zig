const std = @import("std");

const rl = @import("raylib");

const ui = @import("../ui.zig");
const socket_packet = @import("../../socket_packet.zig");
const states = @import("states.zig");

const Server = @import("../../server/Server.zig");
const Client = @import("../Client.zig");
const Game = @import("../Game.zig");

const Self = @This();

nickname_input_label: ui.Text,
nickname_input: ui.TextBox,
buttons: ui.ButtonSet,
title_text: ui.Text,

pub fn init(alloc: std.mem.Allocator) !Self {
    const nickname_input_label = try ui.Text.init(alloc, .{
        .body = "nickname: ",
        .x = @as(f32, @floatFromInt(rl.getScreenWidth())) / 2.0 - 120,
        .y = 480,
    });

    return .{
        .nickname_input_label = nickname_input_label,
        .nickname_input = try ui.TextBox.init(alloc, .{
            .x = ui.getRight(nickname_input_label.hitbox) + 16.0,
            .y = nickname_input_label.y,
        }),
        .buttons = try ui.ButtonSet.initGeneric(
            alloc,
            .{ .top_left_x = 24, .top_left_y = 128 },
            &[_][]const u8{
                "Host server",
                "Connect to server",
                "Settings",
            },
        ),
        .title_text = try ui.Text.init(alloc, .{
            .body = "Gnome Man's Land",
            .font_size = .title,
            .x = @as(f32, @floatFromInt(rl.getScreenWidth())) / 2.0,
            .y = 100.0,
            .anchor = .center,
        }),
    };
}

pub fn deinit(self: *const Self, alloc: std.mem.Allocator) void {
    self.nickname_input.deinit(alloc);
    self.buttons.deinit(alloc);
}

pub fn update(self: *Self, game: *Game) !void {
    rl.beginDrawing();
    rl.clearBackground(.black);

    try self.buttons.update(.{
        .{ states.serverSetup, .{game} },
        .{ states.clientSetup, .{game} },
        .{ states.openSettings, .{game} },
    });

    self.title_text.update();

    self.nickname_input_label.update();
    try self.nickname_input.update();

    rl.endDrawing();
}
