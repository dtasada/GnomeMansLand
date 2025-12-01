//! TCP server struct
const std = @import("std");
const network = @import("network");

const socket_packet = @import("socket_packet");

const commons = @import("commons");
const s2s = @import("s2s");

pub const GameData = @import("GameData.zig");

const ServerSettings = commons.ServerSettings;

const Self = @This();

const BYTE_LIMIT: usize = 65535;

gpa: std.heap.DebugAllocator(.{}),
tsa: std.heap.ThreadSafeAllocator,
alloc: std.mem.Allocator,

/// Contains internal configuration.
settings: ServerSettings,

/// Arraylist of pointers to all the client objects.
clients: std.ArrayList(*Client),

/// Contains internal server game data.
game_data: GameData,

/// Contains cached data to be sent to clients.
socket_packets: struct {
    map_chunks: []socket_packet.MapChunk,
},

//// The network socket itself.
sock: network.Socket,

/// Atomic boolean identifying whether the server is running or not.
running: std.atomic.Value(bool),

/// Thread that runs `listen`
listen_thread: std.Thread,

/// Wrapper around a single client construct.
const Client = struct {
    /// The actual client socket object.
    sock: network.Socket,

    /// Thread that runs `handleClientReceive`
    thread_handle_receive: std.Thread,

    /// Thread that runs `handleClientSend`
    thread_handle_send: std.Thread,

    /// Internal identifier for a client object
    id: u32,

    /// Atomic boolean identifying whether the client is running or not
    open: std.atomic.Value(bool),

    pub fn send(self: *const Client, alloc: std.mem.Allocator, object: anytype) !void {
        var serialize_writer = std.Io.Writer.Allocating.init(alloc);
        defer serialize_writer.deinit();
        try s2s.serialize(&serialize_writer.writer, @TypeOf(object), object);

        const descriptor_byte: socket_packet.Descriptor.Type = @intFromEnum(object.descriptor);

        const payload_bytes = serialize_writer.written();
        const full_length: u32 = @sizeOf(socket_packet.Descriptor.Type) +
            @as(u32, @intCast(payload_bytes.len));

        var client_writer_buf: [4096]u8 = undefined;
        var client_writer = self.sock.writer(&client_writer_buf);
        try client_writer.interface.writeInt(u32, full_length, .big);
        try client_writer.interface.writeInt(socket_packet.Descriptor.Type, descriptor_byte, .big);
        try client_writer.interface.writeAll(payload_bytes);
        try client_writer.interface.flush();
    }
};

/// Runs until the client is disconnected. Reads incoming messages and calls `handleMessage`.
fn handleClientReceive(self: *Self, client: *Client) !void {
    defer {
        client.open.store(false, .monotonic);
        client.thread_handle_send.join();
        client.sock.close();
    }

    try client.sock.setReadTimeout(500 * 1000);

    var pending_data = try std.ArrayList(u8).initCapacity(self.alloc, BYTE_LIMIT);
    defer pending_data.deinit(self.alloc);

    var read_buffer: [4096]u8 = undefined;

    var message_len: u32 = 0;
    var reading_len = true;

    while (self.running.load(.monotonic)) {
        const bytes_read = client.sock.receive(&read_buffer) catch |err| switch (err) {
            error.WouldBlock => {
                std.Thread.sleep(10); // Sleep briefly if no data
                continue;
            },
            error.ConnectionResetByPeer => break, // Client disconnected
            else => return err,
        };

        if (bytes_read == 0) continue;

        try pending_data.appendSlice(self.alloc, read_buffer[0..bytes_read]);

        // Loop to process all complete messages in the pending_data buffer
        while (true) {
            if (reading_len) {
                if (pending_data.items.len >= 4) {
                    message_len = std.mem.readInt(u32, pending_data.items[0..@sizeOf(u32)], .big);
                    reading_len = false;
                } else break; // Not enough data for length
            } else if (pending_data.items.len >= 4 + message_len) {
                const message_payload = pending_data.items[4 .. 4 + message_len];
                try self.handleMessage(client, message_payload);

                const processed_len = 4 + message_len;
                try pending_data.replaceRange(self.alloc, 0, processed_len, &.{});

                reading_len = true;
                message_len = 0;
            } else break; // Not enough data for payload
        }
    }

    // The defer block will handle cleanup of threads and sockets.
    // The main Server.deinit will handle destroying the client object itself.
    commons.print("Client disconnected.\n", .{}, .blue);
}

