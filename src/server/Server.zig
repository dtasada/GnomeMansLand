//! TCP server struct
const std = @import("std");

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
server: std.Io.net.Server,

/// Atomic boolean identifying whether the server is running or not.
running: std.atomic.Value(bool),

/// Thread that runs `listen`
listen_thread: std.Thread,

io: std.Io,
threaded: std.Io.Threaded,

/// Wrapper around a single client construct.
const Client = struct {
    /// The actual client socket object.
    stream: std.Io.net.Stream,

    /// Async handle that runs `handleClientReceive`
    receive_handler: std.Io.Future(anyerror!void),

    /// Async handle runs `handleClientSend`
    send_handler: std.Io.Future(void),

    /// Internal identifier for a client object
    id: u32,

    /// Atomic boolean identifying whether the client is running or not
    open: std.atomic.Value(bool),

    pub fn send(self: *const Client, alloc: std.mem.Allocator, io: std.Io, object: socket_packet.Packet) !void {
        var serialize_writer = std.Io.Writer.Allocating.init(alloc);
        defer serialize_writer.deinit();
        try s2s.serialize(&serialize_writer.writer, @TypeOf(object), object);

        const payload_bytes = serialize_writer.written();

        var client_writer_buf: [4096]u8 = undefined;
        var client_writer = self.stream.writer(io, &client_writer_buf);
        try client_writer.interface.writeInt(u32, @intCast(payload_bytes.len), .big);
        try client_writer.interface.writeAll(payload_bytes);
        try client_writer.interface.flush();
    }
};

