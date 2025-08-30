const std = @import("std");
const Settings = @import("Settings.zig");
const LocalGameData = @import("LocalGameData.zig");

const Self = @This();

sockfd: std.posix.socket_t,
serverAddress: std.net.Address,
open: bool,
queue: std.ArrayList([]const u8),
listen_thread: std.Thread,
alloc: std.mem.Allocator,
_gpa: std.heap.GeneralPurposeAllocator(.{}),
polling_interval: u64,
game_data: LocalGameData,

pub fn init(alloc: std.mem.Allocator, st: *const Settings, lgd: LocalGameData) !*Self {
    var self: *Self = try alloc.create(Self);

    self._gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    self.alloc = self._gpa.allocator();
    self.polling_interval = st.multiplayer.server_polling_interval;

    // Create UDP socket
    self.serverAddress = try std.net.Address.parseIp(st.multiplayer.server_host, st.multiplayer.server_port);
    self.sockfd = try std.posix.socket(
        self.serverAddress.any.family,
        std.posix.SOCK.DGRAM | std.posix.SOCK.NONBLOCK,
        std.posix.IPPROTO.UDP,
    );

    const flags = try std.posix.fcntl(self.sockfd, std.posix.F.GETFL, 0);
    _ = try std.posix.fcntl(self.sockfd, std.posix.F.SETFL, flags | std.posix.SOCK.NONBLOCK);

    self.open = true;
    self.queue = try std.ArrayList([]const u8).initCapacity(self.alloc, 64);
    self.game_data = lgd;

    std.debug.print("UDP Client connecting to {f}\n", .{self.serverAddress});

    const message = try std.fmt.allocPrint(
        self.alloc,
        "{{\"connect\": {{\"nickname\":\"{s}\"}}}}",
        .{self.game_data.player.nickname},
    );
    defer self.alloc.free(message);
    try self.sendMessage(message);

    self.listen_thread = try std.Thread.spawn(.{}, Self.listen, .{self});

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

    std.debug.print("Deinitialized client.\n", .{});
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
    std.debug.print("UDP Client listening...\n", .{});
    while (self.open) {
        const result = self.receiveMessage() catch |err| {
            if (err == error.NoDataAvailable) {
                std.Thread.sleep(self.polling_interval * 1000);
                continue;
            }
            return err;
        };
        try self.queue.append(self.alloc, result);
    }
}
