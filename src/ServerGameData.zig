//! Namespace for game data used by both the client and server
const std = @import("std");

const Perlin = @import("Perlin.zig");
const Settings = @import("Settings.zig");

const Self = @This();

players: std.ArrayList(Player),
world_data: WorldData,

pub fn init(alloc: std.mem.Allocator, st: *const Settings) !Self {
    return .{
        .players = try .initCapacity(alloc, 8),
        .world_data = try .init(alloc, st),
    };
}

pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
    self.world_data.deinit(alloc);
    self.players.deinit(alloc);
}

pub const Player = struct {
    nickname: []const u8,

    pub fn init(nickname: []const u8) Player {
        return .{
            .nickname = nickname,
        };
    }
};

pub const WorldData = struct {
    height_map: []f32, // 2d in practice
    size: struct { x: u32, y: u32 },

    pub fn init(alloc: std.mem.Allocator, st: *const Settings) !WorldData {
        var self: WorldData = undefined;
        self.size = .{ .x = st.world_generation.resolution[0], .y = st.world_generation.resolution[1] };
        self.height_map = try alloc.alloc(f32, self.size.x * self.size.y);

        try self.genTerrainData(alloc, st);

        std.debug.print("World generated\n", .{});
        return self;
    }

    pub fn deinit(self: *WorldData, alloc: std.mem.Allocator) void {
        alloc.free(self.height_map);
    }

    fn genTerrainData(self: *WorldData, alloc: std.mem.Allocator, st: *const Settings) !void {
        const seed: u32 = st.world_generation.seed orelse rand: {
            var seed: u32 = undefined;
            try std.posix.getrandom(std.mem.asBytes(&seed));
            var rand = std.Random.DefaultPrng.init(seed);
            break :rand rand.random().intRangeAtMost(u32, 0, std.math.maxInt(u32));
        };

        var pn = try Perlin.init(alloc, seed);
        defer pn.deinit(alloc);

        for (0..self.size.y) |y| {
            for (0..self.size.x) |x| {
                var freq = 7.68 * st.world_generation.frequency / @as(f32, @floatFromInt(self.size.x));
                var height: f32 = 0.0;
                var amp: f32 = st.world_generation.amplitude;
                var maxValue: f32 = 0.0;

                var nx: f32 = 0;
                var ny: f32 = 0;

                for (0..@intCast(st.world_generation.octaves)) |_| {
                    nx = @as(f32, @floatFromInt(x)) * freq;
                    ny = @as(f32, @floatFromInt(y)) * freq;

                    height += amp * pn.noise(nx, ny, 0);
                    maxValue += amp;
                    amp *= st.world_generation.persistence;
                    freq *= st.world_generation.lacunarity;
                }

                self.height_map[y * self.size.x + x] = height;
            }
        }
    }
};
