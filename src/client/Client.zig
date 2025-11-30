//! Local client handler struct
const std = @import("std");
const builtin = @import("builtin");
const network = @import("network");

const commons = @import("commons");
const socket_packet = @import("socket_packet");
const s2s = @import("s2s");

const GameData = @import("game").GameData;

pub const Settings = @import("Settings.zig");

const Self = @This();

alloc: std.mem.Allocator,
sock: network.Socket,
listen_thread: std.Thread,
game_data: GameData,
running: std.atomic.Value(bool),
polling_rate: u64,

const BYTE_LIMIT: usize = 65535;

pub fn init(alloc: std.mem.Allocator, settings: Settings, connect_message: socket_packet.ClientConnect) !*Self {
    var self = try alloc.create(Self);
    errdefer alloc.destroy(self);

    self.alloc = alloc;

    self.game_data = try GameData.init(self.alloc);
    errdefer self.game_data.deinit(self.alloc);

    try network.init();
    errdefer network.deinit();

    self.sock = network.connectToHost(
        self.alloc,
        settings.multiplayer.server_host,
        settings.multiplayer.server_port,
        .tcp,
    ) catch |err| return commons.printErr(
        err,
        "Couldn't connect to host server at ({s}:{}): {}\n",
        .{ settings.multiplayer.server_host, settings.multiplayer.server_port, err },
        .red,
    );

    self.running = std.atomic.Value(bool).init(true);
    errdefer self.running.store(false, .monotonic);

    try self.serializeSend(self.alloc, connect_message);

    self.listen_thread = try std.Thread.spawn(.{}, Self.listen, .{self});
    self.polling_rate = settings.multiplayer.polling_rate;

    try self.sock.setReadTimeout(500 * 1000); // set 500 ms timeout for thread join

    return self;
}

pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
    self.game_data.deinit(self.alloc);

    self.running.store(false, .monotonic);

    self.listen_thread.join();
    self.sock.close();

    network.deinit();

    alloc.destroy(self);
}

/// Meant to run as a thread. Listens for new messages and calls `handleMessage` upon receiving one.
fn listen(self: *Self) !void {
    const buf = try self.alloc.alloc(u8, BYTE_LIMIT); // don't decrease this. decreasing it makes it slower
    defer self.alloc.free(buf);

    var pending = try std.ArrayList(u8).initCapacity(self.alloc, BYTE_LIMIT);
    defer pending.deinit(self.alloc);

    while (self.running.load(.monotonic)) : (std.Thread.sleep(std.time.ns_per_ms * self.polling_rate)) {
        const bytes_read = self.sock.receive(buf) catch |err| switch (err) {
            error.WouldBlock => continue,
            error.ConnectionResetByPeer => {
                self.running.store(false, .monotonic);
                commons.print("Socket disconnected\n", .{}, .blue);
                return;
            },
            else => return commons.printErr(
                err,
                "Couldn't read from socket: {}\n",
                .{err},
                .red,
            ),
        };

        if (bytes_read == 0) break;
        if (!self.running.load(.monotonic)) return;

        try pending.appendSlice(self.alloc, buf[0..bytes_read]);

        // Process complete lines
        const message_len = std.mem.readInt(usize, pending.items[0..@sizeOf(usize)], .big) +
            @sizeOf(socket_packet.Descriptor.Type);

        try self.handleMessage(pending.items[@sizeOf(usize)..message_len]);

        // Remove processed bytes from buffer
        const range = try self.alloc.alloc(usize, message_len);
        defer self.alloc.free(range);
        for (0..message_len) |i| range[i] = i;
        pending.orderedRemoveMany(range);
    }
}

/// Deserializes a message and processes it
fn handleMessage(self: *Self, message_bytes: []const u8) !void {
    var stream = std.Io.Reader.fixed(message_bytes);

    const descriptor: socket_packet.Descriptor = @enumFromInt(try stream.takeByte());
    var serializer_stream = std.Io.Reader.fixed(message_bytes[@sizeOf(socket_packet.Descriptor)..]);

    switch (descriptor) {
        .player_state => {
            const player = try s2s.deserializeAlloc(&serializer_stream, socket_packet.Player, self.alloc);
            if (self.game_data.players.items.len <= @as(usize, player.player.id)) {
                try self.game_data.players.append(self.alloc, player.player);
            } else {
                self.game_data.players.items[@intCast(player.player.id)] = player.player;
            }
        },
        .map_chunk => {
            // if we don't own the map, we're the host, so we don't need to download it
            if (self.game_data.map) |*map| {
                if (!map.owns_height_map) return;
            }

            const map_chunk = try s2s.deserializeAlloc(&serializer_stream, socket_packet.MapChunk, self.alloc);

            if (self.game_data.map) |*map|
                map.addChunk(map_chunk)
            else
                self.game_data.map = try GameData.Map.init(self.alloc, map_chunk);
        },
        .server_full => @panic("unimplemented"),
        else => commons.print(
            "Received message with illegal descriptor {s} received from server\n",
            .{@tagName(descriptor)},
            .yellow,
        ),
    }
}

pub fn serializeSend(self: *const Self, alloc: std.mem.Allocator, object: anytype) !void {
    var serialize_writer = std.Io.Writer.Allocating.init(alloc);
    defer serialize_writer.deinit();
    try s2s.serialize(&serialize_writer.writer, @TypeOf(object), object);

    const descriptor_byte: socket_packet.Descriptor.Type = @intFromEnum(object.descriptor);

    const payload_bytes = serialize_writer.written();
    const full_length = @sizeOf(socket_packet.Descriptor.Type) + payload_bytes.len; // Descriptor byte + payload

    var client_writer_buf: [4096]u8 = undefined;
    var client_writer = self.sock.writer(&client_writer_buf);
    const client_writer_interface = &client_writer.interface;
    try client_writer_interface.writeInt(usize, @intCast(full_length), .big); // Length prefix
    try client_writer_interface.writeInt(socket_packet.Descriptor.Type, descriptor_byte, .big); // Descriptor
    try client_writer_interface.writeAll(payload_bytes); // s2s Payload
}
