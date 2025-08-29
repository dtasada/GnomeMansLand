video: struct {
    resolution: [2]i32,
    framerate: i32,
},
multiplayer: struct {
    server_host: []const u8,
    server_port: u16,
    server_polling_interval: i32,
},
world_generation: struct {
    resolution: [2]u32,
    seed: ?u32 = null,
    octaves: i32,
    persistence: f32,
    lacunarity: f32,
    frequency: f32,
    amplitude: f32,
},
server: struct {
    port: u16,
},
