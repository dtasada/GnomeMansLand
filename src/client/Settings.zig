//! Container for game configuration pulled from config.json
const std = @import("std");

const commons = @import("commons");

video: struct {
    resolution: [2]i32,
    framerate: i32,
},

multiplayer: struct {
    server_host: []u8,
    server_port: u16,
    polling_rate: u64, // in milliseconds
},

server: commons.ServerSettings,
