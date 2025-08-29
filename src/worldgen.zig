const rl = @import("raylib");
const std = @import("std");
const c = @cImport({
    @cInclude("stdlib.h");
});

const Settings = @import("settings.zig");
const Perlin = @import("perlin.zig");

const Self = @This();

size: [2]u32,
renderScale: f32,
// mapData: std.ArrayList(std.ArrayList(Rgb)),
mapData: std.ArrayList(std.ArrayList(f32)),
model: rl.Model,
mesh: rl.Mesh,

const Rgb = struct {
    r: u8,
    g: u8,
    b: u8,

    pub fn init(r: u8, g: u8, b: u8) Rgb {
        return .{ .r = r, .g = g, .b = b };
    }

    pub fn add(lhs: Rgb, rhs: Rgb) Rgb {
        return Rgb.init(lhs.r + rhs.r, lhs.g + rhs.g, lhs.b + rhs.b);
    }

    pub fn subtract(lhs: Rgb, rhs: Rgb) Rgb {
        return Rgb.init(lhs.r -| rhs.r, lhs.g -| rhs.g, lhs.b -| rhs.b);
    }

    pub fn scale(lhs: Rgb, m: f32) Rgb {
        if (m > 1.0) unreachable;
        if (m < 0.0) unreachable;
        return Rgb.init(
            @intFromFloat(@as(f32, @floatFromInt(lhs.r)) * m),
            @intFromFloat(@as(f32, @floatFromInt(lhs.g)) * m),
            @intFromFloat(@as(f32, @floatFromInt(lhs.b)) * m),
        );
    }
};

const Color = struct {
    const waterLow = Rgb.init(0, 0, 50);
    const waterHigh = Rgb.init(30, 110, 140);
    const sandLow = Rgb.init(237, 206, 178);
    const sandHigh = Rgb.init(255, 245, 193);
    const grassLow = Rgb.init(10, 155, 104);
    const grassHigh = Rgb.init(0, 120, 80);
    const mountainLow = Rgb.init(80, 80, 80);
    const mountainHigh = Rgb.init(120, 120, 120);
};

const TileData = struct {
    const water: f32 = 0.48;
    const sand: f32 = 0.51;
    const grass: f32 = 0.61;
    const mountain: f32 = 0.68;
    const snow: f32 = 1.0;
};

fn lerp_color(c1: Rgb, c2: Rgb, m: f32) Rgb {
    return c1.add(c2.subtract(c1).scale(m));
}

pub fn init(alloc: std.mem.Allocator, st: Settings) !Self {
    var self = Self{
        .size = st.world_generation.resolution,
        .mapData = .empty,
        .renderScale = 1.0,
        .model = undefined,
        .mesh = undefined,
    };

    try self.mapData.resize(alloc, self.size[1]);
    for (self.mapData.items) |*column| {
        column.* = .empty;
        try column.resize(alloc, self.size[0]);
    }

    const seed: u32 = st.world_generation.seed orelse rand: {
        var seed: u32 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        var rand = std.Random.DefaultPrng.init(seed);
        break :rand rand.random().intRangeAtMost(u32, 0, std.math.maxInt(u32));
    };

    var pn = try Perlin.init(alloc, seed);
    defer pn.deinit(alloc);

    for (0..self.size[1]) |y| {
        for (0..self.size[0]) |x| {
            var freq = 7.68 * st.world_generation.frequency / @as(f32, @floatFromInt(self.size[0]));
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

            self.mapData.items[y].items[x] = height;
        }
    }

    try self.genTerrainMesh();
    self.model = try rl.Model.fromMesh(self.mesh);

    var image = rl.Image.genColor(
        @intCast(self.size[0]),
        @intCast(self.size[1]),
        .blue,
    );
    for (0..self.size[1]) |y| {
        for (0..self.size[0]) |x| {
            const height = (self.getHeight(x, y) + st.world_generation.amplitude) / (2 * st.world_generation.amplitude);
            const tile: Rgb =
                if (height <= TileData.water)
                    lerp_color(Color.waterLow, Color.waterHigh, height / TileData.water)
                else if (height <= TileData.sand)
                    lerp_color(Color.sandLow, Color.sandHigh, (height - TileData.water) / (TileData.sand - TileData.water))
                else if (height <= TileData.grass)
                    lerp_color(Color.grassLow, Color.grassHigh, (height - TileData.sand) / (TileData.grass - TileData.sand))
                else if (height <= TileData.mountain)
                    lerp_color(Color.mountainLow, Color.mountainHigh, (height - TileData.grass) / (TileData.mountain - TileData.grass))
                else
                    Rgb.init(240, 240, 240);

            image.drawPixel(
                @intCast(x),
                @intCast(y),
                .{ .r = tile.r, .g = tile.g, .b = tile.b, .a = 255 },
            );
        }
    }
    const tex = try rl.Texture.fromImage(image);
    self.model.materials[0].maps[@intFromEnum(rl.MATERIAL_MAP_DIFFUSE)].texture = tex;

    std.debug.print("World generated\n", .{});
    return self;
}

