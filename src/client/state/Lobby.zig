const std = @import("std");

const rl = @import("raylib");

const ui = @import("ui.zig");
const socket_packet = @import("socket_packet");
const commons = @import("commons");

const Client = @import("client");
const Game = @import("game");
const State = @import("State.zig");

const Self = @This();

nickname_input: ui.TextBox,
buttons: ui.ButtonSet,
title_text: ui.Text,
nickname_error_text: ?ui.Text = null,

pub fn init(
    alloc: std.mem.Allocator,
    settings: struct {
        nickname_input_body: []const u8 = "",
    },
) !Self {
    const width: f32 = @floatFromInt(rl.getScreenWidth());
    const height: f32 = @floatFromInt(rl.getScreenHeight());

    return .{
        .nickname_input = try ui.TextBox.init(alloc, .{
            .x = width / 2.0 - 160.0,
            .y = height - 240.0,
            .default_body = settings.nickname_input_body,
            .label = "nickname: ",
        }),
        .buttons = try ui.ButtonSet.initGeneric(
            alloc,
            .{ .top_left_x = 24, .top_left_y = 128 },
            &.{
                "Host server",
                "Connect to server",
                "Settings",
            },
        ),
        .title_text = try ui.Text.init(.{
            .body = "Gnome Man's Land",
            .font_size = .title,
            .x = width / 2.0,
            .y = 100.0,
            .anchor = .center,
        }),
    };
}

pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
    self.nickname_input.deinit(alloc);
    self.buttons.deinit(alloc);
}

/// Deinits and reinitializes Lobby. used when resizing window.
pub fn reinit(self: *Self, alloc: std.mem.Allocator) !void {
    const nickname_save = try alloc.dupe(u8, self.nickname_input.getBody());
    defer alloc.free(nickname_save);

    self.deinit(alloc);
    self.* = try init(alloc, .{ .nickname_input_body = nickname_save });
}

pub fn update(self: *Self, game: *Game) !void {
    if (rl.isWindowResized())
        try self.reinit(game.alloc);

    rl.clearBackground(.black);

    try self.buttons.update(.{
        .{ serverSetup, .{ self, &game.state } },
        .{ State.clientSetup, .{&game.state} },
        .{ State.openSettings, .{&game.state} },
    });

    self.title_text.update();

    try self.nickname_input.update();

    if (self.nickname_error_text) |*t| t.update();

    rl.endDrawing();
}

pub fn serverSetup(self: *Self, game_state: *State) void {
    if (game_state.lobby.nickname_input.getBody().len != 0) {
        self.nickname_error_text = null;
        State.serverSetup(game_state);
    } else {
        if (self.nickname_error_text == null) {
            const nickname_input_pos = game_state.lobby.nickname_input.label.getHitbox();
            self.nickname_error_text = try .init(.{
                .body = "nickname can't be empty!",
                .x = nickname_input_pos.x,
                .y = nickname_input_pos.y + nickname_input_pos.height + 12,
                .color = .red,
            });
        }
    }
}
