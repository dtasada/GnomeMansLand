//! Local client handler struct
const std = @import("std");
const builtin = @import("builtin");
const network = @import("network");

const commons = @import("commons");
const socket_packet = @import("socket_packet");

const GameData = @import("game").GameData;

pub const Settings = @import("Settings.zig");

const Self = @This();

alloc: std.mem.Allocator,
sock: network.Socket,
listen_thread: std.Thread,
game_data: GameData,
running: std.atomic.Value(bool),
polling_rate: u64,

const BYTE_LIMIT: usize = 65535;

pub fn init(alloc: std.mem.Allocator, settings: Settings, connect_message: socket_packet.ClientConnect) !*Self {
    var self = try alloc.create(Self);
    errdefer alloc.destroy(self);

    self.alloc = alloc;

    self.game_data = try GameData.init(self.alloc);
    errdefer self.game_data.deinit(self.alloc);

    try network.init();
    errdefer network.deinit();

    self.sock = network.connectToHost(
        self.alloc,
        settings.multiplayer.server_host,
        settings.multiplayer.server_port,
        .tcp,
    ) catch |err| return commons.printErr(
        err,
        "Couldn't connect to host server at ({s}:{}): {}\n",
        .{ settings.multiplayer.server_host, settings.multiplayer.server_port, err },
        .red,
    );

    self.running = std.atomic.Value(bool).init(true);
    errdefer self.running.store(false, .monotonic);

    const connect_message_json = try std.json.Stringify.valueAlloc(self.alloc, connect_message, .{});
    defer self.alloc.free(connect_message_json);
    _ = try self.send(connect_message_json);

    self.listen_thread = try std.Thread.spawn(.{}, Self.listen, .{self});
    self.polling_rate = settings.multiplayer.polling_rate;

    try self.sock.setReadTimeout(500 * 1000); // set 500 ms timeout for thread join

    return self;
}

pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
    self.game_data.deinit(self.alloc);

    self.running.store(false, .monotonic);

    self.listen_thread.join();
    self.sock.close();

    network.deinit();

    alloc.destroy(self);
}

/// Meant to run as a thread. Listens for new messages and calls `handleMessage` upon receiving one.
fn listen(self: *Self) !void {
    const buf = try self.alloc.alloc(u8, BYTE_LIMIT); // don't decrease this. decreasing it makes it slower
    defer self.alloc.free(buf);

    var pending = try std.ArrayList(u8).initCapacity(self.alloc, BYTE_LIMIT);
    defer pending.deinit(self.alloc);

    while (self.running.load(.monotonic)) : (std.Thread.sleep(std.time.ns_per_ms * self.polling_rate)) {
        const bytes_read = self.sock.receive(buf) catch |err| switch (err) {
            error.WouldBlock => continue,
            error.ConnectionResetByPeer => {
                self.running.store(false, .monotonic);
                commons.print("Socket disconnected\n", .{}, .blue);
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
        if (!self.running.load(.monotonic)) return;

        try pending.appendSlice(self.alloc, buf[0..bytes_read]);

        // Process complete lines
        var start: usize = 0;
        while (std.mem.indexOfScalarPos(u8, pending.items, start, '\n')) |pos| {
            const line = pending.items[start..pos];
            if (line.len != 0) try self.handleMessage(line);
            start = pos + 1;
        }

        // Remove processed bytes from buffer
        if (start > 0) {
            const range = try self.alloc.alloc(usize, start);
            defer self.alloc.free(range);
            for (0..start) |i| range[i] = i;
            pending.orderedRemoveMany(range);
        }
    }
}

/// Parses a message and calls `processMessage`.
fn handleMessage(self: *Self, message: []const u8) !void {
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
            message_root,
            try commons.getDescriptor(object, .server),
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
    message_root: std.json.Value,
    descriptor: socket_packet.Descriptor,
) !void {
    switch (descriptor) {
        .player_state => {
            const request_parsed = try std.json.parseFromValue(socket_packet.Player, self.alloc, message_root, .{});
            defer request_parsed.deinit();

            const player = request_parsed.value.player;
            if (self.game_data.players.items.len <= @as(usize, player.id)) {
                try self.game_data.players.append(self.alloc, player);
            } else {
                self.game_data.players.items[@intCast(player.id)] = player;
            }
        },
        .map_chunk => {
            // if we don't own the map, we're the host, so we don't need to download it
            if (self.game_data.map) |*map| {
                if (!map.owns_height_map) return;
            }

            const request_parsed = try std.json.parseFromValue(socket_packet.MapChunk, self.alloc, message_root, .{});
            defer request_parsed.deinit();

            const map_chunk = request_parsed.value;
            if (self.game_data.map) |*map|
                map.addChunk(map_chunk)
            else
                self.game_data.map = try GameData.Map.init(self.alloc, map_chunk);
        },
        .server_full => @panic("unimplemented"),
        else => commons.print(
            "Received message with illegal descriptor {s} received from server\n",
            .{@tagName(descriptor)},
            .yellow,
        ),
    }
}

pub fn send(self: *const Self, message: []const u8) !void {
    _ = try self.sock.send(message);
}
