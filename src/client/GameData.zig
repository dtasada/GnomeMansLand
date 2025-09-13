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

    pub fn init(alloc: std.mem.Allocator, first_packet: socket_packet.WorldDataChunk) !WorldData {
        var self = WorldData{
            .size = first_packet.total_size,
            .height_map = try alloc.alloc(f32, first_packet.total_size.x * first_packet.total_size.y),
            ._height_map_filled = 0,
            .model = null,
        };

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
        if (self.model) |m| rl.unloadModel(m);
    }

    pub fn genModel(self: *WorldData, settings: Settings, light_shader: rl.Shader) !void {
        self.model = try rl.Model.fromMesh(try self.genTerrainMesh());
        var image = rl.Image.genColor(
            @intCast(self.size.x),
            @intCast(self.size.y),
            .blue,
        );

        for (0..self.size.y) |y| {
            for (0..self.size.x) |x| {
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

                image.drawPixel(@intCast(x), @intCast(y), .{
                    .r = @intCast(tile.r),
                    .g = @intCast(tile.g),
                    .b = @intCast(tile.b),
                    .a = 255,
                });
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

    fn genTerrainMesh(self: *const WorldData) !rl.Mesh {
        var mesh: rl.Mesh = std.mem.zeroes(rl.Mesh);

        const width = self.size.x;
        const height = self.size.y;

        const surface_vertex_count = width * height;
        const surface_triangle_count = (width - 1) * (height - 1) * 2;

        // Floor: 4 verts, 2 triangles
        const floor_vertex_count = 4;
        const floor_triangle_count = 2;

        // Walls: each edge has (N-1) quads = 2*(N-1) triangles, 4*(N-1) verts
        const wall_quads = (width - 1) * 2 + (height - 1) * 2;
        const wall_vertex_count = wall_quads * 4;
        const wall_triangle_count = wall_quads * 2;

        const total_vertex_count = surface_vertex_count + floor_vertex_count + wall_vertex_count;
        const total_triangle_count = surface_triangle_count + floor_triangle_count + wall_triangle_count;

        mesh.vertexCount = @intCast(total_vertex_count);
        mesh.triangleCount = @intCast(total_triangle_count);

        mesh.vertices = @ptrCast(@alignCast(c.malloc(total_vertex_count * 3 * @sizeOf(f32))));
        mesh.normals = @ptrCast(@alignCast(c.malloc(total_vertex_count * 3 * @sizeOf(f32))));
        mesh.texcoords = @ptrCast(@alignCast(c.malloc(total_vertex_count * 2 * @sizeOf(f32))));
        mesh.indices = @ptrCast(@alignCast(c.malloc(total_triangle_count * 3 * @sizeOf(u16))));

        if (mesh.vertices == null or mesh.normals == null or
            mesh.texcoords == null or mesh.indices == null)
            return error.OutOfMemory;

        const width_f: f32 = @floatFromInt(width);
        const height_f: f32 = @floatFromInt(height);
        const floor_y: f32 = -100.0;

        var vtx: usize = 0;
        var tri: usize = 0;

        // -------------------------
        // 1. Terrain surface verts
        // -------------------------
        for (0..height) |y| {
            for (0..width) |x| {
                // const index = y * width + x;
                const noise_value = self.getHeight(x, y);

                mesh.vertices[vtx * 3 + 0] = @as(f32, @floatFromInt(x)) - width_f / 2.0;
                mesh.vertices[vtx * 3 + 1] = noise_value;
                mesh.vertices[vtx * 3 + 2] = @as(f32, @floatFromInt(y)) - height_f / 2.0;

                mesh.texcoords[vtx * 2 + 0] = @as(f32, @floatFromInt(x)) / (width_f - 1);
                mesh.texcoords[vtx * 2 + 1] = @as(f32, @floatFromInt(y)) / (height_f - 1);

                vtx += 1;
            }
        }

        // Surface indices
        for (0..height - 1) |y| {
            for (0..width - 1) |x| {
                const top_left = y * width + x;
                const top_right = top_left + 1;
                const bottom_left = (y + 1) * width + x;
                const bottom_right = bottom_left + 1;

                mesh.indices[tri * 3 + 0] = @intCast(top_left);
                mesh.indices[tri * 3 + 1] = @intCast(bottom_left);
                mesh.indices[tri * 3 + 2] = @intCast(top_right);
                tri += 1;

                mesh.indices[tri * 3 + 0] = @intCast(top_right);
                mesh.indices[tri * 3 + 1] = @intCast(bottom_left);
                mesh.indices[tri * 3 + 2] = @intCast(bottom_right);
                tri += 1;
            }
        }

        // -------------------------
        // 2. Floor
        // -------------------------
        const floor_start = vtx;

        const fx0: f32 = -width_f / 2.0;
        const fx1: f32 = width_f / 2.0;
        const fz0: f32 = -height_f / 2.0;
        const fz1: f32 = height_f / 2.0;

        const floor_verts = [_]rl.Vector3{
            .{ .x = fx0, .y = floor_y, .z = fz0 },
            .{ .x = fx1, .y = floor_y, .z = fz0 },
            .{ .x = fx1, .y = floor_y, .z = fz1 },
            .{ .x = fx0, .y = floor_y, .z = fz1 },
        };

        for (floor_verts) |fv| {
            mesh.vertices[vtx * 3 + 0] = fv.x;
            mesh.vertices[vtx * 3 + 1] = fv.y;
            mesh.vertices[vtx * 3 + 2] = fv.z;
            mesh.texcoords[vtx * 2 + 0] = (fv.x - fx0) / (fx1 - fx0);
            mesh.texcoords[vtx * 2 + 1] = (fv.z - fz0) / (fz1 - fz0);
            mesh.normals[vtx * 3 + 0] = 0;
            mesh.normals[vtx * 3 + 1] = 1;
            mesh.normals[vtx * 3 + 2] = 0;
            vtx += 1;
        }

        mesh.indices[tri * 3 + 0] = @truncate(floor_start + 0);
        mesh.indices[tri * 3 + 1] = @truncate(floor_start + 1);
        mesh.indices[tri * 3 + 2] = @truncate(floor_start + 2);
        tri += 1;
        mesh.indices[tri * 3 + 0] = @truncate(floor_start + 0);
        mesh.indices[tri * 3 + 1] = @truncate(floor_start + 2);
        mesh.indices[tri * 3 + 2] = @truncate(floor_start + 3);
        tri += 1;

        // -------------------------
        // 3. Walls (loop edges)
        // -------------------------
        // helper inline fn

        // West wall (x=0 col)
        for (0..height - 1) |y| {
            const top1 = self.getHeight(0, y);
            const top2 = self.getHeight(0, y + 1);
            const z1 = @as(f32, @floatFromInt(y)) - height_f / 2.0;
            const z2 = @as(f32, @floatFromInt(y + 1)) - height_f / 2.0;
            const x = -width_f / 2.0;
            addWallQuad(.{ .x = x, .y = top1, .z = z1 }, .{ .x = x, .y = floor_y, .z = z1 }, .{ .x = x, .y = top2, .z = z2 }, .{ .x = x, .y = floor_y, .z = z2 }, .{ .x = -1, .y = 0, .z = 0 }, &mesh, &vtx, &tri);
        }
        // East wall (x=width-1)
        for (0..height - 1) |y| {
            const top1 = self.getHeight(width - 1, y);
            const top2 = self.getHeight(width - 1, y + 1);
            const z1 = @as(f32, @floatFromInt(y)) - height_f / 2.0;
            const z2 = @as(f32, @floatFromInt(y + 1)) - height_f / 2.0;
            const x = width_f / 2.0;
            addWallQuad(.{ .x = x, .y = top1, .z = z1 }, .{ .x = x, .y = floor_y, .z = z1 }, .{ .x = x, .y = top2, .z = z2 }, .{ .x = x, .y = floor_y, .z = z2 }, .{ .x = 1, .y = 0, .z = 0 }, &mesh, &vtx, &tri);
        }
        // North wall (y=0 row)
        for (0..width - 1) |x_idx| {
            const top1 = self.getHeight(x_idx, 0);
            const top2 = self.getHeight(x_idx + 1, 0);
            const x1 = @as(f32, @floatFromInt(x_idx)) - width_f / 2.0;
            const x2 = @as(f32, @floatFromInt(x_idx + 1)) - width_f / 2.0;
            const z = -height_f / 2.0;
            addWallQuad(.{ .x = x1, .y = top1, .z = z }, .{ .x = x1, .y = floor_y, .z = z }, .{ .x = x2, .y = top2, .z = z }, .{ .x = x2, .y = floor_y, .z = z }, .{ .x = 0, .y = 0, .z = -1 }, &mesh, &vtx, &tri);
        }
        // South wall (y=height-1 row)
        for (0..width - 1) |x_idx| {
            const top1 = self.getHeight(x_idx, height - 1);
            const top2 = self.getHeight(x_idx + 1, height - 1);
            const x1 = @as(f32, @floatFromInt(x_idx)) - width_f / 2.0;
            const x2 = @as(f32, @floatFromInt(x_idx + 1)) - width_f / 2.0;
            const z = height_f / 2.0;
            addWallQuad(.{ .x = x1, .y = top1, .z = z }, .{ .x = x1, .y = floor_y, .z = z }, .{ .x = x2, .y = top2, .z = z }, .{ .x = x2, .y = floor_y, .z = z }, .{ .x = 0, .y = 0, .z = 1 }, &mesh, &vtx, &tri);
        }

        // -------------------------
        // 4. Normals for surface (recalc)
        // -------------------------
        for (0..height) |y| {
            for (0..width) |x| {
                const index = y * width + x;

                const x_prev = if (x > 0) x - 1 else x;
                const x_next = if (x < width - 1) x + 1 else x;
                const y_prev = if (y > 0) y - 1 else y;
                const y_next = if (y < height - 1) y + 1 else y;

                const height_left = self.getHeight(x_prev, y);
                const height_right = self.getHeight(x_next, y);
                const height_up = self.getHeight(x, y_prev);
                const height_down = self.getHeight(x, y_next);

                const dx = (height_right - height_left) / 2.0;
                const dy = (height_down - height_up) / 2.0;

                const normal_vec = rl.Vector3.init(-dx, 1.0, -dy).normalize();

                mesh.normals[index * 3 + 0] = normal_vec.x;
                mesh.normals[index * 3 + 1] = normal_vec.y;
                mesh.normals[index * 3 + 2] = normal_vec.z;
            }
        }

        rl.uploadMesh(&mesh, false);

        std.debug.print("Vertices: {}, Triangles: {}\n", .{ mesh.vertexCount, mesh.triangleCount });
        std.debug.print("Written vtx: {}, tri: {}\n", .{ vtx, tri });
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
