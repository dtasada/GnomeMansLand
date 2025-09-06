//! TCP server struct
const std = @import("std");
const builtin = @import("builtin");

const ServerGameData = @import("ServerGameData.zig");
const Settings = @import("Settings.zig");
const SocketPacket = @import("SocketPacket.zig");

const Self = @This();

sockfd: std.posix.socket_t,
server_address: std.net.Address,
open: std.atomic.Value(bool),
listen_thread: std.Thread,
alloc: std.mem.Allocator,
_gpa: std.heap.GeneralPurposeAllocator(.{}),
polling_interval: u64,
game_data: ServerGameData,

clients: std.ArrayList(ClientConnection),
next_client_id: u32,

const ClientConnection = struct {
    stream: std.net.Stream,
    address: std.net.Address,
    id: u32,
    // Buffer for accumulating incoming data per client
    receive_buffer: std.ArrayList(u8),
    expected_message_length: ?u32,
};

pub fn init(alloc: std.mem.Allocator, st: *const Settings) !*Self {
    var self: *Self = try alloc.create(Self);

    // Create TCP socket
    self.polling_interval = st.multiplayer.server_polling_interval;
    self.server_address = try std.net.Address.parseIp(st.multiplayer.server_host, st.multiplayer.server_port);
    self.sockfd = try std.posix.socket(
        self.server_address.any.family,
        std.posix.SOCK.STREAM,
        std.posix.IPPROTO.TCP,
    );

    self._gpa = .init;
    self.alloc = self._gpa.allocator();

    // Allow address reuse
    try std.posix.setsockopt(
        self.sockfd,
        std.posix.SOL.SOCKET,
        std.posix.SO.REUSEADDR,
        &std.mem.toBytes(@as(c_int, 1)),
    );

    // Bind socket to address
    try std.posix.bind(self.sockfd, &self.server_address.any, self.server_address.getOsSockLen());

    try std.posix.listen(self.sockfd, 8);

    self.open = std.atomic.Value(bool).init(true);
    self.game_data = try ServerGameData.init(self.alloc, st);

    self.clients = try std.ArrayList(ClientConnection).initCapacity(self.alloc, 8);
    self.next_client_id = 0;

    try setNonBlocking(self.sockfd);
    // Set timeout for the server socket
    try setSocketTimeout(self.sockfd, @intCast(self.polling_interval));

    self.listen_thread = try std.Thread.spawn(.{}, Self.listen, .{self});

    return self;
}

pub fn deinit(self: *Self) void {
    std.debug.print("Deinitializing server...\n", .{});

    // Signal thread to stop
    self.open.store(false, .monotonic);

    // Force close the server socket to unblock accept() if it's waiting
    // This will cause accept() to return an error and exit the loop
    std.posix.close(self.sockfd);

    // Wait for listen thread to finish
    self.listen_thread.join();

    // Clean up all clients
    for (self.clients.items) |*client| {
        client.stream.close();
        client.receive_buffer.deinit(self.alloc);
    }
    self.clients.deinit(self.alloc);

    self.game_data.deinit(self.alloc);
    // sockfd already closed above
    _ = self._gpa.deinit();

    std.debug.print("Deinitialized server\n", .{});
}

fn setNonBlocking(sockfd: std.posix.socket_t) !void {
    switch (builtin.os.tag) {
        .windows => {
            var nonblocking: c_ulong = 1;
            const result = std.os.windows.ws2_32.ioctlsocket(
                sockfd,
                std.os.windows.ws2_32.FIONBIO,
                &nonblocking,
            );
            if (result != 0) return error.SetNonBlockingFailed;
        },
        else => {
            const flags = try std.posix.fcntl(sockfd, std.posix.F.GETFL, 0);
            _ = try std.posix.fcntl(
                sockfd,
                std.posix.F.SETFL,
                flags | std.posix.SOCK.NONBLOCK,
            );
        },
    }
}

fn setSocketTimeout(sockfd: std.posix.socket_t, timeout_ms: u32) !void {
    const timeout = std.posix.timeval{
        .sec = @intCast(timeout_ms / 1000),
        .usec = @intCast((timeout_ms % 1000) * 1000),
    };

    // Set both receive and send timeouts
    try std.posix.setsockopt(
        sockfd,
        std.posix.SOL.SOCKET,
        std.posix.SO.RCVTIMEO,
        std.mem.asBytes(&timeout),
    );

    try std.posix.setsockopt(
        sockfd,
        std.posix.SOL.SOCKET,
        std.posix.SO.SNDTIMEO,
        std.mem.asBytes(&timeout),
    );
}

fn acceptNewClient(self: *Self) !void {
    var client_address: std.net.Address = undefined;
    var client_address_len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr);

    const client_sockfd = std.posix.accept(
        self.sockfd,
        @ptrCast(&client_address.any),
        &client_address_len,
        0,
    ) catch |err| switch (err) {
        error.WouldBlock => return err, // No pending connections
        // Most other errors during shutdown indicate the socket was closed
        error.FileDescriptorNotASocket, error.SocketNotListening, error.OperationNotSupported => {
            return error.ServerShuttingDown;
        },
        error.ConnectionAborted => return err,
        else => {
            std.debug.print("Unexpected accept error: {}\n", .{err});
            return error.ServerShuttingDown;
        },
    };

    // Set the client socket to non-blocking and with timeout
    try setNonBlocking(client_sockfd);
    try setSocketTimeout(client_sockfd, @intCast(self.polling_interval));

    const client = ClientConnection{
        .stream = .{ .handle = client_sockfd },
        .address = client_address,
        .id = self.next_client_id,
        .receive_buffer = try std.ArrayList(u8).initCapacity(self.alloc, 8),
        .expected_message_length = null,
    };

    try self.clients.append(self.alloc, client);
    self.next_client_id += 1;

    std.debug.print("New client {} connected from {f}\n", .{ client.id, client.address });
}

