//! Namespace for JSON request types
const std = @import("std");

const commons = @import("commons");

const ServerGameData = @import("server").GameData;

pub const ClientConnect = struct {
    descriptor: []const u8 = "client_connect",
    nickname: []const u8,

    pub fn init(nickname: []const u8) ClientConnect {
        return .{ .nickname = nickname };
    }
};

pub const WorldDataChunk = struct {
    const MAX_SIZE_BYTES: usize = 1024;
    const JSON_FLOAT_SIZE: usize = 20;
    const JSON_OVERHEAD: usize = 200;
    const AVAILABLE_BYTES_FOR_DATA: usize = MAX_SIZE_BYTES - JSON_OVERHEAD;
    pub const FLOATS_PER_CHUNK = @divFloor(AVAILABLE_BYTES_FOR_DATA, JSON_FLOAT_SIZE);

    descriptor: []const u8,
    chunk_index: u32,
    float_start_index: u32,
    float_end_index: u32,
    total_size: commons.v2u,
    height_map: []f32, // 2d in practice

    /// Asynchronoulsy populates `world_data_chunks`
    pub fn init(
        alloc: std.mem.Allocator,
        server_world_data: *ServerGameData.WorldData,
        world_data_chunks: []?WorldDataChunk,
    ) !std.Thread {
        return try std.Thread.spawn(.{}, genChunks, .{
            alloc,
            world_data_chunks,
            server_world_data,
        });
    }

    /// blocking. populates `world_data_chunks` in parallel.
    fn genChunks(
        alloc: std.mem.Allocator,
        world_data_chunks: []?WorldDataChunk,
        server_world_data: *ServerGameData.WorldData,
    ) !void {
        var pool: std.Thread.Pool = undefined;
        try pool.init(.{ .allocator = alloc });
        defer pool.deinit();

        var wg: std.Thread.WaitGroup = .{};
        for (0..world_data_chunks.len) |i| {
            pool.spawnWg(&wg, genChunk, .{
                alloc,
                world_data_chunks,
                server_world_data,
                i,
            });
        }

        wg.wait();
    }

    fn genChunk(
        alloc: std.mem.Allocator,
        chunks: []?WorldDataChunk,
        server_world_data: *ServerGameData.WorldData,
        i: usize,
    ) void {
        const start_idx = i * FLOATS_PER_CHUNK;
        const end_idx = @min(start_idx + FLOATS_PER_CHUNK, server_world_data.height_map.len);

        chunks[i] = .{
            .descriptor = std.fmt.allocPrint(alloc, "world_data_chunk-{}", .{i}) catch |err| {
                commons.print(
                    "Couldn't create world_data_chunk-{{}} descriptor: {}\n",
                    .{err},
                    .red,
                );
                return;
            },
            .chunk_index = @intCast(i),
            .float_start_index = @intCast(start_idx),
            .float_end_index = @intCast(end_idx),
            .total_size = server_world_data.size,
            .height_map = server_world_data.height_map[start_idx..end_idx],
        };

        _ = server_world_data.network_chunks_generated.fetchAdd(1, .monotonic);
        if (server_world_data.network_chunks_generated.load(.monotonic) == chunks.len)
            server_world_data.network_chunks_ready.store(true, .monotonic);
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
