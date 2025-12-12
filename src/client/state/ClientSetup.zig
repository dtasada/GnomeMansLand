const std = @import("std");
const rl = @import("raylib");

const ui = @import("ui.zig");
const commons = @import("commons");

const Game = @import("game");
const Client = @import("client");
const State = @import("State.zig");

const Self = @This();

text_box_set: ui.TextBoxSet,
button_set: ui.ButtonSet,
/// u16 port number can only be 5 chars
server_port_string_buf: [6]u8 = undefined,
connect_error_text: ?ui.Text = null,
server_port_error_text: ?ui.Text = null,

pub fn init(alloc: std.mem.Allocator, settings: Client.Settings) !Self {
    var self: Self = .{
        .text_box_set = undefined,
        .button_set = undefined,
    };

    self.text_box_set = try ui.TextBoxSet.initGeneric(
        alloc,
        .{ .top_left_x = 24, .top_left_y = 128 },
        &.{
            .{
                .label = "Server address: ",
                .max_len = 15,
                .default_value = @constCast(settings.multiplayer.server_host),
            },
            .{
                .label = "Server port: ",
                .max_len = self.server_port_string_buf.len - 1,
                .default_value = try std.fmt.bufPrint(&self.server_port_string_buf, "{}", .{settings.multiplayer.server_port}),
            }, // buf.len - 1 bc discard sentinel
        },
    );
    self.button_set = try ui.ButtonSet.initGeneric(
        alloc,
        .{
            .top_left_x = self.text_box_set.getHitbox().x,
            .top_left_y = self.text_box_set.getHitbox().y + self.text_box_set.getHitbox().height + 16.0,
        },
        &.{
            "Join server",
            "Back",
        },
    );

    return self;
}

pub fn deinit(self: *const Self, alloc: std.mem.Allocator) void {
    self.button_set.deinit(alloc);
    self.text_box_set.deinit(alloc);
}

pub fn update(self: *Self, game: *Game) !void {
    rl.beginDrawing();
    rl.clearBackground(.black);

    try self.text_box_set.update(&.{
        game.settings.multiplayer.server_host,
        &self.server_port_string_buf,
    });

    self.button_set.update(.{
        .{ State.openGame, .{ &game.state, game } },
        .{ State.openLobby, .{&game.state} },
    }) catch |err| switch (err) {
        error.CouldNotConnect => {
            self.connect_error_text = try ui.Text.init(.{
                .body = "Couldn't connect to server!",
                .color = .red,
                .x = ui.getRight(self.button_set.buttons[0].getHitbox()) + 12.0,
                .y = self.button_set.buttons[0].getHitbox().y + 4.0,
            });
        },
        else => return err,
    };

    if (self.connect_error_text) |*ce| ce.update();

    // bro do not touch this code this is so fragile bro. null termination sucks
    if (std.mem.indexOfScalar(u8, &self.server_port_string_buf, 0)) |len| {
        game.settings.multiplayer.server_port = std.fmt.parseUnsigned(u16, @ptrCast(self.server_port_string_buf[0..len]), 10) catch default: {
            var port_box = self.text_box_set.boxes[1];
            self.server_port_error_text = try ui.Text.init(.{
                .body = "not a valid number!",
                .x = port_box.inner_text.hitbox.x + port_box.getShadowHitbox().width,
                .y = port_box.inner_text.hitbox.y,
                .color = .red,
            });

            break :default game.settings.multiplayer.server_port;
        };
    }

    if (self.server_port_error_text) |*t| t.update();

    rl.endDrawing();
}
