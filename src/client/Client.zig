//! Local client handler struct
const std = @import("std");
const builtin = @import("builtin");
const network = @import("network");

const commons = @import("../commons.zig");
const socket_packet = @import("../socket_packet.zig");

const GameData = @import("GameData.zig");
const Settings = @import("Settings.zig");

const Self = @This();

_gpa: std.heap.GeneralPurposeAllocator(.{}),
alloc: std.mem.Allocator,
sock: network.Socket,
listen_thread: std.Thread,
game_data: GameData,
running: std.atomic.Value(bool),
polling_rate: u64,

pub fn init(alloc: std.mem.Allocator, settings: Settings, connect_message: socket_packet.ClientConnect) !*Self {
    var self: *Self = try alloc.create(Self);
    errdefer alloc.destroy(self);

    self._gpa = .init;
    self.alloc = self._gpa.allocator();
    errdefer _ = self._gpa.deinit();

    self.game_data = try GameData.init(self.alloc);
    errdefer self.game_data.deinit(self.alloc);

    try network.init();
    errdefer network.deinit();

    self.sock = network.connectToHost(
        self.alloc,
        settings.multiplayer.server_host,
        settings.multiplayer.server_port,
        .tcp,
    ) catch |err| {
        commons.print(
            "Couldn't connect to host server at ({s}:{}): {}\n",
            .{ settings.multiplayer.server_host, settings.multiplayer.server_port, err },
            .red,
        );
        return err;
    };

    self.running = std.atomic.Value(bool).init(true);

    const connect_message_json = try std.json.Stringify.valueAlloc(self.alloc, connect_message, .{});
    defer self.alloc.free(connect_message_json);
    _ = try self.sock.send(connect_message_json);

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

    _ = self._gpa.deinit();
    alloc.destroy(self);
}

fn listen(self: *Self) !void {
    const buf = try self.alloc.alloc(u8, 65535); // don't decrease this. decreasing it makes it slower
    defer self.alloc.free(buf);

    var pending = try std.ArrayList(u8).initCapacity(self.alloc, 65535);
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
        while (true) {
            if (std.mem.indexOfScalarPos(u8, pending.items, start, '\n')) |pos| {
                const line = pending.items[start..pos];
                if (line.len != 0) try self.handleMessage(line);
                start = pos + 1;
            } else break;
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
        .object => |object| {
            var it = object.iterator();
            while (it.next()) |entry| {
                const key = entry.key_ptr.*;

                if (std.mem.eql(u8, key, "descriptor")) {
                    const descriptor = entry.value_ptr.*.string;

                    if (std.mem.eql(u8, descriptor, "player_state")) {
                        const request_parsed = try std.json.parseFromValue(socket_packet.Player, self.alloc, message_root, .{});
                        defer request_parsed.deinit();

                        const player = request_parsed.value.player;
                        if (self.game_data.players.items.len <= @as(usize, player.id)) {
                            try self.game_data.players.append(self.alloc, player);
                        } else {
                            self.game_data.players.items[@intCast(player.id)] = player;
                        }
                    }
                    if (std.mem.startsWith(u8, descriptor, "world_data_chunk-")) {
                        const request_parsed = try std.json.parseFromValue(socket_packet.WorldDataChunk, self.alloc, message_root, .{});
                        defer request_parsed.deinit();

                        const world_data_chunk: socket_packet.WorldDataChunk = request_parsed.value;
                        if (self.game_data.world_data) |*world_data|
                            world_data.addChunk(world_data_chunk)
                        else
                            self.game_data.world_data = try GameData.WorldData.init(self.alloc, world_data_chunk);
                    }
                }
            }
        },
        else => {},
    }
}

pub fn send(self: *const Self, message: []const u8) !void {
    _ = try self.sock.send(message);
}
