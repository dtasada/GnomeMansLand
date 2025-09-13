//! Container for game data owned by the client
const std = @import("std");
const rl = @import("raylib");
const commons = @import("../commons.zig");
const c = @cImport({
    @cInclude("stdlib.h");
});

const socket_packet = @import("../socket_packet.zig");

const Settings = @import("Settings.zig");
const Player = @import("../server/GameData.zig").Player;

const GameData = @This();

const MODEL_RESOLUTION = 64;

world_data: ?WorldData,
players: std.ArrayList(Player),

pub fn init(alloc: std.mem.Allocator) !GameData {
    return .{
        .world_data = null,
        .players = try std.ArrayList(Player).initCapacity(alloc, 1),
    };
}

pub fn deinit(self: *GameData, alloc: std.mem.Allocator) void {
    if (self.world_data) |*world_data|
        world_data.deinit(alloc);

    self.players.deinit(alloc);
}

pub const WorldData = struct {
    height_map: []f32, // 2d in practice
    _height_map_filled: usize,
    size: commons.v2u,
    models: []?rl.Model,

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

    pub fn init(alloc: std.mem.Allocator, first_packet: socket_packet.WorldDataChunk) !WorldData {
        const chunks_x = (first_packet.total_size.x + MODEL_RESOLUTION - 1) / MODEL_RESOLUTION;
        const chunks_y = (first_packet.total_size.y + MODEL_RESOLUTION - 1) / MODEL_RESOLUTION;
        const amount_of_models = chunks_x * chunks_y;

        var self = WorldData{
            .size = first_packet.total_size,
            .height_map = try alloc.alloc(f32, first_packet.total_size.x * first_packet.total_size.y),
            ._height_map_filled = 0,
            .models = try alloc.alloc(?rl.Model, amount_of_models),
        };
        @memset(self.models, null);

        self.addChunk(first_packet);
        return self;
    }

    pub fn addChunk(self: *WorldData, world_data_chunk: socket_packet.WorldDataChunk) void {
        @memcpy(self.height_map[world_data_chunk.float_start_index..world_data_chunk.float_end_index], world_data_chunk.height_map);
        self._height_map_filled += world_data_chunk.height_map.len;
    }

    pub fn isComplete(self: *const WorldData) bool {
        return self._height_map_filled == self.size.x * self.size.y;
    }

    pub fn deinit(self: *const WorldData, alloc: std.mem.Allocator) void {
        alloc.free(self.height_map);

        // Free GPU resources
        for (self.models) |model| if (model) |m| rl.unloadModel(m);
        alloc.free(self.models);
    }

    pub fn genModel(self: *WorldData, settings: Settings, light_shader: rl.Shader) !void {
        const model_index = blk: {
            var idx: ?usize = null;
            for (self.models, 0..) |model, i|
                if (model == null) {
                    idx = i;
                    break;
                };

            break :blk idx orelse return;
        };

        const chunks_x = (self.size.x + MODEL_RESOLUTION - 1) / MODEL_RESOLUTION;
        const chunk_x = model_index % chunks_x;
        const chunk_y = model_index / chunks_x;

        const min_x = chunk_x * MODEL_RESOLUTION;
        const min_y = chunk_y * MODEL_RESOLUTION;
        const max_x = @min(min_x + MODEL_RESOLUTION, self.size.x);
        const max_y = @min(min_y + MODEL_RESOLUTION, self.size.y);

        var image = rl.Image.genColor(
            @intCast(MODEL_RESOLUTION),
            @intCast(MODEL_RESOLUTION),
            .blue,
        );

        for (min_y..max_y) |y| {
            for (min_x..max_x) |x| {
                if (x >= self.size.x or y >= self.size.y) continue;

                const height = (self.getHeight(x, y) + settings.server.world_generation.amplitude) / (2 * settings.server.world_generation.amplitude);
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
                    @intCast(x - min_x),
                    @intCast(y - min_y),
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

        const model = &self.models[model_index];
        model.* = try rl.Model.fromMesh(try self.genTerrainMesh(min_x, max_x, min_y, max_y));
        model.*.?.materials[0].maps[@intFromEnum(rl.MATERIAL_MAP_DIFFUSE)].texture = tex;
        model.*.?.materials[0].shader = light_shader;

        model.*.?.transform = rl.Matrix.translate(
            @as(f32, @floatFromInt(chunk_x * MODEL_RESOLUTION)),
            0.0,
            @as(f32, @floatFromInt(chunk_y * MODEL_RESOLUTION)),
        );
    }

    fn genTerrainMesh(
        self: *const WorldData,
        min_x: usize,
        max_x: usize,
        min_y: usize,
        max_y: usize,
    ) !rl.Mesh {
        var mesh: rl.Mesh = std.mem.zeroes(rl.Mesh);

        const width = max_x - min_x;
        const height = max_y - min_y;

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

        // --- Vertices + texcoords
        for (0..height) |yy| {
            for (0..width) |xx| {
                const index = yy * width + xx;
                const world_x = min_x + xx;
                const world_y = min_y + yy;

                const noise_value = self.getHeight(world_x, world_y);

                // Local vertex position (chunk-local, not world!)
                mesh.vertices[index * 3 + 0] = @as(f32, @floatFromInt(xx));
                mesh.vertices[index * 3 + 1] = noise_value;
                mesh.vertices[index * 3 + 2] = @as(f32, @floatFromInt(yy));

                // Local UVs, normalized across the chunk
                mesh.texcoords[index * 2 + 0] = @as(f32, @floatFromInt(xx)) / @as(f32, @floatFromInt(width - 1));
                mesh.texcoords[index * 2 + 1] = @as(f32, @floatFromInt(yy)) / @as(f32, @floatFromInt(height - 1));
            }
        }

        // --- Indices
        var triangle_index: usize = 0;
        for (0..height - 1) |yy| {
            for (0..width - 1) |xx| {
                const top_left = yy * width + xx;
                const top_right = top_left + 1;
                const bottom_left = (yy + 1) * width + xx;
                const bottom_right = bottom_left + 1;

                mesh.indices[triangle_index * 3 + 0] = @truncate(top_left);
                mesh.indices[triangle_index * 3 + 1] = @truncate(bottom_left);
                mesh.indices[triangle_index * 3 + 2] = @truncate(top_right);
                triangle_index += 1;

                mesh.indices[triangle_index * 3 + 0] = @truncate(top_right);
                mesh.indices[triangle_index * 3 + 1] = @truncate(bottom_left);
                mesh.indices[triangle_index * 3 + 2] = @truncate(bottom_right);
                triangle_index += 1;
            }
        }

        // --- Normals
        for (0..height) |yy| {
            for (0..width) |xx| {
                const index = yy * width + xx;
                const world_x = min_x + xx;
                const world_y = min_y + yy;

                const x_prev = if (world_x > 0) world_x - 1 else world_x;
                const x_next = if (world_x < self.size.x - 1) world_x + 1 else world_x;
                const y_prev = if (world_y > 0) world_y - 1 else world_y;
                const y_next = if (world_y < self.size.y - 1) world_y + 1 else world_y;

                const height_left = self.getHeight(x_prev, world_y);
                const height_right = self.getHeight(x_next, world_y);
                const height_up = self.getHeight(world_x, y_prev);
                const height_down = self.getHeight(world_x, y_next);

                const dx = (height_right - height_left) / 2.0;
                const dy = (height_down - height_up) / 2.0;

                const normal_vec = rl.Vector3{ .x = -dx, .y = 1.0, .z = -dy };
                const normal = normal_vec.normalize();

                mesh.normals[index * 3 + 0] = normal.x;
                mesh.normals[index * 3 + 1] = normal.y;
                mesh.normals[index * 3 + 2] = normal.z;
            }
        }

        rl.uploadMesh(&mesh, false);
        return mesh;
    }

    inline fn addWallQuad(
        a_top: rl.Vector3,
        a_bot: rl.Vector3,
        b_top: rl.Vector3,
        b_bot: rl.Vector3,
        normal: rl.Vector3,
        mesh: *rl.Mesh,
        vtx: *usize,
        tri: *usize,
    ) void {
        const start = vtx.*;
        const verts = [_]rl.Vector3{ a_top, a_bot, b_top, b_bot };
        for (verts) |v| {
            mesh.vertices[vtx.* * 3 + 0] = v.x;
            mesh.vertices[vtx.* * 3 + 1] = v.y;
            mesh.vertices[vtx.* * 3 + 2] = v.z;
            mesh.texcoords[vtx.* * 2 + 0] = 0; // simple
            mesh.texcoords[vtx.* * 2 + 1] = 0;
            mesh.normals[vtx.* * 3 + 0] = normal.x;
            mesh.normals[vtx.* * 3 + 1] = normal.y;
            mesh.normals[vtx.* * 3 + 2] = normal.z;
            vtx.* += 1;
        }
        // two triangles
        mesh.indices[tri.* * 3 + 0] = @truncate(start + 0);
        mesh.indices[tri.* * 3 + 1] = @truncate(start + 1);
        mesh.indices[tri.* * 3 + 2] = @truncate(start + 2);
        tri.* += 1;
        mesh.indices[tri.* * 3 + 0] = @truncate(start + 2);
        mesh.indices[tri.* * 3 + 1] = @truncate(start + 1);
        mesh.indices[tri.* * 3 + 2] = @truncate(start + 3);
        tri.* += 1;
    }

    pub fn getHeight(self: *const WorldData, x: usize, y: usize) f32 {
        return self.height_map[y * self.size.x + x];
    }
};