fn genTerrainMesh(self: *Self) !void {
    self.mesh = std.mem.zeroes(rl.Mesh);
    const heightScale = 1.0;

    const width = self.mapData.items[0].items.len;
    const height = self.mapData.items.len;

    const vertexCount = width * height;
    const triangleCount = (width - 1) * (height - 1) * 2;

    self.mesh.vertexCount = @intCast(vertexCount);
    self.mesh.triangleCount = @intCast(triangleCount);

    self.mesh.vertices = @ptrCast(@alignCast(c.malloc(vertexCount * 3 * @sizeOf(f32))));
    self.mesh.normals = @ptrCast(@alignCast(c.malloc(vertexCount * 3 * @sizeOf(f32))));
    self.mesh.texcoords = @ptrCast(@alignCast(c.malloc(vertexCount * 2 * @sizeOf(f32))));
    self.mesh.indices = @ptrCast(@alignCast(c.malloc(triangleCount * 3 * @sizeOf(u16))));

    if (self.mesh.vertices == null or self.mesh.normals == null or
        self.mesh.texcoords == null or self.mesh.indices == null)
        return error.OutOfMemory;

    for (0..height) |y| {
        for (0..width) |x| {
            const index = y * width + x;
            const noiseValue = self.getHeight(x, y);

            const x_f = @as(f32, @floatFromInt(x));
            const y_f = @as(f32, @floatFromInt(y));
            const width_f = @as(f32, @floatFromInt(width));
            const height_f = @as(f32, @floatFromInt(height));

            self.mesh.vertices[index * 3 + 0] = x_f - width_f / 2.0;
            self.mesh.vertices[index * 3 + 1] = noiseValue * heightScale;
            self.mesh.vertices[index * 3 + 2] = y_f - height_f / 2.0;

            self.mesh.texcoords[index * 2 + 0] = @as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(width - 1));
            self.mesh.texcoords[index * 2 + 1] = @as(f32, @floatFromInt(y)) / @as(f32, @floatFromInt(height - 1));
        }
    }

    var triIndex: usize = 0;
    for (0..height - 1) |y| {
        for (0..width - 1) |x| {
            const topLeft = y * width + x;
            const topRight = topLeft + 1;
            const bottomLeft = (y + 1) * width + x;
            const bottomRight = bottomLeft + 1;

            self.mesh.indices[triIndex * 3 + 0] = @intCast(topLeft);
            self.mesh.indices[triIndex * 3 + 1] = @intCast(bottomLeft);
            self.mesh.indices[triIndex * 3 + 2] = @intCast(topRight);
            triIndex += 1;

            self.mesh.indices[triIndex * 3 + 0] = @intCast(topRight);
            self.mesh.indices[triIndex * 3 + 1] = @intCast(bottomLeft);
            self.mesh.indices[triIndex * 3 + 2] = @intCast(bottomRight);
            triIndex += 1;
        }
    }

    for (0..vertexCount) |i| {
        self.mesh.normals[i * 3 + 0] = 0.0;
        self.mesh.normals[i * 3 + 1] = 1.0;
        self.mesh.normals[i * 3 + 2] = 0.0;
    }

    rl.uploadMesh(&self.mesh, false);
}

// pub fn getColor(self: *const Self, x: usize, y: usize) Rgb {
//     return self.mapData.items[y].items[x];
// }

pub fn getHeight(self: *const Self, x: usize, y: usize) f32 {
    return self.mapData.items[y].items[x];
}

pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
    for (self.mapData.items) |*col|
        col.deinit(alloc);

    self.mapData.deinit(alloc);
}
