//! Sub-container for server-specific configuration
max_players: u32,
port: u16,
polling_rate: u64,

world_generation: struct {
    resolution: [2]u32,
    seed: ?u32 = null,
    octaves: i32,
    persistence: f32,
    lacunarity: f32,
    frequency: f32,
    amplitude: f32,
},
