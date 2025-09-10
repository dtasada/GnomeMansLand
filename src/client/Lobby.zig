const std = @import("std");

const rl = @import("raylib");

const ui = @import("ui.zig");
const socket_packet = @import("../socket_packet.zig");

const Server = @import("../server/Server.zig");
const Client = @import("Client.zig");
const Game = @import("Game.zig");

const Self = @This();

nickname_input: ui.TextBox,

pub fn init(alloc: std.mem.Allocator) !Self {
    ui.chalk_font = try rl.loadFontEx("resources/fonts/chalk.ttf", 256, null);
    ui.gwathlyn_font = try rl.loadFontEx("resources/fonts/gwathlyn.ttf", 256, null);

    return .{
        .nickname_input = try ui.TextBox.init(alloc, .{
            .x = @as(f32, @floatFromInt(rl.getScreenWidth())) / 2.0 - 120,
            .y = 480,
        }),
    };
}

pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
    self.nickname_input.deinit(alloc);
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

    var buttons = try ui.ButtonSet.initGeneric(
        game.alloc,
        .{ .top_left_x = 24, .top_left_y = 128 },
        &[_][]const u8{ "Host server", "Connect to server" },
    );
    defer buttons.deinit(game.alloc);

    try buttons.update(.{
        .{ setServer, .{game} },
        .{ setClient, .{ self, game } },
    });

    const title_text = try ui.Text.init(.{
        .body = "Gnome Man's Land",
        .font_size = .title,
        .x = @as(f32, @floatFromInt(rl.getScreenWidth())) / 2.0,
        .y = 100.0,
        .anchor = .center,
    });

    title_text.update();

    try self.nickname_input.update();

    rl.endDrawing();
}
