const std = @import("std");
const rl = @import("raylib");

const ui = @import("ui.zig");
const commons = @import("commons");

const Game = @import("game");
const State = @import("State.zig");
const Client = @import("client");

const Self = @This();

text_box_set: ui.TextBoxSet,
button_set: ui.ButtonSet,
port_string_buf: [6]u8,
max_players_string_buf: [2]u8,

pub fn init(alloc: std.mem.Allocator, settings: Client.Settings) !Self {
    var self: Self = undefined;

    @memset(&self.port_string_buf, 0);
    @memset(&self.max_players_string_buf, 0);

    const server_port = try std.fmt.bufPrint(&self.port_string_buf, "{}", .{settings.server.port});
    const max_players = try std.fmt.bufPrint(&self.max_players_string_buf, "{}", .{settings.server.max_players});

    self.text_box_set = try ui.TextBoxSet.initGeneric(
        alloc,
        .{ .top_left_x = 24, .top_left_y = 128 },
        &.{
            .{ .label = "Server port: ", .max_len = 5, .default_value = server_port },
            .{ .label = "Max players:", .max_len = 1, .default_value = max_players },
        },
    );
    self.button_set = try ui.ButtonSet.initGeneric(
        alloc,
        .{ // clamp button set to be under text boxes
            .top_left_x = self.text_box_set.getHitbox().x,
            .top_left_y = self.text_box_set.getHitbox().y + self.text_box_set.getHitbox().height + 16.0,
        },
        &.{
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
    if (game.server) |server| {
        const world_data = &server.game_data.world_data;
        if (!world_data.finished_generating.load(.monotonic) or
            !world_data.network_chunks_ready.load(.monotonic))
        {
            rl.beginDrawing();
            rl.clearBackground(.black);

            var buf: [24]u8 = undefined;
            const body = if (!world_data.finished_generating.load(.monotonic))
                try std.fmt.bufPrint(
                    &buf,
                    "Creating world ({}%)...",
                    .{@divFloor(
                        world_data.floats_written.load(.monotonic),
                        world_data.height_map.len,
                    )},
                )
            else if (!world_data.network_chunks_ready.load(.monotonic))
                try std.fmt.bufPrint(
                    &buf,
                    "Preparing world ({}%)...",
                    .{@divFloor(
                        100 * world_data.network_chunks_generated.load(.monotonic),
                        server.socket_packets.world_data_chunks.len,
                    )},
                )
            else
                unreachable;

            var loading_screen_text = try ui.Text.init(.{
                .x = @as(f32, @floatFromInt(rl.getScreenWidth())) / 2.0,
                .y = @as(f32, @floatFromInt(rl.getScreenHeight())) / 2.0,
                .anchor = .center,
                .body = body,
            });

            loading_screen_text.update();

            rl.endDrawing();
            return;
        }
    }

    rl.beginDrawing();
    rl.clearBackground(.black);

    try self.text_box_set.update(&.{
        &self.port_string_buf,
        &self.max_players_string_buf,
    });
    try self.button_set.update(.{
        .{ State.hostServer, .{game} },
        .{ State.openLobby, .{game} },
    });

    // bro do not touch this code this is so fragile bro. null termination sucks
    if (std.mem.indexOfScalar(u8, &self.port_string_buf, 0)) |len| {
        game.settings.multiplayer.server_port = std.fmt.parseUnsigned(
            u16,
            @ptrCast(self.port_string_buf[0..len]),
            10,
        ) catch default: {
            var port_box = self.text_box_set.boxes[1];
            var error_text = try ui.Text.init(.{
                .body = "not a valid number!",
                .x = port_box.inner_text.hitbox.x + port_box.getShadowHitbox().width,
                .y = port_box.inner_text.hitbox.y,
                .color = .red,
            });
            error_text.update();

            break :default game.settings.multiplayer.server_port;
        };
    }

    rl.endDrawing();
}
