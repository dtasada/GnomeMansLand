//! TCP server struct
const std = @import("std");
const builtin = @import("builtin");
const network = @import("network");

const socket_packet = @import("socket_packet");

const commons = @import("commons");

pub const GameData = @import("GameData.zig");

const ServerSettings = commons.ServerSettings;

const Self = @This();

var polling_rate: u64 = undefined;

gpa: std.heap.DebugAllocator(.{}),
tsa: std.heap.ThreadSafeAllocator,
alloc: std.mem.Allocator,

//// The network socket itself.
sock: network.Socket,

/// Arraylist of pointers to all the client objects.
clients: std.ArrayList(*Client),

/// Thread that runs `listen`
listen_thread: std.Thread,

/// Atomic boolean identifying whether the server is running or not.
running: std.atomic.Value(bool),

/// Contains internal server game data.
game_data: GameData,

/// Contains internal configuration.
settings: ServerSettings,

/// Contains cached data to be sent to clients.
socket_packets: struct {
    world_data_chunks: []socket_packet.WorldDataChunk,
},

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

    /// Appends a newline sentinel to `message` and sends it to the client. Blocking
    pub fn send(self: *const Client, alloc: std.mem.Allocator, message: []const u8) !void {
        const message_newline = try std.fmt.allocPrint(alloc, "{s}\n", .{message});
        defer alloc.free(message_newline);

        while (true) {
            _ = self.sock.send(message_newline) catch |err| switch (err) {
                error.WouldBlock => {
                    std.Thread.sleep(polling_rate * std.time.ns_per_ms);
                    continue;
                },
                error.ConnectionResetByPeer, error.BrokenPipe => break, // caller decides to stop
                else => return err,
            };
            break;
        }
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

    var buf: []u8 = try self.alloc.alloc(u8, 65535);
    defer self.alloc.free(buf);

    while (self.running.load(.monotonic)) : (std.Thread.sleep(polling_rate * std.time.ns_per_ms)) {
        const bytes_read = client.sock.receive(buf) catch |err| switch (err) {
            error.WouldBlock => continue,
            error.ConnectionResetByPeer => {
                commons.print(
                    "Socket disconnected: {}\n",
                    .{err},
                    .blue,
                );
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

        const message = buf[0..bytes_read];

        // handle current message
        try self.handleMessage(client, message);
    }

    _ = self.clients.orderedRemove(client.id);
    commons.print("Client disconnected.\n", .{}, .blue);
}

/// Continuously sends all necessary game info to `client`. Blocking.
fn handleClientSend(self: *const Self, client: *const Client) !void {
    loop: while (self.running.load(.monotonic) and client.open.load(.monotonic)) : (std.Thread.sleep(polling_rate * std.time.ns_per_ms)) {
        // send necessary game info
        for (self.game_data.players.items) |p| {
            const player_packet = socket_packet.Player.init(p);
            const player_string = std.json.Stringify.valueAlloc(self.alloc, player_packet, .{}) catch |err|
                return commons.printErr(
                    err,
                    "Could not stringify packet: {}\n",
                    .{err},
                    .red,
                );

            defer self.alloc.free(player_string);

            client.send(self.alloc, player_string) catch |err| switch (err) {
                error.ConnectionResetByPeer, error.BrokenPipe => break :loop,
                else => return err,
            };
        }
    }
}

/// Parses the message and calls `processMessage`.
fn handleMessage(self: *Self, client: *const Client, message: []u8) !void {
    if (!self.running.load(.monotonic) or !client.open.load(.monotonic)) return;

    const message_parsed: std.json.Parsed(std.json.Value) = try std.json.parseFromSlice(
        std.json.Value,
        self.alloc,
        message,
        .{},
    );
    defer message_parsed.deinit();

    const message_root = message_parsed.value;
    switch (message_root) {
        .object => |object| try self.processMessage(
            client,
            message_root,
            try commons.getDescriptor(object, .client),
        ),
        else => return commons.printErr(
            error.InvalidMessage,
            "Received invalid message from server! JSON package must be an object.",
            .{},
            .yellow,
        ),
    }
}

/// Actually processes message and responds accordingly.
fn processMessage(
    self: *Self,
    client: *const Client,
    message_root: std.json.Value,
    descriptor: socket_packet.Descriptor,
) !void {
    switch (descriptor) {
        .client_connect => {
            const request_parsed = try std.json.parseFromValue(
                socket_packet.ClientConnect,
                self.alloc,
                message_root,
                .{},
            );
            defer request_parsed.deinit();

            self.appendPlayer(request_parsed.value) catch {
                const server_full = try std.json.Stringify.valueAlloc(self.alloc, socket_packet.ServerFull{}, .{});
                defer self.alloc.free(server_full);
                try client.send(self.alloc, server_full);
                return;
            };

            // Send world data to the client
            if (self.game_data.world_data.network_chunks_ready.load(.monotonic))
                for (self.socket_packets.world_data_chunks) |c| {
                    const world_data_string = try std.json.Stringify.valueAlloc(self.alloc, c, .{});
                    defer self.alloc.free(world_data_string);

                    try client.send(self.alloc, world_data_string);
                };
        },
        .resend_request => {
            const request_parsed = try std.json.parseFromValue(
                socket_packet.ResendRequest,
                self.alloc,
                message_root,
                .{},
            );
            defer request_parsed.deinit();

            const resend_request: socket_packet.ResendRequest = request_parsed.value;
            if (std.mem.startsWith(u8, resend_request.body, "world_data_chunk-")) {
                var split = std.mem.splitAny(u8, resend_request.body, "-");
                split.index = 1;
                const chunk_index = try std.fmt.parseInt(u32, split.next().?, 10);

                const world_data_string = try std.json.Stringify.valueAlloc(self.alloc, self.socket_packets.world_data_chunks[chunk_index], .{});
                defer self.alloc.free(world_data_string);

                try client.send(self.alloc, world_data_string);
            }
        },
        .move_player => {
            const request_parsed = try std.json.parseFromValue(socket_packet.MovePlayer, self.alloc, message_root, .{});
            defer request_parsed.deinit();

            self.game_data.players.items[client.id].position = request_parsed.value.new_pos;
        },
        else => {
            commons.print("Illegal message received from client. Has descriptor {s}.\n", .{@tagName(descriptor)}, .yellow);
            return error.IllegalMessage;
        },
    }
}

/// `game_data` and `socket_packets.world_data_chunks` are populated asynchronously
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
        .world_data_chunks = try self.alloc.alloc(
            socket_packet.WorldDataChunk,
            @divFloor(
                self.game_data.world_data.height_map.len,
                socket_packet.WorldDataChunk.FLOATS_PER_CHUNK,
            ) + @intFromBool(
                self.game_data.world_data.height_map.len %
                    socket_packet.WorldDataChunk.FLOATS_PER_CHUNK != 0,
            ),
        ),
    };
    errdefer self.alloc.free(self.socket_packets.world_data_chunks);

    polling_rate = self.settings.polling_rate;

    try network.init();
    errdefer network.deinit();

    self.sock = try network.Socket.create(.ipv4, .tcp);
    errdefer self.sock.close();

    self.sock.bindToPort(self.settings.port) catch |err|
        return commons.printErr(
            err,
            "Error initializing server: Couldn't bind to port {}. ({})",
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
    self.alloc.free(self.socket_packets.world_data_chunks);

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
    while (self.running.load(.monotonic)) {
        const sock = self.sock.accept() catch |err| switch (err) {
            error.WouldBlock, error.ConnectionAborted => continue,
            else => {
                commons.print("Server socket closed, shutting down...\n", .{}, .blue);
                break;
            },
        };

        var client: *Client = try self.alloc.create(Client);
        errdefer self.alloc.destroy(client);

        client.* = .{
            .sock = sock,
            .thread_handle_receive = try std.Thread.spawn(.{}, handleClientReceive, .{ self, client }),
            .thread_handle_send = try std.Thread.spawn(.{}, handleClientSend, .{ self, client }),
            .id = @intCast(self.clients.items.len),
            .open = .init(true),
        };

        try self.clients.append(self.alloc, client);

        commons.print("Client connected from {f}.\n", .{try client.sock.getLocalEndPoint()}, .blue);
    }
}

/// Appends a player to
fn appendPlayer(self: *Self, connect_request: socket_packet.ClientConnect) !void {
    try self.game_data.players.appendBounded(GameData.Player.init(
        @intCast(self.game_data.players.items.len),
        try self.alloc.dupe(u8, connect_request.nickname), // duplicate nickname bc threads
    ));
}