/// Runs until the client is disconnected. Reads incoming messages and calls `handleMessage`.
fn handleClientReceive(self: *Self, client: *Client) anyerror!void {
    defer {
        client.open.store(false, .monotonic);
        client.stream.close(self.io);
    }

    var pending_data = try std.ArrayList(u8).initCapacity(self.alloc, BYTE_LIMIT);
    defer pending_data.deinit(self.alloc);

    var read_buffer: [4096]u8 = undefined;

    var message_len: u32 = 0;
    var reading_len = true;

    while (self.running.load(.monotonic)) {
        var reading = self.io.async(std.Io.net.Socket.receive, .{ &client.stream.socket, self.io, &read_buffer });
        const message = reading.await(self.io) catch |err| switch (err) {
            error.ConnectionResetByPeer => break, // Client disconnected
            else => return err,
        };

        if (message.data.len == 0) continue;

        try pending_data.appendSlice(self.alloc, message.data);

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
    commons.print("Client disconnected.", .{}, .blue);
}

/// Continuously sends all necessary game info to `client`. Blocking.
fn handleClientSend(self: *Self, client: *const Client) void {
    while (self.running.load(.monotonic) and client.open.load(.monotonic)) {
        // send necessary game info
        for (self.game_data.players.items) |p| {
            client.send(self.alloc, self.io, .{ .player_state = .init(p) }) catch |err| {
                commons.print("Failed to send message to client: {}", .{err}, .yellow);
                return;
            };
        }

        commons.sleep(self.io, self.settings.polling_rate);
    }
}

/// Deserializes a message and processes it
fn handleMessage(self: *Self, client: *const Client, message_bytes: []const u8) !void {
    var stream = std.Io.Reader.fixed(message_bytes);
    var packet = try s2s.deserializeAlloc(&stream, socket_packet.Packet, self.alloc);
    defer s2s.free(self.alloc, socket_packet.Packet, &packet);

    switch (packet) {
        .client_requests_connect => |client_connect| {
            self.appendPlayer(client_connect) catch |err| switch (err) {
                error.ServerFull => {
                    commons.print(
                        "Client attempted to join from {f}, but the server is full ({}/{})!",
                        .{ client.stream.socket.address, self.game_data.players.items.len, self.game_data.players.capacity },
                        .yellow,
                    );
                    try client.send(self.alloc, self.io, .server_full);
                    return;
                },
                else => return err,
            };

            try client.send(self.alloc, self.io, .{ .server_accepted_client = .init(self.game_data.map.size) });
        },
        .client_requests_map_data => {
            while (!self.mapChunksReady()) {}
            for (self.socket_packets.map_chunks) |c| {
                client.send(self.alloc, self.io, .{ .map_chunk = c }) catch |err| {
                    commons.print("Failed to send message to client: {}", .{err}, .yellow);
                    return;
                };
            }
        },
        .resend_request => @panic("unimplemented"),
        .client_requests_move_player => |move_player| {
            self.game_data.players.items[client.id].position = move_player.new_pos;
        },
        else => return commons.printErr(
            error.IllegalMessage,
            "Illegal message received from client. Has descriptor {s}.",
            .{@tagName(std.meta.activeTag(packet))},
            .yellow,
        ),
    }
}

fn prepareMapChunks(self: *Self) !void {
    // Wait for the main map to finish generating
    while (!self.mapFinishedGenerating()) : (commons.sleep(self.io, 100)) {}

    // Now that the map is ready, generate the network chunks from it.
    try socket_packet.MapChunk.init(
        self.io,
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

    self.threaded = .init(self.alloc, .{ .environ = .empty });
    self.io = self.threaded.io();

    self.settings = settings;

    self.clients = try .initCapacity(self.alloc, self.settings.max_players);
    errdefer self.clients.deinit(self.alloc);

    self.game_data = try GameData.init(self.alloc, self.io, self.settings);
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

    (try std.Thread.spawn(.{}, prepareMapChunks, .{self})).detach();

    const address = try std.Io.net.IpAddress.parseIp4("127.0.0.1", self.settings.port);

    self.server = address.listen(self.io, .{}) catch |err|
        return commons.printErr(
            err,
            "Error initializing server: Couldn't bind to port {}. ({})",
            .{ self.settings.port, err },
            .red,
        );
    errdefer self.server.deinit(self.io);

    self.running = .init(true);

    self.listen_thread = try std.Thread.spawn(.{}, Self.listen, .{self});

    return self;
}

pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
    self.alloc.free(self.socket_packets.map_chunks);

    self.game_data.deinit(self.alloc);
    self.running.store(false, .monotonic);

    self.listen_thread.detach(); // this works for some reason. see thousand yard stare

    for (self.clients.items) |client| {
        client.receive_handler.cancel(self.io) catch |err|
            commons.print(
                "Server error: Could not cancel client receiving handler: {}",
                .{err},
                .red,
            );
        client.send_handler.cancel(self.io);
        self.alloc.destroy(client);
    }

    self.clients.deinit(self.alloc);

    self.server.deinit(self.io);

    self.threaded.deinit();

    _ = self.gpa.deinit();

    alloc.destroy(self);
}

/// Listens for new clients and appends them to `self.clients`
fn listen(self: *Self) !void {
    while (self.running.load(.monotonic)) {
        const sock = self.server.accept(self.io) catch |err| {
            commons.print("Server socket closed: {}. Shutting down...", .{err}, .blue);
            break;
        };

        var client = try self.alloc.create(Client);
        errdefer self.alloc.destroy(client);

        client.* = .{
            .stream = sock,
            .receive_handler = undefined,
            .send_handler = undefined,
            .id = @intCast(self.clients.items.len),
            .open = .init(true),
        };

        client.receive_handler = self.io.async(handleClientReceive, .{ self, client });
        errdefer client.receive_handler.cancel(self.io) catch |err|
            commons.print(
                "Server error: Could not cancel client receiving handler: {}",
                .{err},
                .red,
            );

        client.send_handler = self.io.async(handleClientSend, .{ self, client });
        errdefer client.send_handler.cancel(self.io);

        try self.clients.append(self.alloc, client);

        commons.print("Client connected from {f}.", .{client.stream.socket.address}, .blue);
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

pub fn mapChunksReady(self: *const Self) bool {
    return self.game_data.map.network_chunks_generated.load(.monotonic) ==
        self.socket_packets.map_chunks.len;
}

pub fn mapFinishedGenerating(self: *const Self) bool {
    return self.game_data.map.floats_written.load(.monotonic) ==
        self.game_data.map.height_map.len;
}
