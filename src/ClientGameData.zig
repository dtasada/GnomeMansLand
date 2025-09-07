//! Container for game data owned by the client
const std = @import("std");
const rl = @import("raylib");
const commons = @import("commons.zig");
const c = @cImport({
    @cInclude("stdlib.h");
});

const SocketPacket = @import("SocketPacket.zig");
const Settings = @import("Settings.zig");
pub const Player = @import("ServerGameData.zig").Player;

const ClientGameData = @This();

world_data: ?WorldData,
players: std.ArrayList(Player),

pub fn init(alloc: std.mem.Allocator) !ClientGameData {
    return .{
        .world_data = null,
        .players = try std.ArrayList(Player).initCapacity(alloc, 1),
    };
}

pub fn deinit(self: *ClientGameData, alloc: std.mem.Allocator) void {
    if (self.world_data) |*world_data|
        world_data.deinit(alloc);

    self.players.deinit(alloc);
}

pub const WorldData = struct {
    height_map: []f32, // 2d in practice
    _height_map_filled: usize,
    size: commons.v2u,
    model: ?rl.Model,

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

        pub fn lerp(lhs: Rgb, rhs: Rgb, m: f32) Rgb {
            return lhs.add(rhs.subtract(lhs).scale(m)); // c1+(c2-c1)*m
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

    pub fn init(alloc: std.mem.Allocator, first_packet: SocketPacket.WorldDataChunk) !WorldData {
        var self: WorldData = undefined;

        self.size = first_packet.total_size;
        self.height_map = try alloc.alloc(f32, self.size.x * self.size.y);
        self._height_map_filled = 0;
        self.model = null;

        self.addChunk(first_packet);

        return self;
    }

    pub fn addChunk(self: *WorldData, world_data_chunk: SocketPacket.WorldDataChunk) void {
        @memcpy(self.height_map[world_data_chunk.float_start_index..world_data_chunk.float_end_index], world_data_chunk.height_map);
        self._height_map_filled += world_data_chunk.height_map.len;
    }

    pub fn isComplete(self: *WorldData) bool {
        return self._height_map_filled == self.size.x * self.size.y;
    }

    pub fn deinit(self: *WorldData, alloc: std.mem.Allocator) void {
        alloc.free(self.height_map);

        // Free GPU resources
        if (self.model) |m| rl.unloadModel(m);
    }

    pub fn genModel(self: *WorldData, st: *const Settings, light_shader: rl.Shader) !void {
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
                        Color.WATER_LOW.lerp(Color.WATER_HIGH, height / TileData.water)
                    else if (height <= TileData.sand)
                        Color.SAND_LOW.lerp(Color.SAND_HIGH, (height - TileData.water) / (TileData.sand - TileData.water))
                    else if (height <= TileData.grass)
                        Color.GRASS_LOW.lerp(Color.GRASS_HIGH, (height - TileData.sand) / (TileData.grass - TileData.sand))
                    else if (height <= TileData.mountain)
                        Color.MOUNTAIN_LOW.lerp(Color.MOUNTAIN_HIGH, (height - TileData.grass) / (TileData.mountain - TileData.grass))
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
        const tex = try rl.Texture.fromImage(image); // do not deinit the texture lol

        if (self.model) |*m| {
            m.materials[0].maps[@intFromEnum(rl.MATERIAL_MAP_DIFFUSE)].texture = tex;
            m.materials[0].shader = light_shader;
        }

        const translation_matrix = rl.Matrix.translate(
            @as(f32, @floatFromInt(self.size.x)) * 0.5,
            0.0,
            @as(f32, @floatFromInt(self.size.y)) * 0.5,
        );

        self.model.?.transform = self.model.?.transform.multiply(translation_matrix);
    }

    fn genTerrainMesh(self: *WorldData) !rl.Mesh {
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

    pub fn getHeight(self: *WorldData, x: usize, y: usize) f32 {
        return self.height_map[y * self.size.x + x];
    }
};
