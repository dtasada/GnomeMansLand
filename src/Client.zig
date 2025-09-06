//! Local client handler struct
const std = @import("std");
const builtin = @import("builtin");

const ClientGameData = @import("ClientGameData.zig");
const Settings = @import("Settings.zig");
const SocketPacket = @import("SocketPacket.zig");

const Self = @This();

stream: std.net.Stream,
serverAddress: std.net.Address,
open: std.atomic.Value(bool),
listen_thread: std.Thread,
alloc: std.mem.Allocator,
_gpa: std.heap.GeneralPurposeAllocator(.{}),
polling_interval: u64,
game_data: ClientGameData,
// Buffer for accumulating incoming data
receive_buffer: std.ArrayList(u8),
expected_message_length: ?u32,

pub fn init(alloc: std.mem.Allocator, st: *const Settings, connect_message: SocketPacket.ClientConnect) !*Self {
    var self: *Self = try alloc.create(Self);

    self._gpa = .init;
    self.alloc = self._gpa.allocator();
    self.polling_interval = st.multiplayer.server_polling_interval;

    // Create TCP socket and connect
    self.serverAddress = try std.net.Address.parseIp(st.multiplayer.server_host, st.multiplayer.server_port);
    self.stream = try std.net.tcpConnectToAddress(self.serverAddress);

    // Make socket non-blocking
    try setNonBlocking(self.stream.handle);
    try setSocketTimeout(self.stream.handle, @intCast(self.polling_interval));

    self.open = std.atomic.Value(bool).init(true);
    self.game_data = try ClientGameData.init(self.alloc);
    self.receive_buffer = try std.ArrayList(u8).initCapacity(self.alloc, 4096);
    self.expected_message_length = null;

    std.debug.print("TCP Client connected to {f}\n", .{self.serverAddress});
    self.listen_thread = try std.Thread.spawn(.{}, Self.listen, .{self});

    const connect_message_string = try std.json.Stringify.valueAlloc(self.alloc, connect_message, .{});
    defer self.alloc.free(connect_message_string);
    try self.sendMessage(connect_message_string);

    return self;
}

pub fn deinit(self: *Self) void {
    std.debug.print("Deinitializing client...\n", .{});

    // Signal thread to stop
    self.open.store(false, .monotonic);

    // Give the thread a moment to notice the signal
    self.listen_thread.join();

    self.stream.close();
    self.receive_buffer.deinit(self.alloc);
    self.game_data.deinit(self.alloc);
    _ = self._gpa.deinit();

    std.debug.print("Deinitialized client.\n", .{});
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

    try std.posix.setsockopt(
        sockfd,
        std.posix.SOL.SOCKET,
        std.posix.SO.RCVTIMEO,
        std.mem.asBytes(&timeout),
    );
}

pub fn sendMessage(self: *Self, message: []const u8) !void {
    // Send message length first (4 bytes), then message
    const msg_len: u32 = @intCast(message.len);
    const len_bytes = std.mem.asBytes(&msg_len);

    // Use direct socket write for non-blocking behavior
    _ = try self.stream.write(len_bytes);
    _ = try self.stream.write(message);

    std.debug.print("Client sent: {s}\n", .{message});
}

// Non-blocking receive using direct socket operations
fn receive(self: *Self) !?[]u8 {
    var temp_buffer: []u8 = try self.alloc.alloc(u8, 65535);
    defer self.alloc.free(temp_buffer);

    // Try to read data without blocking
    const bytes_read = self.stream.read(temp_buffer[0..]) catch |err| switch (err) {
        error.WouldBlock => return null, // No data available right now
        error.ConnectionResetByPeer, error.BrokenPipe => return error.ServerDisconnected,
        else => return err,
    };

    if (bytes_read == 0) return error.ServerDisconnected;

    // Add received data to our buffer
    try self.receive_buffer.appendSlice(self.alloc, temp_buffer[0..bytes_read]);

    // Try to extract complete messages
    while (true) {
        // If we don't know the expected length, try to read it
        if (self.expected_message_length == null) {
            if (self.receive_buffer.items.len < 4) {
                return null; // Need more data for length header
            }

            // Extract length from first 4 bytes
            const len_bytes = self.receive_buffer.items[0..4];
            self.expected_message_length = std.mem.bytesToValue(u32, len_bytes);

            // Sanity check
            if (self.expected_message_length.? == 0) return error.EmptyMessage;
            if (self.expected_message_length.? > 1024 * 1024) return error.MessageTooLarge;

            // Remove length header from buffer
            std.mem.copyForwards(u8, self.receive_buffer.items, self.receive_buffer.items[4..]);
            self.receive_buffer.shrinkRetainingCapacity(self.receive_buffer.items.len - 4);
        }

        // Check if we have a complete message
        if (self.receive_buffer.items.len >= self.expected_message_length.?) {
            const msg_len = self.expected_message_length.?;

            // Extract the complete message
            const message = try self.alloc.dupe(u8, self.receive_buffer.items[0..msg_len]);

            // Remove processed message from buffer
            std.mem.copyForwards(u8, self.receive_buffer.items, self.receive_buffer.items[msg_len..]);
            self.receive_buffer.shrinkRetainingCapacity(self.receive_buffer.items.len - msg_len);

            // Reset expected length for next message
            self.expected_message_length = null;

            return message;
        } else {
            return null; // Need more data for complete message
        }
    }
}

