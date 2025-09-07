//! TCP server struct
const std = @import("std");
const builtin = @import("builtin");
const network = @import("network");

const ServerGameData = @import("ServerGameData.zig");
const Settings = @import("Settings.zig");
const SocketPacket = @import("SocketPacket.zig");

const Self = @This();

_gpa: std.heap.GeneralPurposeAllocator(.{}),
alloc: std.mem.Allocator,
sock: network.Socket,
clients: std.ArrayList(*Client),
listen_thread: std.Thread,
running: std.atomic.Value(bool),
game_data: ServerGameData,
world_data_chunks: []SocketPacket.WorldDataChunk,

const Client = struct {
    sock: network.Socket,
    handle_thread: std.Thread,

    pub fn send(self: *Client, alloc: std.mem.Allocator, message: []const u8) !void {
        const message_newline = try std.fmt.allocPrint(alloc, "{s}\n", .{message});
        defer alloc.free(message_newline);
        _ = self.sock.send(message_newline) catch |err| {
            std.debug.print("Couldn't send: {}. Trying again in 200 ms...\n", .{err});
            std.Thread.sleep(200 * std.time.ns_per_ms); // sleep for 200 ms
            try self.send(alloc, message); // try again
        };
    }
};

fn handleClient(
    self: *Self,
    client: *Client,
) !void {
    defer client.sock.close();

    var buf_: [64]u8 = undefined;
    var writer = client.sock.writer(&buf_);
    try writer.interface.writeAll("server: welcome to server!!!!!\n");

    var buf: []u8 = try self.alloc.alloc(u8, 65535);
    defer self.alloc.free(buf);

    while (self.running.load(.monotonic)) {
        const bytes_read = client.sock.receive(buf) catch |err| switch (err) {
            error.WouldBlock => continue,
            error.ConnectionResetByPeer => {
                self.running.store(false, .monotonic);
                std.debug.print("Socket disconnected\n", .{});
                return;
            },
            else => {
                std.debug.print("Couldn't read from socket: {}\n", .{err});
                return err;
            },
        };

        if (bytes_read == 0) break;

        const message = buf[0..bytes_read];
        std.debug.print("Client wrote: {s}\n", .{message});

        try self.handleMessage(client, message);
    }

    std.debug.print("Client disconnected.\n", .{});
}

/// Parses, handles and responds to message accordingly
fn handleMessage(self: *Self, client: *Client, message: []u8) !void {
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

                    std.debug.print("Server received message with descriptor {s}\n", .{descriptor});
                    if (std.mem.eql(u8, descriptor, "client_connect")) {
                        const request_parsed = try std.json.parseFromValue(
                            SocketPacket.ClientConnect,
                            self.alloc,
                            message_root,
                            .{},
                        );
                        defer request_parsed.deinit();

                        const connect_request: SocketPacket.ClientConnect = request_parsed.value;
                        try self.game_data.players.append(self.alloc, ServerGameData.Player.init(connect_request.nickname));

                        // Send response to this specific client
                        for (self.world_data_chunks) |chunk| {
                            const world_data_string = try std.json.Stringify.valueAlloc(self.alloc, chunk, .{});
                            defer self.alloc.free(world_data_string);

                            try client.send(self.alloc, world_data_string);
                        }
                    } else if (std.mem.eql(u8, descriptor, "resend_request")) {
                        const request_parsed = try std.json.parseFromValue(
                            SocketPacket.ResendRequest,
                            self.alloc,
                            message_root,
                            .{},
                        );
                        defer request_parsed.deinit();

                        const resend_request: SocketPacket.ResendRequest = request_parsed.value;
                        if (std.mem.startsWith(u8, resend_request.body, "world_data_chunk-")) {
                            var split = std.mem.splitAny(u8, resend_request.body, "-");
                            split.index = 1;
                            const chunk_index = try std.fmt.parseInt(u32, split.next().?, 10);
                            std.debug.print("chunk index: {}\n", .{chunk_index});

                            const chunk = self.world_data_chunks[chunk_index];
                            const world_data_string = try std.json.Stringify.valueAlloc(self.alloc, chunk, .{});
                            defer self.alloc.free(world_data_string);
                            try client.send(self.alloc, world_data_string);
                        }
                    }
                }
            }
        },
        else => {},
    }
}

pub fn init(alloc: std.mem.Allocator, st: *const Settings) !*Self {
    var self: *Self = try alloc.create(Self);

    self._gpa = .init;
    self.alloc = self._gpa.allocator();
    self.clients = try std.ArrayList(*Client).initCapacity(self.alloc, 8);
    self.game_data = try ServerGameData.init(self.alloc, st);
    self.world_data_chunks = try SocketPacket.WorldDataChunk.init(self.alloc, self.game_data.world_data);

    try network.init();
    self.sock = try network.Socket.create(.ipv4, .tcp);

    try self.sock.bindToPort(st.multiplayer.server_port);

    try self.sock.listen();

    self.running = std.atomic.Value(bool).init(true);

    self.listen_thread = try std.Thread.spawn(.{}, Self.listen, .{self});

    try self.sock.setReadTimeout(2000 * 1000);

    return self;
}

pub fn deinit(self: *Self) void {
    for (self.world_data_chunks) |chunk|
        self.alloc.free(chunk.descriptor);
    self.alloc.free(self.world_data_chunks);

    self.game_data.deinit(self.alloc);
    self.running.store(false, .monotonic);

    self.listen_thread.detach(); // this works for some reason. see thousand yard stare

    for (self.clients.items) |client| {
        client.handle_thread.join();
        self.alloc.destroy(client);
    }

    self.clients.deinit(self.alloc);

    self.sock.close();

    network.deinit();

    _ = self._gpa.deinit();
}

fn listen(self: *Self) !void {
    while (self.running.load(.monotonic)) {
        if (self.sock.accept()) |sock| {
            var client: *Client = try self.alloc.create(Client);
            client.sock = sock;
            client.handle_thread = try std.Thread.spawn(.{}, handleClient, .{ self, client });

            try self.clients.append(self.alloc, client);

            std.debug.print("Client connected from {f}.\n", .{try client.sock.getLocalEndPoint()});
        } else |err| switch (err) {
            error.WouldBlock => {},
            error.ConnectionAborted => {},
            else => {
                std.debug.print("Server socket closed, shutting down...\n", .{});
                break;
            },
        }
    }
}
