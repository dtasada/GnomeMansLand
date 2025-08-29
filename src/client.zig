const std = @import("std");
const Settings = @import("settings.zig");

const Self = @This();

sockfd: std.posix.socket_t,
serverAddress: std.net.Address,
open: bool,
queue: std.ArrayList([]const u8),
listen_thread: std.Thread,
alloc: std.mem.Allocator,
_gpa: std.heap.GeneralPurposeAllocator(.{}),

pub fn init(st: *const Settings) !Self {
    var self: Self = undefined;

    self._gpa = std.heap.GeneralPurposeAllocator(.{}){};
    self.alloc = self._gpa.allocator();

    // Create UDP socket
    self.serverAddress = try std.net.Address.parseIp(st.multiplayer.server_host, st.multiplayer.server_port);
    self.sockfd = try std.posix.socket(self.serverAddress.any.family, std.posix.SOCK.DGRAM, 0);
    self.open = true;
    self.queue = try std.ArrayList([]const u8).initCapacity(self.alloc, 64);

    std.debug.print("UDP Client connecting to {f}\n", .{self.serverAddress});

    try self.sendMessage("Hello from Zig UDP client!");
    self.listen_thread = try std.Thread.spawn(.{}, Self.listen, .{&self});

    return self;
}

pub fn deinit(self: *Self) void {
    self.open = false;
    self.listen_thread.join();

    for (self.queue.items) |msg|
        self.alloc.free(msg);

    self.queue.deinit(self.alloc);
    std.posix.close(self.sockfd);

    _ = self._gpa.deinit();

    std.debug.print("Deinitialized client.", .{});
}

pub fn sendMessage(self: *Self, message: []const u8) !void {
    // Send message to server
    _ = try std.posix.sendto(
        self.sockfd,
        message,
        0,
        @ptrCast(&self.serverAddress.any),
        self.serverAddress.getOsSockLen(),
    );
    std.debug.print("Sent: {s}\n", .{message});
}

pub fn receiveMessage(self: *const Self) ![]u8 {
    // Receive response from server
    var buffer: [1024]u8 = undefined;
    var from_address: std.net.Address = undefined;
    var from_address_len: std.posix.socklen_t = @sizeOf(std.net.Address);

    const bytes_received = std.posix.recvfrom(
        self.sockfd,
        buffer[0..],
        0,
        @ptrCast(&from_address.any),
        &from_address_len,
    ) catch |err| switch (err) {
        error.WouldBlock => return error.NoDataAvailable,
        error.SocketNotConnected => return error.SocketClosed,
        else => return err,
    };

    if (bytes_received == 0) {
        std.debug.print("No response received\n", .{});
        return error.NoDataAvailable;
    }

    return try self.alloc.dupe(u8, buffer[0..bytes_received]);
}

pub fn listen(self: *Self) !void {
    while (self.open) {
        try self.queue.append(self.alloc, try self.receiveMessage());
    }
}
