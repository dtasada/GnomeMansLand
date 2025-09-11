const std = @import("std");
const rl = @import("raylib");

const ui = @import("../ui.zig");
const commons = @import("../../commons.zig");
const states = @import("states.zig");

const Game = @import("../Game.zig");

const Self = @This();

text_box_set: ui.TextBoxSet,
join_button: ui.Button,
server_port_string_buf: [6]u8,

pub fn init(alloc: std.mem.Allocator, game: *Game) !Self {
    var self: Self = undefined;

    @memset(&self.server_port_string_buf, 0);
    _ = try std.fmt.bufPrint(&self.server_port_string_buf, "{}", .{game.settings.multiplayer.server_port});

    self.text_box_set = try ui.TextBoxSet.initGeneric(
        alloc,
        .{ .top_left_x = 24, .top_left_y = 128 },
        &[_]ui.BoxLabel{
            .{ .label = "Server address: ", .max_len = 15, .default_value = "127.0.0.1" },
            .{ .label = "Server port: ", .max_len = 5, .default_value = "42069" },
        },
    );
    self.join_button = try ui.Button.init(.{
        .text = "Join server",
        .x = self.text_box_set.getHitbox().x,
        .y = self.text_box_set.getHitbox().y + self.text_box_set.getHitbox().height,
    });

    return self;
}

pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
    self.text_box_set.deinit(alloc);
}

pub fn update(self: *Self, game: *Game) !void {
    rl.beginDrawing();
    rl.clearBackground(.black);

    // u16 port number can only be 5 chars, ipv4 can only be 15

    var refs: [2][]u8 = [_][]u8{
        game.settings.multiplayer.server_host,
        &self.server_port_string_buf,
    };

    try self.text_box_set.update(&refs);
    try self.join_button.update(states.openGame, .{game});

    // bro do not touch this code this is so fragile bro. null termination sucks
    const len = std.mem.indexOf(u8, &self.server_port_string_buf, &[_]u8{0}) orelse 0;
    if (len != 0) {
        game.settings.multiplayer.server_port = std.fmt.parseUnsigned(u16, @ptrCast(self.server_port_string_buf[0..len]), 10) catch def: {
            const port_box = self.text_box_set.boxes[1];
            const error_text = try ui.Text.init(.{
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
