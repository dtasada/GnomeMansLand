const std = @import("std");

const rl = @import("raylib");

const ui = @import("../ui.zig");
const socket_packet = @import("../../socket_packet.zig");
const states = @import("states.zig");

const Server = @import("../../server/Server.zig");
const Client = @import("../Client.zig");
const Game = @import("../Game.zig");

const Self = @This();

nickname_input: ui.TextBox,
buttons: ui.ButtonSet,
title_text: ui.Text,

pub fn init(alloc: std.mem.Allocator) !Self {
    return .{
        .nickname_input = try ui.TextBox.init(alloc, .{
            .x = @as(f32, @floatFromInt(rl.getScreenWidth())) / 2.0 - 120,
            .y = 480,
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
        .title_text = try ui.Text.init(.{
            .body = "Gnome Man's Land",
            .font_size = .title,
            .x = @as(f32, @floatFromInt(rl.getScreenWidth())) / 2.0,
            .y = 100.0,
            .anchor = .center,
        }),
    };
}

pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
    self.nickname_input.deinit(alloc);
    self.buttons.deinit(alloc);
}

fn setServer(game: *Game) !void {
    if (game.server == null) game.server = try Server.init(game.alloc, game.settings.server);
}

fn setClient(self: *Self, game: *Game) !void {
    if (self.nickname_input.len != 0) { // only if nickname isn't empty
        if (game.client == null) game.client = Client.init(
            game.alloc,
            game.settings,
            socket_packet.ClientConnect.init(self.nickname_input.content.body),
        ) catch null;

        if (game.client) |_| game.state = .game;
    }
}

pub fn update(self: *Self, game: *Game) !void {
    rl.beginDrawing();
    rl.clearBackground(.black);

    try self.buttons.update(.{
        .{ setServer, .{game} },
        .{ setClient, .{ self, game } },
        .{ states.openSettings, .{game} },
    });

    self.title_text.update();

    try self.nickname_input.update();

    rl.endDrawing();
}