/// Continuously sends all necessary game info to `client`. Blocking.
fn handleClientSend(self: *const Self, client: *const Client) !void {
    while (self.running.load(.monotonic) and client.open.load(.monotonic)) {
        // send necessary game info
        for (self.game_data.players.items) |p| {
            const player_packet = socket_packet.PlayerState.init(p);
            client.send(self.alloc, player_packet) catch |err| {
                commons.print("Failed to send message to client: {}\n", .{err}, .yellow);
                return;
            };
        }

        std.Thread.sleep(self.settings.polling_rate * std.time.ns_per_ms);
    }
}

/// Deserializes a message and processes it
fn handleMessage(self: *Self, client: *const Client, message_bytes: []const u8) !void {
    var stream = std.Io.Reader.fixed(message_bytes);

    const descriptor: socket_packet.Descriptor = @enumFromInt(try stream.takeByte());
    var serializer_stream = std.Io.Reader.fixed(message_bytes[@sizeOf(socket_packet.Descriptor)..]);

    switch (descriptor) {
        .client_requests_connect => {
            var client_connect = try s2s.deserializeAlloc(&serializer_stream, socket_packet.ClientRequestsConnect, self.alloc);
            defer s2s.free(self.alloc, socket_packet.ClientRequestsConnect, &client_connect);

            self.appendPlayer(client_connect) catch |err| switch (err) {
                error.ServerFull => {
                    commons.print(
                        "Client attempted to join from {f}, but the server is full ({}/{})!",
                        .{ try client.sock.getRemoteEndPoint(), self.game_data.players.items.len, self.game_data.players.capacity },
                        .yellow,
                    );
                    try client.send(self.alloc, socket_packet.ServerFull{});
                    return;
                },
                else => return err,
            };

            try client.send(self.alloc, socket_packet.ServerAcceptedClient.init(self.game_data.map.size));
        },
        .client_requests_map_data => {
            while (!self.game_data.map.network_chunks_ready.load(.monotonic)) {}
            for (self.socket_packets.map_chunks) |c|
                client.send(self.alloc, c) catch |err| {
                    commons.print("Failed to send message to client: {}\n", .{err}, .yellow);
                    return;
                };
        },
        .resend_request => @panic("unimplemented"),
        .client_requests_move_player => {
            var move_player = try s2s.deserializeAlloc(&serializer_stream, socket_packet.ClientRequestsMovePlayer, self.alloc);
            defer s2s.free(self.alloc, socket_packet.ClientRequestsMovePlayer, &move_player);
            self.game_data.players.items[client.id].position = move_player.new_pos;
        },
        else => return commons.printErr(
            error.IllegalMessage,
            "Illegal message received from client. Has descriptor {s}.\n",
            .{@tagName(descriptor)},
            .yellow,
        ),
    }
}

fn prepareMapChunks(self: *Self) !void {
    // Wait for the main map to finish generating
    while (!self.game_data.map.finished_generating.load(.monotonic)) : (std.Thread.sleep(100 * std.time.ns_per_ms)) {}

    // Now that the map is ready, generate the network chunks from it.
    try socket_packet.MapChunk.init(
        self.alloc,
        self.socket_packets.map_chunks,
        self.game_data.map,
    );
}

