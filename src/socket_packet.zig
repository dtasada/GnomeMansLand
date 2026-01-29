//! Namespace for JSON request types
const std = @import("std");

const commons = @import("commons");

const ServerGameData = @import("server").GameData;

/// Identifies the different types of messages that can be sent and received.
pub const Packet = union(enum(u8)) {
    /// Send to client when the server is full and has reached the maximum player limit.
    server_full,
    /// Request by a client to receive game map data
    client_requests_map_data,

    /// Object representing a world terrain chunk.
    map_chunk: MapChunk,
    /// Object identifying a new player.
    client_requests_connect: ClientRequestsConnect,
    /// Requests the server to move a player to `new_pos`.
    client_requests_move_player: ClientRequestsMovePlayer,
    /// Server sends feedback upon a `client_requests_connect`
    server_accepted_client: ServerAcceptedClient,

    /// Represents the player object in the client-server interface.
    player_state: struct {
        player: ServerGameData.Player,

        pub fn init(player: ServerGameData.Player) @This() {
            return .{ .player = player };
        }
    },

    /// Request the server to send a message again.
    resend_request: struct { // not in use atm but keeping it in for now just in case.
        body: []const u8,

        pub fn init(body: []const u8) @This() {
            return .{ .body = body };
        }
    },
};

pub const MapChunk = struct {
    const Self = @This();

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
        io: std.Io,
        map_chunks: []Self,
        server_map: *ServerGameData.Map,
    ) !void {
        var pool: std.Io.Group = .init;

        for (0..map_chunks.len) |i|
            pool.async(io, genChunk, .{
                map_chunks,
                server_map,
                i,
            });

        try pool.await(io);
    }

    /// Generates a single chunk of index `i`.
    fn genChunk(chunks: []Self, server_map: *ServerGameData.Map, i: usize) void {
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
    }
};

pub const ClientRequestsConnect = struct {
    nickname: []const u8,

    pub fn init(nickname: []const u8) @This() {
        return .{ .nickname = nickname };
    }
};

pub const ServerAcceptedClient = struct {
    map_size: commons.v2u,

    pub fn init(map_size: commons.v2u) @This() {
        return .{ .map_size = map_size };
    }
};

pub const ClientRequestsMovePlayer = struct {
    new_pos: commons.v2f,

    pub fn init(new_pos: commons.v2f) @This() {
        return .{ .new_pos = new_pos };
    }
};
