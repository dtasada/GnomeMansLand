//! Namespace for JSON request types
const std = @import("std");
const ServerGameData = @import("ServerGameData.zig");
const commons = @import("commons.zig");

pub const ClientConnect = struct {
    descriptor: []const u8 = "client_connect",
    nickname: []const u8,

    pub fn init(nickname: []const u8) ClientConnect {
        return .{ .nickname = nickname };
    }
};

pub const WorldDataChunk = struct {
    descriptor: []const u8,
    chunk_index: u32,
    float_start_index: u32,
    float_end_index: u32,
    total_size: commons.v2u,
    height_map: []f32, // 2d in practice

    /// Caller is responsible for memory cleanup
    pub fn init(alloc: std.mem.Allocator, server_world_data: ServerGameData.WorldData) ![]WorldDataChunk {
        const MAX_SIZE_BYTES = 65535;
        const JSON_FLOAT_SIZE = 20;
        const JSON_OVERHEAD = 200;

        const available_bytes_for_data = MAX_SIZE_BYTES - JSON_OVERHEAD;

        const floats_per_chunk = @divFloor(available_bytes_for_data, JSON_FLOAT_SIZE);
        const total_floats = server_world_data.height_map.len;
        const amount_of_chunks = @divFloor(total_floats, floats_per_chunk) +
            (if (total_floats % floats_per_chunk == 0) @as(u32, 0) else @as(u32, 1));
        std.debug.print("amount_of_chunks {}\n", .{amount_of_chunks});

        var chunks = try alloc.alloc(WorldDataChunk, amount_of_chunks);

        for (0..amount_of_chunks) |i| {
            const start_idx = i * floats_per_chunk;
            const end_idx = @min(start_idx + floats_per_chunk, total_floats);

            chunks[i] = WorldDataChunk{
                .descriptor = try std.fmt.allocPrint(alloc, "world_data_chunk-{}", .{i}),
                .chunk_index = @intCast(i),
                .float_start_index = @intCast(start_idx),
                .float_end_index = @intCast(end_idx),
                .total_size = server_world_data.size,
                .height_map = server_world_data.height_map[start_idx..end_idx],
            };
        }
        return chunks;
    }
};

/// Request the server to send a message again.
pub const ResendRequest = struct { // not in use atm but keeping it in for now just in case.
    descriptor: []const u8 = "resend_request",
    body: []const u8,

    pub fn init(body: []const u8) ResendRequest {
        return .{ .body = body };
    }
};

pub const Player = struct {
    descriptor: []const u8 = "player_state",
    player: ServerGameData.Player,

    pub fn init(player: ServerGameData.Player) Player {
        return .{ .player = player };
    }
};

pub const MovePlayer = struct {
    descriptor: []const u8 = "move_player",
    new_pos: commons.v2f,

    pub fn init(new_pos: commons.v2f) MovePlayer {
        return .{ .new_pos = new_pos };
    }
};
