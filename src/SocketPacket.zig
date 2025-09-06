//! Namespace for JSON request types
const std = @import("std");
const ServerGameData = @import("ServerGameData.zig");

pub const ClientConnect = struct {
    descriptor: []const u8 = "client_connect",
    nickname: []const u8,

    pub fn init(nickname: []const u8) ClientConnect {
        return .{ .nickname = nickname };
    }
};

pub const WorldDataChunk = struct {
    descriptor: []const u8,
    total_size: [2]u32,
    height_map: []f32, // 2d in practice

    /// Caller is responsible for memory cleanup
    pub fn init(alloc: std.mem.Allocator, server_world_data: ServerGameData.WorldData) ![]WorldDataChunk {
        const MAX_SIZE_BYTES = 65535;
        const JSON_FLOAT_SIZE = 20;
        const json_overhead = 200;

        const available_bytes_for_data = MAX_SIZE_BYTES - json_overhead;

        const floats_per_chunk = @divFloor(available_bytes_for_data, JSON_FLOAT_SIZE);
        const total_floats = server_world_data.height_map.len;
        const amount_of_chunks = @divFloor(total_floats, floats_per_chunk) +
            (if (total_floats % floats_per_chunk == 0) @as(u32, 0) else @as(u32, 1));
        std.debug.print("amount_of_chunks {}\n", .{amount_of_chunks});

        var chunks = try alloc.alloc(WorldDataChunk, amount_of_chunks);

        for (0..amount_of_chunks) |i| {
            const start_idx = i * floats_per_chunk;
            const end_idx = @min(start_idx + floats_per_chunk, total_floats);
            std.debug.print("server: chunk amount of floats: {}\n", .{end_idx - start_idx});

            chunks[i] = WorldDataChunk{
                .descriptor = "world_data_chunk",
                .total_size = .{ server_world_data.size.x, server_world_data.size.y },
                .height_map = server_world_data.height_map[start_idx..end_idx],
            };
        }
        return chunks;
    }
};
