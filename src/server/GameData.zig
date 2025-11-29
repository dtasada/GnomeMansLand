//! Namespace for game data used by the server
const std = @import("std");

const commons = @import("commons");

const Perlin = @import("Perlin.zig");

const ServerSettings = commons.ServerSettings;

const Self = @This();

map: *Map,
players: std.ArrayList(Player),
server_settings: ServerSettings,

/// Returns with an empty arraylist of players, and a Map pointer.
pub fn init(alloc: std.mem.Allocator, settings: ServerSettings) !Self {
    var players = try std.ArrayList(Player).initCapacity(alloc, settings.max_players);
    errdefer players.deinit(alloc);

    return .{
        .players = players,
        .map = try Map.init(alloc, settings),
        .server_settings = settings,
    };
}

pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
    self.map.deinit(alloc);

    for (self.players.items) |p| p.deinit(alloc);

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

    pub fn deinit(self: *const Player, alloc: std.mem.Allocator) void {
        alloc.free(self.nickname);
    }
};

pub const Map = struct {
    size: commons.v2u,
    height_map: []f32, // 2d in practice
    finished_generating: std.atomic.Value(bool) = .init(false),
    network_chunks_ready: std.atomic.Value(bool) = .init(false),
    floats_written: usize = 0,
    network_chunks_generated: std.atomic.Value(usize) = .init(0),
    terrain_gen_thread: ?std.Thread = null,

    /// starts genTerrainData thread.
    pub fn init(alloc: std.mem.Allocator, settings: ServerSettings) !*Map {
        const x, const y = settings.world_generation.resolution;
        const self = try alloc.create(Map);
        errdefer alloc.destroy(self);
        self.* = .{
            .size = .{ .x = x, .y = y },
            .height_map = try alloc.alloc(f32, x * y),
        };
        errdefer alloc.free(self.height_map);

        self.terrain_gen_thread = try std.Thread.spawn(.{}, genTerrainData, .{ self, alloc, settings });

        return self;
    }

    pub fn deinit(self: *const Map, alloc: std.mem.Allocator) void {
        if (self.terrain_gen_thread) |t| t.join();
        alloc.free(self.height_map);
        alloc.destroy(self);
    }

    /// Asynchronously populates `map.height_map`
    fn genTerrainData(self: *Map, alloc: std.mem.Allocator, settings: ServerSettings) !void {
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

        var wg: std.Thread.WaitGroup = .{};
        var mutex: std.Thread.Mutex = .{};

        for (0..self.size.y) |y|
            pool.spawnWg(
                &wg,
                genTerrainDataLoop,
                .{ self, &mutex, &settings, &pn, y },
            );

        wg.wait();
    }

    fn genTerrainDataLoop(
        self: *Map,
        mutex: *std.Thread.Mutex,
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

            mutex.lock();
            self.height_map[y * self.size.x + x] = height;
            self.floats_written += 1;
            mutex.unlock();
        }

        if (self.floats_written == self.height_map.len)
            self.finished_generating.store(true, .monotonic);
    }
};
