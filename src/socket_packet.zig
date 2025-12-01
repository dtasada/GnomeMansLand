//! Namespace for JSON request types
const std = @import("std");

const commons = @import("commons");

const ServerGameData = @import("server").GameData;

/// Identifies the different types of messages that can be sent and received.
pub const Descriptor = enum(u8) {
    pub const Type = std.meta.Tag(@This()); // returns the integer type of the enum

    player_state,
    map_chunk,
    server_full,
    client_requests_connect,
    client_requests_move_player,
    client_requests_map_data,
    resend_request,
    server_accepted_client,
};

/// Object identifying a new player.
pub const ClientRequestsConnect = struct {
    descriptor: Descriptor = .client_requests_connect,
    nickname: []const u8,

    pub fn init(nickname: []const u8) ClientRequestsConnect {
        return .{ .nickname = nickname };
    }
};

/// Object representing a world terrain chunk.
pub const MapChunk = struct {
    /// Constant: max length in bytes of a chunk.
    const MAX_SIZE_BYTES: usize = 1024;
    /// Constant: the length in bytes of a floating point number in JSON.
    const JSON_FLOAT_SIZE: usize = 20;
    /// Constsant: amount of bytes consumed by miscellaneous JSON boilerplate.
    const JSON_OVERHEAD: usize = 200;
    /// Constant: amount of bytes available for actual floating point data.
    const AVAILABLE_BYTES_FOR_DATA: usize = MAX_SIZE_BYTES - JSON_OVERHEAD;
    /// Constant: amount of floating point values that can fit in a chunk.
    pub const FLOATS_PER_CHUNK = @divFloor(AVAILABLE_BYTES_FOR_DATA, JSON_FLOAT_SIZE);

    descriptor: Descriptor = .map_chunk,
    /// identifies the index of the chunk.
    chunk_index: u32,
    /// identifies the index of the first float in the chunk relative to the full height map.
    start_index: u32,
    /// 2d vector containing the dimensions of the full height map.
    total_size: commons.v2u,
    /// actual floating point numbers of the chunk to be written into the JSON chunk.
    height_map: []f32, // 2d in practice

    /// Asynchronoulsy populates `map_chunks`
    pub fn init(
        alloc: std.mem.Allocator,
        map_chunks: []MapChunk,
        server_map: *ServerGameData.Map,
    ) !void {
        var pool: std.Thread.Pool = undefined;
        try pool.init(.{ .allocator = alloc });
        defer pool.deinit();

        var wg: std.Thread.WaitGroup = .{};
        for (0..map_chunks.len) |i| {
            pool.spawnWg(&wg, genChunk, .{
                map_chunks,
                server_map,
                i,
            });
        }

        wg.wait();
    }

    /// Generates a single chunk of index `i`.
    fn genChunk(chunks: []MapChunk, server_map: *ServerGameData.Map, i: usize) void {
        const start_idx = i * FLOATS_PER_CHUNK;

        chunks[i] = .{
            .chunk_index = @intCast(i),
            .start_index = @intCast(start_idx),
            .total_size = server_map.size,
            .height_map = server_map.height_map[start_idx..@min(
                start_idx + FLOATS_PER_CHUNK,
                server_map.height_map.len,
            )],
        };

        _ = server_map.network_chunks_generated.fetchAdd(1, .monotonic);
        if (server_map.network_chunks_generated.load(.monotonic) == chunks.len)
            server_map.network_chunks_ready.store(true, .monotonic);
    }
};

/// Request the server to send a message again.
pub const ResendRequest = struct { // not in use atm but keeping it in for now just in case.
    descriptor: Descriptor = .resend_request,
    body: []const u8,

    pub fn init(body: []const u8) ResendRequest {
        return .{ .body = body };
    }
};

/// Represents the player object in the client-server interface.
pub const PlayerState = struct {
    descriptor: Descriptor = .player_state,
    player: ServerGameData.Player,

    pub fn init(player: ServerGameData.Player) PlayerState {
        return .{ .player = player };
    }
};

/// Requests the server to move a player to `new_pos`.
pub const ClientRequestsMovePlayer = struct {
    descriptor: Descriptor = .client_requests_move_player,
    new_pos: commons.v2f,

    pub fn init(new_pos: commons.v2f) ClientRequestsMovePlayer {
        return .{ .new_pos = new_pos };
    }
};

/// Send to client when the server is full and has reached the maximum player limit.
pub const ServerFull = struct {
    descriptor: Descriptor = .server_full,
};

pub const ServerAcceptedClient = struct {
    descriptor: Descriptor = .server_accepted_client,
    map_size: commons.v2u,

    pub fn init(map_size: commons.v2u) ServerAcceptedClient {
        return .{ .map_size = map_size };
    }
};

pub const ClientRequestsMapData = struct {
    descriptor: Descriptor = .client_requests_map_data,
};