pub fn listen(self: *Self) !void {
    std.debug.print("TCP Client listening (non-blocking)...\n", .{});

    while (self.open.load(.monotonic)) {
        // Try to receive a message without blocking
        if (self.receive()) |message_opt| {
            if (message_opt) |message| {
                defer self.alloc.free(message);
                try self.processMessage(message);
            }
        } else |err| switch (err) {
            error.ServerDisconnected => {
                std.debug.print("Server disconnected\n", .{});
                self.open.store(false, .monotonic);
                break;
            },
            else => {
                std.debug.print("Receive error: {}\n", .{err});
            },
        }

        // Sleep briefly to avoid busy waiting
        std.Thread.sleep(self.polling_interval * std.time.ns_per_ms);
    }

    std.debug.print("TCP Client listen thread exiting...\n", .{});
}

fn processMessage(self: *Self, message: []const u8) !void {
    // Safely print message - check if it's valid UTF-8 first
    if (std.unicode.utf8ValidateSlice(message)) {
        // std.debug.print("message received from server: {s}\n", .{message});
    } else {
        std.debug.print("message received from server (binary/invalid UTF-8): {} bytes\n", .{message.len});
    }

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
                    std.debug.print("Client received message with descriptor {s}\n", .{descriptor});

                    if (std.mem.eql(u8, descriptor, "world_data_chunk")) {
                        const request_parsed = try std.json.parseFromValue(SocketPacket.WorldDataChunk, self.alloc, message_root, .{});
                        defer request_parsed.deinit();

                        const world_data_chunk: SocketPacket.WorldDataChunk = request_parsed.value;
                        if (self.game_data.world_data) |*world_data| {
                            std.debug.print("Client: adding chunk\n", .{});
                            world_data.addChunk(world_data_chunk);
                        } else {
                            std.debug.print("Client: Initializing world_data\n", .{});
                            self.game_data.world_data = try ClientGameData.WorldData.init(self.alloc, world_data_chunk);
                        }
                    }
                }
            }
        },
        else => {},
    }
}

// Alternative approach using polling with select/poll
pub fn listenWithPolling(self: *Self) !void {
    std.debug.print("TCP Client listening with polling...\n", .{});

    while (self.open.load(.monotonic)) {
        // Use poll to check if data is available
        var poll_fds = [_]std.posix.pollfd{
            .{
                .fd = self.stream.handle,
                .events = std.posix.POLL.IN,
                .revents = 0,
            },
        };

        // Poll with a timeout to allow checking self.open periodically
        const poll_result = std.posix.poll(&poll_fds, @intCast(self.polling_interval)) catch |err| {
            std.debug.print("Poll error: {}\n", .{err});
            return err;
        };

        if (poll_result > 0 and (poll_fds[0].revents & std.posix.POLL.IN) != 0) {
            // Data is available, try to read it
            if (self.receive()) |message_opt| {
                if (message_opt) |message| {
                    defer self.alloc.free(message);
                    try self.processMessage(message);
                }
            } else |err| switch (err) {
                error.ServerDisconnected => {
                    std.debug.print("Server disconnected\n", .{});
                    self.open.store(false, .monotonic);
                    break;
                },
                else => {
                    std.debug.print("Receive error: {}\n", .{err});
                },
            }
        }
        // If poll_result == 0, it was a timeout, which is fine - just continue the loop
    }

    std.debug.print("TCP Client listen thread exiting...\n", .{});
}