// Non-blocking receive for a specific client
fn receiveDataFromClient(self: *Self, client: *ClientConnection) !?[]u8 {
    var temp_buffer: [4096]u8 = undefined;

    // Try to read data without blocking
    const bytes_read = client.stream.read(temp_buffer[0..]) catch |err| switch (err) {
        error.WouldBlock => return null, // No data available right now
        error.ConnectionResetByPeer, error.BrokenPipe => return error.ClientDisconnected,
        else => return err,
    };

    if (bytes_read == 0) return error.ClientDisconnected;

    // Add received data to client's buffer
    try client.receive_buffer.appendSlice(self.alloc, temp_buffer[0..bytes_read]);

    // Try to extract complete messages
    while (true) {
        // If we don't know the expected length, try to read it
        if (client.expected_message_length == null) {
            if (client.receive_buffer.items.len < 4) {
                return null; // Need more data for length header
            }

            // Extract length from first 4 bytes
            const len_bytes = client.receive_buffer.items[0..4];
            client.expected_message_length = std.mem.bytesToValue(u32, len_bytes);

            // Sanity check
            if (client.expected_message_length.? == 0) return error.EmptyMessage;
            if (client.expected_message_length.? > 1024 * 1024) return error.MessageTooLarge;

            // Remove length header from buffer
            std.mem.copyForwards(u8, client.receive_buffer.items, client.receive_buffer.items[4..]);
            client.receive_buffer.shrinkRetainingCapacity(client.receive_buffer.items.len - 4);
        }

        // Check if we have a complete message
        if (client.receive_buffer.items.len >= client.expected_message_length.?) {
            const msg_len = client.expected_message_length.?;

            // Extract the complete message
            const message = try self.alloc.dupe(u8, client.receive_buffer.items[0..msg_len]);

            // Remove processed message from buffer
            std.mem.copyForwards(u8, client.receive_buffer.items, client.receive_buffer.items[msg_len..]);
            client.receive_buffer.shrinkRetainingCapacity(client.receive_buffer.items.len - msg_len);

            // Reset expected length for next message
            client.expected_message_length = null;

            return message;
        } else {
            return null; // Need more data for complete message
        }
    }
}

fn handleClientMessage(self: *Self, client_idx: usize, message: []const u8) !void {
    const client = &self.clients.items[client_idx];

    std.debug.print("Received from client {}: {s}\n", .{ client.id, message });

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
                        const world_data_chunks = try SocketPacket.WorldDataChunk.init(self.alloc, self.game_data.world_data);
                        defer self.alloc.free(world_data_chunks);

                        for (0..world_data_chunks.len) |i| {
                            const world_data_string = try std.json.Stringify.valueAlloc(self.alloc, world_data_chunks[i], .{});
                            defer self.alloc.free(world_data_string);
                            std.debug.print("Server: world data chunk length: {}\n", .{world_data_string.len});
                            try self.sendMessageToClient(client_idx, world_data_string);
                        }
                    }
                }
            }
        },
        else => {},
    }
}

fn sendMessageToClient(self: *Self, client_idx: usize, message: []const u8) !void {
    const client = &self.clients.items[client_idx];

    // Send message length first (4 bytes), then message
    const msg_len: u32 = @intCast(message.len);
    const len_bytes = std.mem.asBytes(&msg_len);

    _ = client.stream.write(len_bytes) catch |err| {
        std.debug.print("Failed to send length to client {}: {}\n", .{ client.id, err });
        return err;
    };

    _ = client.stream.write(message) catch |err| {
        std.debug.print("Failed to send message to client {}: {}\n", .{ client.id, err });
        return err;
    };

    // std.debug.print("Sent to client {}: {s}\n", .{ client.id, message });
}

pub fn listen(self: *Self) !void {
    std.debug.print("TCP Server listening on {f}\n", .{self.server_address});

    while (self.open.load(.monotonic)) {
        // Accept new connections (non-blocking)
        self.acceptNewClient() catch |err| switch (err) {
            error.WouldBlock => {}, // No pending connections, continue
            error.ConnectionAborted => {},
            error.ServerShuttingDown => {
                std.debug.print("Server socket closed, shutting down...\n", .{});
                break;
            },
            else => {
                std.debug.print("Accept error: {}\n", .{err});
            },
        };
        std.debug.print("Server continuing after accepting client...\n", .{});

        // Handle messages from existing clients
        var i: usize = 0;
        while (i < self.clients.items.len) {
            var client = &self.clients.items[i];

            if (self.receiveDataFromClient(client)) |message_opt| {
                if (message_opt) |message| {
                    defer self.alloc.free(message);

                    // Handle the message
                    self.handleClientMessage(i, message) catch |err| {
                        std.debug.print("Error handling message from client {}: {}\n", .{ client.id, err });
                    };
                }
                i += 1;
            } else |err| switch (err) {
                error.ClientDisconnected => {
                    std.debug.print("Client {} disconnected\n", .{client.id});
                    client.stream.close();
                    client.receive_buffer.deinit(self.alloc);
                    _ = self.clients.swapRemove(i);
                    // Don't increment i, we removed an item
                },
                else => {
                    std.debug.print("Error receiving from client {}: {}\n", .{ client.id, err });
                    i += 1;
                },
            }
        }

        // Brief sleep to avoid busy waiting when no clients or activity
        std.Thread.sleep(self.polling_interval * std.time.ns_per_ms);
    }

    std.debug.print("Server listen thread ending\n", .{});
}
