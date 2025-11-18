const std = @import("std");
const c = @cImport({
    @cInclude("stdlib.h");
});

const rl = @import("raylib");

const commons = @import("commons");
const socket_packet = @import("socket_packet");
const Settings = @import("client").Settings;

const Self = @This();

// Reduced model resolution for larger maps
const MODEL_RESOLUTION = 32; // Reduced from 64

height_map: []f32, // 2d in practice
_height_map_filled: usize = 0,
size: commons.v2u,
models: []?rl.Model,
models_generated: usize = 0,
gen_models_thread: ?std.Thread = null,

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
        const m_ = if (m >= 0) m else 0;
        return Rgb.init(
            @intFromFloat(@as(f32, @floatFromInt(lhs.r)) * m_),
            @intFromFloat(@as(f32, @floatFromInt(lhs.g)) * m_),
            @intFromFloat(@as(f32, @floatFromInt(lhs.b)) * m_),
        );
    }

    pub fn lerp(lhs: Rgb, rhs: Rgb, m: f32) Rgb {
        return lhs.add(rhs.subtract(lhs).scale(m));
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

pub fn init(alloc: std.mem.Allocator, first_packet: socket_packet.WorldDataChunk) !Self {
    const chunks_x = (first_packet.total_size.x + MODEL_RESOLUTION - 1) / MODEL_RESOLUTION;
    const chunks_y = (first_packet.total_size.y + MODEL_RESOLUTION - 1) / MODEL_RESOLUTION;
    const amount_of_models = chunks_x * chunks_y;

    // Add safety check for too many models
    if (amount_of_models > 2048) {
        commons.print("Warning: {} models requested, this may cause performance issues\n", .{amount_of_models}, .yellow);
    }

    var self: Self = .{
        .size = first_packet.total_size,
        .height_map = try alloc.alloc(f32, first_packet.total_size.x * first_packet.total_size.y),
        .models = b: {
            const m = try alloc.alloc(?rl.Model, amount_of_models);
            @memset(m, null);
            break :b m;
        },
    };

    self.addChunk(first_packet);
    return self;
}

pub fn addChunk(self: *Self, world_data_chunk: socket_packet.WorldDataChunk) void {
    @memcpy(self.height_map[world_data_chunk.float_start_index..world_data_chunk.float_end_index], world_data_chunk.height_map);
    self._height_map_filled += world_data_chunk.height_map.len;
}

pub fn allFloatsDownloaded(self: *const Self) bool {
    return self._height_map_filled == self.height_map.len;
}

pub fn allModelsGenerated(self: *const Self) bool {
    return self.models_generated == self.models.len;
}

pub fn deinit(self: *const Self, alloc: std.mem.Allocator) void {
    alloc.free(self.height_map);

    if (self.gen_models_thread) |t| {
        t.join();
    }

    // Free GPU resources
    for (self.models) |model| if (model) |m| rl.unloadModel(m);
    alloc.free(self.models);
}

pub fn genModels(self: *Self, _: Settings, light_shader: rl.Shader) !void {
    for (0..self.models.len) |model_index| {
        const chunks_x = (self.size.x + MODEL_RESOLUTION - 1) / MODEL_RESOLUTION;
        const chunk_x = model_index % chunks_x;
        const chunk_y = model_index / chunks_x;

        const min_x = chunk_x * MODEL_RESOLUTION;
        const min_y = chunk_y * MODEL_RESOLUTION;
        const max_x = @min(min_x + MODEL_RESOLUTION, self.size.x);
        const max_y = @min(min_y + MODEL_RESOLUTION, self.size.y);

        // Add bounds checking
        if (min_x >= self.size.x or min_y >= self.size.y) {
            commons.print(
                "Model generation bounds error: min_x={}, min_y={}, size={}x{}\n",
                .{ min_x, min_y, self.size.x, self.size.y },
                .red,
            );
            return;
        }

        var image = rl.Image.genColor(
            @intCast(MODEL_RESOLUTION),
            @intCast(MODEL_RESOLUTION),
            .blue,
        );
        defer image.unload(); // Make sure to unload the image

        for (min_y..max_y) |y| {
            for (min_x..max_x) |x| {
                if (x >= self.size.x or y >= self.size.y) continue;

                // TODOO: move worldgen settings to server/client shared
                const AMPLITUDE = 180;
                const height = (self.getHeight(x, y) + AMPLITUDE) / (2 * AMPLITUDE);
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
                        .r = @intCast(@max(0, @min(255, tile.r))), // Clamp values
                        .g = @intCast(@max(0, @min(255, tile.g))),
                        .b = @intCast(@max(0, @min(255, tile.b))),
                        .a = 255,
                    },
                );
            }
        }

        const tex = rl.Texture.fromImage(image) catch |err| {
            commons.print(
                "Failed to create texture: {}\n",
                .{err},
                .red,
            );
            return;
        };

        errdefer tex.unload();

        const mesh = self.genTerrainMesh(min_x, max_x, min_y, max_y) catch |err| {
            commons.print(
                "Failed to generate terrain mesh for chunk {}: {}\n",
                .{ model_index, err },
                .red,
            );
            return;
        };

        const model = &self.models[model_index];
        model.* = rl.Model.fromMesh(mesh) catch |err| {
            commons.print(
                "Failed to create model from mesh for chunk {}: {}\n",
                .{ model_index, err },
                .red,
            );
            mesh.unload();
            return;
        };

        model.*.?.materials[0].maps[@intFromEnum(rl.MATERIAL_MAP_DIFFUSE)].texture = tex;
        model.*.?.materials[0].shader = light_shader;
        self.models_generated += 1;
    }
}

