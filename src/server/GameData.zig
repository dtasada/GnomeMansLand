//! Namespace for game data used by the server
const std = @import("std");

const commons = @import("commons");

const Perlin = @import("Perlin.zig");

const ServerSettings = commons.ServerSettings;

const Self = @This();

world_data: WorldData,
players: std.ArrayList(Player),
server_settings: ServerSettings,

pub fn init(alloc: std.mem.Allocator, settings: ServerSettings) !Self {
    var players = try std.ArrayList(Player).initCapacity(alloc, settings.max_players);
    errdefer players.deinit(alloc);

    return .{
        .players = players,
        .world_data = try WorldData.init(alloc, settings),
        .server_settings = settings,
    };
}

pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
    self.world_data.deinit(alloc);

    for (self.players.items) |p|
        alloc.free(p.nickname);

    self.players.deinit(alloc);
}

pub const Player = struct {
    id: u32,
    nickname: []const u8,
    position: ?commons.v2f,

    pub fn init(id: u32, nickname: []const u8) Player {
        return .{
            .id = id,
            .nickname = nickname,
            .position = null,
        };
    }
};

pub const WorldData = struct {
    size: commons.v2u,
    height_map: []f32, // 2d in practice
    finished_generating: std.atomic.Value(bool),
    network_chunks_ready: std.atomic.Value(bool),
    floats_written: std.atomic.Value(usize),
    network_chunks_generated: std.atomic.Value(usize),

    /// starts genTerrainData thread
    pub fn init(alloc: std.mem.Allocator, settings: ServerSettings) !WorldData {
        const x, const y = settings.world_generation.resolution;
        var self: WorldData = .{
            .size = .{ .x = x, .y = y },
            .height_map = try alloc.alloc(f32, x * y),
            .finished_generating = std.atomic.Value(bool).init(false),
            .network_chunks_ready = std.atomic.Value(bool).init(false),
            .floats_written = std.atomic.Value(usize).init(0),
            .network_chunks_generated = std.atomic.Value(usize).init(0),
        };
        errdefer alloc.free(self.height_map);

        try self.genTerrainData(alloc, settings);

        return self;
    }

    pub fn deinit(self: *const WorldData, alloc: std.mem.Allocator) void {
        alloc.free(self.height_map);
    }

    /// Asynchronously populates `world_data.height_map`
    fn genTerrainData(self: *WorldData, alloc: std.mem.Allocator, settings: ServerSettings) !void {
        const seed: u32 = settings.world_generation.seed orelse rand: {
            var seed: u32 = undefined;
            try std.posix.getrandom(std.mem.asBytes(&seed));
            var rand = std.Random.DefaultPrng.init(seed);
            break :rand rand.random().intRangeAtMost(u32, 0, std.math.maxInt(u32));
        };

        var pn = try Perlin.init(alloc, seed);
        defer pn.deinit(alloc);

        var pool: std.Thread.Pool = undefined;
        try pool.init(.{ .allocator = alloc });
        defer pool.deinit();

        for (0..self.size.y) |y| {
            try pool.spawn(genTerrainDataLoop, .{ self, &settings, &pn, y });
        }
    }

    fn genTerrainDataLoop(
        self: *WorldData,
        settings: *const ServerSettings,
        pn: *const Perlin,
        y: usize,
    ) void {
        for (0..self.size.x) |x| {
            var freq = 7.68 * settings.world_generation.frequency / @as(f32, @floatFromInt(self.size.x));
            var height: f32 = 0.0;
            var amp: f32 = settings.world_generation.amplitude;
            var maxValue: f32 = 0.0;

            var nx: f32 = 0;
            var ny: f32 = 0;

            for (0..@intCast(settings.world_generation.octaves)) |_| {
                nx = @as(f32, @floatFromInt(x)) * freq;
                ny = @as(f32, @floatFromInt(y)) * freq;

                height += amp * pn.noise(nx, ny, 0);
                maxValue += amp;
                amp *= settings.world_generation.persistence;
                freq *= settings.world_generation.lacunarity;
            }

            self.height_map[y * self.size.x + x] = height;
            _ = self.floats_written.fetchAdd(1, .monotonic);
        }

        if (self.floats_written.load(.monotonic) == self.height_map.len)
            self.finished_generating.store(true, .monotonic);
    }
};
