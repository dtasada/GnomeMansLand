const rl = @import("raylib");
const std = @import("std");
const c = @cImport({
    @cInclude("stdlib.h");
});

const Settings = @import("Settings.zig");
const Perlin = @import("Perlin.zig");

const Self = @This();

size: struct { x: u32, y: u32 },
map_data: [][]f32,
model: rl.Model,

const Rgb = struct {
    r: i16,
    g: i16,
    b: i16,

    pub fn init(r: i16, g: i16, b: i16) Rgb {
        return .{ .r = r, .g = g, .b = b };
    }

    pub fn add(lhs: Rgb, rhs: Rgb) Rgb {
        return Rgb.init(lhs.r + rhs.r, lhs.g + rhs.g, lhs.b + rhs.b);
    }

    pub fn subtract(lhs: Rgb, rhs: Rgb) Rgb {
        return Rgb.init(lhs.r -| rhs.r, lhs.g -| rhs.g, lhs.b -| rhs.b);
    }

    pub fn scale(lhs: Rgb, m: f32) Rgb {
        // if (m < 0.0) std.debug.panic("Rgb.scale multiplier < 0.0: mult={}\n", .{m});
        const m_ = if (m >= 0) m else 0;
        return Rgb.init(
            @intFromFloat(@as(f32, @floatFromInt(lhs.r)) * m_),
            @intFromFloat(@as(f32, @floatFromInt(lhs.g)) * m_),
            @intFromFloat(@as(f32, @floatFromInt(lhs.b)) * m_),
        );
    }
};

const Color = struct {
    const WATER_LOW = Rgb.init(0, 0, 50);
    const WATER_HIGH = Rgb.init(30, 110, 140);
    const SAND_LOW = Rgb.init(237, 206, 178);
    const SAND_HIGH = Rgb.init(255, 245, 193);
    const GRASS_LOW = Rgb.init(10, 155, 104);
    const GRASS_HIGH = Rgb.init(11, 84, 60);
    const MOUNTAIN_LOW = Rgb.init(80, 80, 80);
    const MOUNTAIN_HIGH = Rgb.init(120, 120, 120);
};

pub const TileData = struct {
    pub var water: f32 = 0.40;
    pub var sand: f32 = 0.43;
    pub var grass: f32 = 0.61;
    pub var mountain: f32 = 0.68;
    pub var snow: f32 = 1.0;
};

fn lerp_color(c1: Rgb, c2: Rgb, m: f32) Rgb {
    return c1.add(c2.subtract(c1).scale(m)); // c1+(c2-c1)*m
}

pub fn init(alloc: std.mem.Allocator, st: *const Settings) !Self {
    var self: Self = undefined;
    self.size = .{ .x = st.world_generation.resolution[0], .y = st.world_generation.resolution[1] };
    self.map_data = try alloc.alloc([]f32, self.size.y);
    self.model = undefined;

    for (0..self.map_data.len) |y|
        self.map_data[y] = try alloc.alloc(f32, self.size.x);

    try self.genWorld(alloc, st);

    std.debug.print("World generated\n", .{});
    return self;
}

fn genWorld(self: *Self, alloc: std.mem.Allocator, st: *const Settings) !void {
    try self.genTerrainData(alloc, st);
    try self.genModel(st);
}

fn genTerrainData(self: *Self, alloc: std.mem.Allocator, st: *const Settings) !void {
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

            self.map_data[y][x] = height;
        }
    }
}

fn genModel(self: *Self, st: *const Settings) !void {
    self.model = try rl.Model.fromMesh(try self.genTerrainMesh());
    var image = rl.Image.genColor(
        @intCast(self.size.x),
        @intCast(self.size.y),
        .blue,
    );

    for (0..self.size.y) |y| {
        for (0..self.size.x) |x| {
            const height = (self.getHeight(x, y) + st.world_generation.amplitude) / (2 * st.world_generation.amplitude);
            const tile: Rgb =
                if (height <= TileData.water)
                    lerp_color(Color.WATER_LOW, Color.WATER_HIGH, height / TileData.water)
                else if (height <= TileData.sand)
                    lerp_color(Color.SAND_LOW, Color.SAND_HIGH, (height - TileData.water) / (TileData.sand - TileData.water))
                else if (height <= TileData.grass)
                    lerp_color(Color.GRASS_LOW, Color.GRASS_HIGH, (height - TileData.sand) / (TileData.grass - TileData.sand))
                else if (height <= TileData.mountain)
                    lerp_color(Color.MOUNTAIN_LOW, Color.MOUNTAIN_HIGH, (height - TileData.grass) / (TileData.mountain - TileData.grass))
                else
                    Rgb.init(240, 240, 240);

            image.drawPixel(
                @intCast(x),
                @intCast(y),
                .{
                    .r = @intCast(tile.r),
                    .g = @intCast(tile.g),
                    .b = @intCast(tile.b),
                    .a = 255,
                },
            );
        }
    }
    const tex = try rl.Texture.fromImage(image);
    self.model.materials[0].maps[@intFromEnum(rl.MATERIAL_MAP_DIFFUSE)].texture = tex;
}

