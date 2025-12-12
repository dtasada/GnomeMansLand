//! Local client handler struct
const std = @import("std");
const builtin = @import("builtin");
const network = @import("network");

const commons = @import("commons");
const socket_packet = @import("socket_packet");
const s2s = @import("s2s");

const ServerMap = @import("server").GameData.Map;
const GameData = @import("game").GameData;

pub const Settings = @import("Settings.zig");

const Self = @This();

alloc: std.mem.Allocator,
sock: network.Socket,
listen_handler: std.Io.Future(anyerror!void),
game_data: GameData,
wait_list: struct {
    client_accepted: ?socket_packet.ServerAcceptedClient = null,
},
running: std.atomic.Value(bool),
polling_rate: u64,
threaded: std.Io.Threaded,

const BYTE_LIMIT: usize = 65535;

pub fn init(
    alloc: std.mem.Allocator,
    settings: Settings,
    connect_message: socket_packet.ClientRequestsConnect,
    server_map: ?*ServerMap,
) !*Self {
    var self = try alloc.create(Self);
    errdefer alloc.destroy(self);

    try network.init();
    errdefer network.deinit();

    self.* = .{
        .alloc = alloc,
        .wait_list = .{},
        .sock = network.connectToHost(
            self.alloc,
            settings.multiplayer.server_host,
            settings.multiplayer.server_port,
            .tcp,
        ) catch |err| return commons.printErr(
            err,
            "Couldn't connect to host server at ({s}:{}): {}\n",
            .{ settings.multiplayer.server_host, settings.multiplayer.server_port, err },
            .red,
        ),
        .listen_handler = undefined,
        .running = .init(true),
        .polling_rate = settings.multiplayer.polling_rate,
        .game_data = undefined,
        .threaded = .init(alloc),
    };
    errdefer self.game_data.deinit(self.alloc);
    errdefer self.running.store(false, .monotonic);

    self.listen_handler = self.threaded.io().async(listen, .{self});
    self.game_data = try GameData.init(
        self.alloc,
        if (server_map) |s| b: {
            try self.send(.{ .client_requests_connect = connect_message });
            break :b .{ .yes = s };
        } else b: {
            const accept = try self.sendAndReceive(
                .{ .client_requests_connect = connect_message },
                socket_packet.ServerAcceptedClient,
                &self.wait_list.client_accepted,
            );
            break :b .{ .no = accept.map_size };
        },
    );

    if (server_map == null) try self.send(.client_requests_map_data);

    return self;
}

pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
    self.running.store(false, .monotonic);

    self.listen_handler.cancel(self.threaded.io()) catch |err|
        commons.print(
            "Client: Error canceling listen handler: {}\n",
            .{err},
            .yellow,
        );

    self.sock.close();

    self.game_data.deinit(self.alloc);

    network.deinit();

    self.threaded.deinit();

    alloc.destroy(self);
}

/// Sends `message` to server, then waits until `wait` is not null. Then returns `wait` unwrapped. Blocking
fn sendAndReceive(self: *Self, message: socket_packet.Packet, comptime T: type, wait: *?T) !T {
    try self.send(message);
    while (wait.* == null) {}
    return wait.*.?;
}

/// Meant to run as a thread. Listens for new messages and calls `handleMessage` upon receiving one.
fn listen(self: *Self) anyerror!void {
    var pending_data = try std.ArrayList(u8).initCapacity(self.alloc, BYTE_LIMIT);
    defer pending_data.deinit(self.alloc);

    var read_buffer: [4096]u8 = undefined;

    var message_len: u32 = 0;
    var reading_len = true;

    const io = self.threaded.io();
    while (self.running.load(.monotonic)) {
        var reading = io.async(network.Socket.receive, .{ self.sock, &read_buffer });
        const bytes_read = reading.await(io) catch |err| switch (err) {
            error.ConnectionResetByPeer => {
                self.running.store(false, .monotonic);
                commons.print("Socket disconnected\n", .{}, .blue);
                return;
            },
            else => return err,
        };

        if (bytes_read == 0) continue;

        try pending_data.appendSlice(self.alloc, read_buffer[0..bytes_read]);

        // Loop to process all complete messages in the pending_data buffer
        while (true) {
            if (reading_len) {
                if (pending_data.items.len >= 4) {
                    message_len = std.mem.readInt(u32, pending_data.items[0..4], .big);
                    reading_len = false;
                } else break;
            } else if (pending_data.items.len >= 4 + message_len) {
                // We have a full message (length prefix + payload)
                const message_payload = pending_data.items[4 .. 4 + message_len];
                try self.handleMessage(message_payload);

                // Remove the processed message from the buffer
                const processed_len = 4 + message_len;
                try pending_data.replaceRange(self.alloc, 0, processed_len, &.{});

                // Reset state to read the next length
                reading_len = true;
                message_len = 0;
            } else break;
        }
    }
}

/// Deserializes a message and processes it
fn handleMessage(self: *Self, message_payload: []const u8) !void {
    var stream = std.Io.Reader.fixed(message_payload);
    var packet = try s2s.deserializeAlloc(&stream, socket_packet.Packet, self.alloc);
    defer s2s.free(self.alloc, socket_packet.Packet, &packet);

    switch (packet) {
        .player_state => |player_state| {
            const player = player_state.player;
            if (self.game_data.players.items.len <= @as(usize, player.id)) {
                try self.game_data.players.append(self.alloc, player);
            } else {
                self.game_data.players.items[@intCast(player.id)] = player;
            }
        },
        .map_chunk => |map_chunk| {
            // if we don't own the map, we're the host, so we don't need to download it
            if (!self.game_data.map.owns_height_map) return;
            self.game_data.map.addChunk(map_chunk);
        },
        .server_full => @panic("unimplemented"),
        .server_accepted_client => |accepted_client| {
            self.wait_list.client_accepted = accepted_client;
        },
        else => commons.print(
            "Received message with illegal descriptor {s} received from server\n",
            .{@tagName(std.meta.activeTag(packet))},
            .yellow,
        ),
    }
}

pub fn send(self: *const Self, object: socket_packet.Packet) !void {
    var serialize_writer = std.Io.Writer.Allocating.init(self.alloc);
    defer serialize_writer.deinit();
    try s2s.serialize(&serialize_writer.writer, @TypeOf(object), object);

    const payload_bytes = serialize_writer.written();

    var client_writer_buf: [4096]u8 = undefined;
    var client_writer = self.sock.writer(&client_writer_buf);
    try client_writer.interface.writeInt(u32, @intCast(payload_bytes.len), .big);
    try client_writer.interface.writeAll(payload_bytes);
    try client_writer.interface.flush();
}