/// `game_data` and `socket_packets.map_chunks` are populated asynchronously
pub fn init(alloc: std.mem.Allocator, settings: ServerSettings) !*Self {
    var self = try alloc.create(Self);
    errdefer alloc.destroy(self);

    self.gpa = .init;
    errdefer _ = self.gpa.deinit();

    self.tsa = .{ .child_allocator = self.gpa.allocator() };
    self.alloc = self.tsa.allocator();

    self.settings = settings;

    self.clients = try .initCapacity(self.alloc, self.settings.max_players);
    errdefer self.clients.deinit(self.alloc);

    self.game_data = try GameData.init(self.alloc, self.settings);
    errdefer self.game_data.deinit(self.alloc);

    self.socket_packets = .{
        .map_chunks = try self.alloc.alloc(
            socket_packet.MapChunk,
            try std.math.divCeil(
                usize,
                self.game_data.map.height_map.len,
                socket_packet.MapChunk.FLOATS_PER_CHUNK,
            ),
        ),
    };
    errdefer self.alloc.free(self.socket_packets.map_chunks);

    const t = try std.Thread.spawn(.{}, Self.prepareMapChunks, .{self});
    t.detach();

    try network.init();
    errdefer network.deinit();

    self.sock = try network.Socket.create(.ipv4, .tcp);
    errdefer self.sock.close();

    self.sock.bindToPort(self.settings.port) catch |err|
        return commons.printErr(
            err,
            "Error initializing server: Couldn't bind to port {}. ({})\n",
            .{ self.settings.port, err },
            .red,
        );

    try self.sock.listen();

    self.running = std.atomic.Value(bool).init(true);

    self.listen_thread = try std.Thread.spawn(.{}, Self.listen, .{self});

    try self.sock.setReadTimeout(500 * 1000);

    return self;
}

pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
    self.alloc.free(self.socket_packets.map_chunks);

    self.game_data.deinit(self.alloc);
    self.running.store(false, .monotonic);

    self.listen_thread.detach(); // this works for some reason. see thousand yard stare

    for (self.clients.items) |client| {
        client.thread_handle_receive.join();
        self.alloc.destroy(client);
    }

    self.clients.deinit(self.alloc);

    self.sock.close();

    network.deinit();

    _ = self.gpa.deinit();

    alloc.destroy(self);
}

/// Listens for new clients and appends them to `self.clients`
fn listen(self: *Self) !void {
    try self.sock.listen();

    while (self.running.load(.monotonic)) {
        const sock = self.sock.accept() catch |err| switch (err) {
            error.WouldBlock, error.ConnectionAborted => continue,
            else => {
                commons.print("Server socket closed, shutting down...\n", .{}, .blue);
                break;
            },
        };

        var client = try self.alloc.create(Client);
        errdefer self.alloc.destroy(client);

        client.* = .{
            .sock = sock,
            .thread_handle_receive = undefined,
            .thread_handle_send = undefined,
            .id = @intCast(self.clients.items.len),
            .open = .init(true),
        };
        client.thread_handle_receive = try std.Thread.spawn(.{}, handleClientReceive, .{ self, client });
        client.thread_handle_send = try std.Thread.spawn(.{}, handleClientSend, .{ self, client });

        try self.clients.append(self.alloc, client);

        commons.print("Client connected from {f}.\n", .{try client.sock.getRemoteEndPoint()}, .blue);
    }
}

/// Appends a player to
fn appendPlayer(self: *Self, connect_request: socket_packet.ClientRequestsConnect) !void {
    // we duplicate the nickname because `connect_request` gets cleaned up after appendPlayer is called
    // so we prevent use after free
    const nickname_dupe = try self.alloc.dupe(u8, connect_request.nickname);
    errdefer self.alloc.free(nickname_dupe);

    self.game_data.players.appendBounded(GameData.Player.init(
        @intCast(self.game_data.players.items.len),
        nickname_dupe,
    )) catch return error.ServerFull;
}