fn genTerrainMesh(
    self: *const Self,
    min_x: usize,
    max_x: usize,
    min_y: usize,
    max_y: usize,
) !rl.Mesh {
    var mesh: rl.Mesh = std.mem.zeroes(rl.Mesh);

    const width = max_x - min_x;
    const height = max_y - min_y;

    const mesh_width = width + 1;
    const mesh_height = height + 1;

    const vertex_count = mesh_width * mesh_height;
    const triangle_count = (mesh_width - 1) * (mesh_height - 1) * 2;

    // Add safety check for reasonable mesh sizes
    if (vertex_count > 10000 or triangle_count > 20000) {
        commons.print("Large mesh detected: {} vertices, {} triangles\n", .{ vertex_count, triangle_count }, .yellow);
    }

    mesh.vertexCount = @intCast(vertex_count);
    mesh.triangleCount = @intCast(triangle_count);

    // Use Zig allocator instead of c.malloc for better error handling
    const vertices_size = vertex_count * 3 * @sizeOf(f32);
    const normals_size = vertex_count * 3 * @sizeOf(f32);
    const texcoords_size = vertex_count * 2 * @sizeOf(f32);
    const indices_size = triangle_count * 3 * @sizeOf(u16);

    // Check total memory requirement
    const total_memory = vertices_size + normals_size + texcoords_size + indices_size;
    if (total_memory > 50 * 1024 * 1024) { // 50MB limit per mesh
        commons.print("Mesh too large: {} bytes", .{total_memory}, .red);
        return error.MeshTooLarge;
    }

    // we use malloc because raylib requires using malloc to allocate and free its resources.
    mesh.vertices = @ptrCast(@alignCast(c.malloc(vertices_size)));
    mesh.normals = @ptrCast(@alignCast(c.malloc(normals_size)));
    mesh.texcoords = @ptrCast(@alignCast(c.malloc(texcoords_size)));
    mesh.indices = @ptrCast(@alignCast(c.malloc(indices_size)));

    if (mesh.vertices == null or mesh.normals == null or
        mesh.texcoords == null or mesh.indices == null)
    {
        // Clean up any allocated memory
        if (mesh.vertices != null) c.free(mesh.vertices);
        if (mesh.normals != null) c.free(mesh.normals);
        if (mesh.texcoords != null) c.free(mesh.texcoords);
        if (mesh.indices != null) c.free(mesh.indices);
        return error.OutOfMemory;
    }

    // --- Vertices + texcoords
    for (0..mesh_height) |yy| {
        for (0..mesh_width) |xx| {
            const index = yy * mesh_width + xx;
            const world_x = min_x + xx;
            const world_y = min_y + yy;

            const safe_world_x = @min(world_x, self.size.x - 1);
            const safe_world_y = @min(world_y, self.size.y - 1);
            const height_value = self.getHeight(safe_world_x, safe_world_y);

            // Use world coordinates (original approach was correct)
            mesh.vertices[index * 3 + 0] = @as(f32, @floatFromInt(world_x));
            mesh.vertices[index * 3 + 1] = height_value;
            mesh.vertices[index * 3 + 2] = @as(f32, @floatFromInt(world_y));

            mesh.texcoords[index * 2 + 0] = @as(f32, @floatFromInt(xx)) / @as(f32, @floatFromInt(mesh_width - 1));
            mesh.texcoords[index * 2 + 1] = @as(f32, @floatFromInt(yy)) / @as(f32, @floatFromInt(mesh_height - 1));
        }
    }

    // --- Indices
    var triangle_index: usize = 0;
    for (0..mesh_height - 1) |yy| {
        for (0..mesh_width - 1) |xx| {
            const top_left = yy * mesh_width + xx;
            const top_right = top_left + 1;
            const bottom_left = (yy + 1) * mesh_width + xx;
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
    for (0..mesh_height) |yy| {
        for (0..mesh_width) |xx| {
            const index = yy * mesh_width + xx;
            const world_x = min_x + xx;
            const world_y = min_y + yy;

            const safe_world_x = @min(world_x, self.size.x - 1);
            const safe_world_y = @min(world_y, self.size.y - 1);

            const x_prev = if (safe_world_x > 0) safe_world_x - 1 else safe_world_x;
            const x_next = if (safe_world_x < self.size.x - 1) safe_world_x + 1 else safe_world_x;
            const y_prev = if (safe_world_y > 0) safe_world_y - 1 else safe_world_y;
            const y_next = if (safe_world_y < self.size.y - 1) safe_world_y + 1 else safe_world_y;

            const height_left = self.getHeight(x_prev, safe_world_y);
            const height_right = self.getHeight(x_next, safe_world_y);
            const height_up = self.getHeight(safe_world_x, y_prev);
            const height_down = self.getHeight(safe_world_x, y_next);

            const dx = (height_right - height_left) / 2.0;
            const dy = (height_down - height_up) / 2.0;

            const normal_vec = rl.Vector3.init(-dx, 1.0, -dy).normalize();
            mesh.normals[index * 3 + 0] = normal_vec.x;
            mesh.normals[index * 3 + 1] = normal_vec.y;
            mesh.normals[index * 3 + 2] = normal_vec.z;
        }
    }

    rl.uploadMesh(&mesh, false);
    return mesh;
}

pub fn getHeight(self: *const Self, x: usize, y: usize) f32 {
    if (x >= self.size.x or y >= self.size.y) {
        commons.print("Height query out of bounds: ({}, {}) >= ({}, {})", .{ x, y, self.size.x, self.size.y }, .yellow);
        return 0.0;
    }

    return self.height_map[y * self.size.x + x];
}
