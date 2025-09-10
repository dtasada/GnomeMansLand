const std = @import("std");
const rl = @import("raylib");

const ui = @import("../ui.zig");
const commons = @import("../../commons.zig");

const Game = @import("../Game.zig");

const Self = @This();

text_box_set: ui.TextBoxSet,

pub fn init(alloc: std.mem.Allocator) !Self {
    return .{
        .text_box_set = try ui.TextBoxSet.initGeneric(
            alloc,
            .{ .top_left_x = 24, .top_left_y = 128 },
            &[_]ui.BoxLabel{
                .{ .label = "Server address: ", .max_len = 15 },
                .{ .label = "Server port: ", .max_len = 5 },
            },
        ),
    };
}

pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
    self.text_box_set.deinit(alloc);
}

pub fn update(self: *Self, game: *Game) !void {
    rl.beginDrawing();
    rl.clearBackground(.black);

    // u16 port number can only be 5 chars, ipv4 can only be 15
    var server_port_string_buf: [6]u8 = undefined;
    var refs: [2][]u8 = [_][]u8{
        game.settings.multiplayer.server_host,
        &server_port_string_buf,
    };
    try self.text_box_set.update(&refs);

    const len = std.mem.indexOf(u8, &server_port_string_buf, &[_]u8{0}) orelse 0;
    if (len != 0) {
        game.settings.multiplayer.server_port = std.fmt.parseInt(
            u16,
            @ptrCast(&server_port_string_buf[0..len]),
            10,
        ) catch def: {
            // commons.print("Server port input is not a valid number\n", .{}, .red);
            break :def game.settings.multiplayer.server_port;
        };
    }

    rl.endDrawing();
}
