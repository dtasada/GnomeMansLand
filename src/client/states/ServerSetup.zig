const std = @import("std");
const rl = @import("raylib");

const ui = @import("../ui.zig");
const commons = @import("../../commons.zig");
const states = @import("states.zig");

const Game = @import("../Game.zig");

const Self = @This();

text_box_set: ui.TextBoxSet,
button_set: ui.ButtonSet,
port_string_buf: [6]u8,
max_players_string_buf: [2]u8,

pub fn init(alloc: std.mem.Allocator, game: *Game) !Self {
    var self: Self = undefined;

    @memset(&self.port_string_buf, 0);
    @memset(&self.max_players_string_buf, 0);
    _ = try std.fmt.bufPrint(&self.port_string_buf, "{}", .{game.settings.server.port});
    _ = try std.fmt.bufPrint(&self.max_players_string_buf, "{}", .{game.settings.server.max_players});

    self.text_box_set = try ui.TextBoxSet.initGeneric(
        alloc,
        .{ .top_left_x = 24, .top_left_y = 128 },
        &[_]ui.BoxLabel{
            .{ .label = "Server port: ", .max_len = 5, .default_value = "42069" },
            .{ .label = "Max players:", .max_len = 1, .default_value = "4" },
        },
    );
    self.button_set = try ui.ButtonSet.initGeneric(
        game.alloc,
        .{ // clamp button set to be under text boxes
            .top_left_x = self.text_box_set.getHitbox().x,
            .top_left_y = self.text_box_set.getHitbox().y + self.text_box_set.getHitbox().height + 16.0,
        },
        &[_][]const u8{
            "Create server",
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

    // u16 port number can only be 5 chars, ipv4 can only be 15

    try self.text_box_set.update(&.{
        &self.port_string_buf,
        &self.max_players_string_buf,
    });
    try self.button_set.update(.{
        .{ states.hostServer, .{game} },
        .{ states.openLobby, .{game} },
    });

    // bro do not touch this code this is so fragile bro. null termination sucks
    const len = std.mem.indexOf(u8, &self.port_string_buf, &[_]u8{0}) orelse 0;
    if (len != 0) {
        game.settings.multiplayer.server_port = std.fmt.parseUnsigned(u16, @ptrCast(self.port_string_buf[0..len]), 10) catch def: {
            var port_box = self.text_box_set.boxes[1];
            var error_text = try ui.Text.init(game.alloc, .{
                .body = "not a valid number!",
                .x = port_box.inner_text.hitbox.x + port_box.getShadowHitbox().width,
                .y = port_box.inner_text.hitbox.y,
                .color = .red,
            });
            error_text.update();

            break :def game.settings.multiplayer.server_port;
        };
    }

    rl.endDrawing();
}
