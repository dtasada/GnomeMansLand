//! TCP server struct
const std = @import("std");
const builtin = @import("builtin");
const network = @import("network");

const socket_packet = @import("socket_packet");

const commons = @import("commons");

pub const GameData = @import("GameData.zig");
pub const ServerSettings = commons.ServerSettings;

const Self = @This();

var polling_rate: u64 = undefined;

_gpa: std.heap.GeneralPurposeAllocator(.{}),
alloc: std.mem.Allocator,
sock: network.Socket,
clients: std.ArrayList(*Client),
listen_thread: std.Thread,
running: std.atomic.Value(bool),
game_data: GameData,
settings: ServerSettings,

socket_packets: struct {
    world_data_chunks: []?socket_packet.WorldDataChunk,
},

const Client = struct {
    sock: network.Socket,
    thread_handle_receive: std.Thread,
    thread_handle_send: std.Thread,
    id: u32,
    open: std.atomic.Value(bool),

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

fn handleClientReceive(self: *Self, client: *Client) !void {
    defer {
        client.open.store(false, .monotonic);
        client.thread_handle_send.join();
        client.sock.close();
    }

    try client.sock.setReadTimeout(500 * 1000);

    // idk why this was necessary but keeping it in just in case.
    // var buf_: [64]u8 = undefined;
    // var writer = client.sock.writer(&buf_);
    // try writer.interface.writeAll("server: welcome to server!!!!!\n");
    // std.debug.print("buf_ (server.zig:64): {s}\n", .{buf_});

    var buf: []u8 = try self.alloc.alloc(u8, 65535);
    defer self.alloc.free(buf);

    while (self.running.load(.monotonic)) : (std.Thread.sleep(polling_rate * std.time.ns_per_ms)) {
        const bytes_read = client.sock.receive(buf) catch |err| switch (err) {
            error.WouldBlock => continue,
            error.ConnectionResetByPeer => {
                commons.print(
                    "Socket disconnected\n",
                    .{},
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

fn handleClientSend(self: *const Self, client: *Client) !void {
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

/// Parses, handles and responds to message accordingly
fn handleMessage(self: *Self, client: *Client, message: []u8) !void {
    if (!self.running.load(.monotonic) or !client.open.load(.monotonic)) return;

    const message_parsed: std.json.Parsed(std.json.Value) = try std.json.parseFromSlice(std.json.Value, self.alloc, message, .{});
    defer message_parsed.deinit();

    const message_root = message_parsed.value;
    switch (message_root) {
        .object => |object| {
            var it = object.iterator();
            while (it.next()) |entry| {
                const key = entry.key_ptr.*;

                if (std.mem.eql(u8, key, "descriptor")) {
                    const descriptor = entry.value_ptr.*.string;

                    commons.print("Server received message with descriptor {s}\n", .{descriptor}, .blue);
                    if (std.mem.eql(u8, descriptor, "client_connect")) {
                        const request_parsed = try std.json.parseFromValue(
                            socket_packet.ClientConnect,
                            self.alloc,
                            message_root,
                            .{},
                        );
                        defer request_parsed.deinit();

                        try self.appendPlayer(request_parsed.value);

                        // Send world data to the client
                        if (self.game_data.world_data.network_chunks_ready.load(.monotonic))
                            for (self.socket_packets.world_data_chunks) |chunk| if (chunk) |c| {
                                const world_data_string = try std.json.Stringify.valueAlloc(self.alloc, c, .{});
                                defer self.alloc.free(world_data_string);

                                try client.send(self.alloc, world_data_string);
                            };
                    } else if (std.mem.eql(u8, descriptor, "resend_request")) {
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

                            if (self.socket_packets.world_data_chunks[chunk_index]) |chunk| {
                                const world_data_string = try std.json.Stringify.valueAlloc(self.alloc, chunk, .{});
                                defer self.alloc.free(world_data_string);

                                try client.send(self.alloc, world_data_string);
                            }
                        }
                    } else if (std.mem.eql(u8, descriptor, "move_player")) {
                        const request_parsed = try std.json.parseFromValue(socket_packet.MovePlayer, self.alloc, message_root, .{});
                        defer request_parsed.deinit();

                        self.game_data.players.items[client.id].position = request_parsed.value.new_pos;
                    }
                }
            }
        },
        else => {},
    }
}

/// `game_data` and `socket_packets.world_data_chunks` are populated asynchronously
pub fn init(alloc: std.mem.Allocator, settings: ServerSettings) !*Self {
    std.debug.print("1111\n", .{});
    var self = try alloc.create(Self);
    std.debug.print("2\n", .{});
    errdefer alloc.destroy(self);

    self._gpa = .init;
    self.alloc = self._gpa.allocator();
    self.settings = settings;
    self.clients = try .initCapacity(self.alloc, self.settings.max_players);
    errdefer self.clients.deinit(self.alloc);
    std.debug.print("3\n", .{});

    self.game_data = try GameData.init(self.alloc, self.settings);
    errdefer self.game_data.deinit(self.alloc);
    std.debug.print("4\n", .{});

    self.socket_packets = .{
        .world_data_chunks = try self.alloc.alloc(
            ?socket_packet.WorldDataChunk,
            @divFloor(
                self.game_data.world_data.height_map.len,
                socket_packet.WorldDataChunk.FLOATS_PER_CHUNK,
            ) + @intFromBool(
                self.game_data.world_data.height_map.len %
                    socket_packet.WorldDataChunk.FLOATS_PER_CHUNK != 0,
            ),
        ),
    };
    errdefer alloc.free(self.socket_packets.world_data_chunks);
    @memset(self.socket_packets.world_data_chunks, null);

    polling_rate = self.settings.polling_rate;

    try network.init();
    errdefer network.deinit();

    self.sock = try network.Socket.create(.ipv4, .tcp);
    errdefer self.sock.close();

    self.sock.bindToPort(self.settings.port) catch |err| {
        commons.print("Error initializing server: Couldn't bind to port {}. ({})", .{ self.settings.port, err }, .red);
        return err;
    };

    try self.sock.listen();

    self.running = std.atomic.Value(bool).init(true);

    self.listen_thread = try std.Thread.spawn(.{}, Self.listen, .{self});

    try self.sock.setReadTimeout(500 * 1000);

    return self;
}

pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
    for (self.socket_packets.world_data_chunks) |chunk| if (chunk) |c|
        self.alloc.free(c.descriptor);

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

    _ = self._gpa.deinit();

    alloc.destroy(self);
}

fn listen(self: *Self) !void {
    while (self.running.load(.monotonic)) {
        if (self.sock.accept()) |sock| {
            var client: *Client = try self.alloc.create(Client);
            errdefer self.alloc.destroy(client);

            client.* = .{
                .sock = sock,
                .thread_handle_receive = try std.Thread.spawn(.{}, handleClientReceive, .{ self, client }),
                .thread_handle_send = try std.Thread.spawn(.{}, handleClientSend, .{ self, client }),
                .id = @intCast(self.clients.items.len),
                .open = std.atomic.Value(bool).init(true),
            };

            try self.clients.append(self.alloc, client);

            commons.print("Client connected from {f}.\n", .{try client.sock.getLocalEndPoint()}, .blue);
        } else |err| switch (err) {
            error.WouldBlock => {},
            error.ConnectionAborted => {},
            else => {
                commons.print("Server socket closed, shutting down...\n", .{}, .blue);
                break;
            },
        }
    }
}

fn appendPlayer(self: *Self, connect_request: socket_packet.ClientConnect) !void {
    self.game_data.players.appendAssumeCapacity(GameData.Player.init(
        @intCast(self.game_data.players.items.len),
        try self.alloc.dupe(u8, connect_request.nickname), // duplicate nickname bc threads
    ));
}