fn genTerrainMesh(self: *Self) !rl.Mesh {
    var mesh: rl.Mesh = std.mem.zeroes(rl.Mesh);

    const width = self.size.x;
    const height = self.size.y;

    const vertex_count = width * height;
    const triangle_count = (width - 1) * (height - 1) * 2;

    mesh.vertexCount = @intCast(vertex_count);
    mesh.triangleCount = @intCast(triangle_count);

    mesh.vertices = @ptrCast(@alignCast(c.malloc(vertex_count * 3 * @sizeOf(f32))));
    mesh.normals = @ptrCast(@alignCast(c.malloc(vertex_count * 3 * @sizeOf(f32))));
    mesh.texcoords = @ptrCast(@alignCast(c.malloc(vertex_count * 2 * @sizeOf(f32))));
    mesh.indices = @ptrCast(@alignCast(c.malloc(triangle_count * 3 * @sizeOf(u16))));

    if (mesh.vertices == null or mesh.normals == null or
        mesh.texcoords == null or mesh.indices == null)
        return error.OutOfMemory;

    for (0..height) |y| {
        for (0..width) |x| {
            const index = y * width + x;
            const noise_value = self.getHeight(x, y);

            const x_f = @as(f32, @floatFromInt(x));
            const y_f = @as(f32, @floatFromInt(y));
            const width_f = @as(f32, @floatFromInt(width));
            const height_f = @as(f32, @floatFromInt(height));

            mesh.vertices[index * 3 + 0] = x_f - width_f / 2.0;
            mesh.vertices[index * 3 + 1] = noise_value;
            mesh.vertices[index * 3 + 2] = y_f - height_f / 2.0;

            mesh.texcoords[index * 2 + 0] = @as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(width - 1));
            mesh.texcoords[index * 2 + 1] = @as(f32, @floatFromInt(y)) / @as(f32, @floatFromInt(height - 1));
        }
    }

    var triangle_index: usize = 0;
    for (0..height - 1) |y| {
        for (0..width - 1) |x| {
            const top_left = y * width + x;
            const top_right = top_left + 1;
            const bottom_left = (y + 1) * width + x;
            const bottom_right = bottom_left + 1;

            mesh.indices[triangle_index * 3 + 0] = @intCast(top_left);
            mesh.indices[triangle_index * 3 + 1] = @intCast(bottom_left);
            mesh.indices[triangle_index * 3 + 2] = @intCast(top_right);
            triangle_index += 1;

            mesh.indices[triangle_index * 3 + 0] = @intCast(top_right);
            mesh.indices[triangle_index * 3 + 1] = @intCast(bottom_left);
            mesh.indices[triangle_index * 3 + 2] = @intCast(bottom_right);
            triangle_index += 1;
        }
    }

    for (0..vertex_count) |i| {
        mesh.normals[i * 3 + 0] = 0.0;
        mesh.normals[i * 3 + 1] = 1.0;
        mesh.normals[i * 3 + 2] = 0.0;
    }

    rl.uploadMesh(&mesh, false);

    return mesh;
}

// pub fn getColor(self: *const Self, x: usize, y: usize) Rgb {
//     return self.mapData.items[y].items[x];
// }

pub fn getHeight(self: *const Self, x: usize, y: usize) f32 {
    return self.map_data[y][x];
}

pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
    // Free nested ArrayLists
    for (0..self.map_data.len) |y|
        alloc.free(self.map_data[y]);

    alloc.free(self.map_data);

    // Free GPU resources
    rl.unloadModel(self.model);
}
