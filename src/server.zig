const std = @import("std");
const Settings = @import("settings.zig");

const Self = @This();

sockfd: std.posix.socket_t,
server_address: std.net.Address,
open: bool,
listen_thread: std.Thread,
alloc: std.mem.Allocator,
_gpa: std.heap.GeneralPurposeAllocator(.{}),

pub fn init(st: *const Settings) !Self {
    // Create UDP socket
    var self: Self = undefined;
    self.server_address = try std.net.Address.parseIp(st.multiplayer.server_host, st.multiplayer.server_port);
    self.sockfd = try std.posix.socket(self.server_address.any.family, std.posix.SOCK.DGRAM, 0);

    self._gpa = std.heap.GeneralPurposeAllocator(.{}){};
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

    self.open = true;

    self.listen_thread = try std.Thread.spawn(.{}, Self.listen, .{&self});

    return self;
}

pub fn deinit(self: *Self) void {
    self.open = false;
    self.listen_thread.join();

    std.posix.close(self.sockfd);

    _ = self._gpa.deinit();

    std.debug.print("Deinitialized server.", .{});
}

pub fn listen(self: *Self) !void {
    std.debug.print("UDP Server listening on {f}\n", .{self.server_address});

    var buffer: [1024]u8 = undefined;
    while (self.open) {
        // Receive data from client
        var client_address: std.net.Address = undefined;
        var client_address_len: std.posix.socklen_t = @sizeOf(std.net.Address);

        const bytes_received = std.posix.recvfrom(
            self.sockfd,
            buffer[0..],
            0,
            @ptrCast(&client_address.any),
            &client_address_len,
        ) catch |err| {
            std.debug.print("Failed to receive data: {}\n", .{err});
            continue;
        };

        if (bytes_received == 0) continue;

        const message = buffer[0..bytes_received];
        std.debug.print("Received from {f}: {s}\n", .{ client_address, message });

        // Echo the message back
        const response = try std.fmt.allocPrint(self.alloc, "Echo: {s}", .{message});
        defer self.alloc.free(response);

        _ = std.posix.sendto(
            self.sockfd,
            response,
            0,
            @ptrCast(&client_address.any),
            client_address_len,
        ) catch |err| {
            std.debug.print("Failed to send response: {}\n", .{err});
            continue;
        };

        std.debug.print("Sent response to client\n", .{});
    }
}
