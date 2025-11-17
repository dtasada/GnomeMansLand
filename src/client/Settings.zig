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

pub fn print(self: *const @This()) void {
    commons.print("video: struct {{\n", .{}, .white);
    commons.print("    resolution: {d}, {d},\n", .{ self.video.resolution[0], self.video.resolution[1] }, .white);
    commons.print("    framerate: {d},\n", .{self.video.framerate}, .white);
    commons.print("}},\n", .{}, .white);
    commons.print("multiplayer: struct {{\n", .{}, .white);
    commons.print("    server_host: {s},\n", .{self.multiplayer.server_host}, .white);
    commons.print("    server_port: {d},\n", .{self.multiplayer.server_port}, .white);
    commons.print("    server_polling_interval: {d},\n", .{self.multiplayer.polling_rate}, .white);
    commons.print("}},\n", .{}, .white);
    commons.print("world_generation: struct {{\n", .{}, .white);
    commons.print("    resolution: {d}, {d},\n", .{ self.world_generation.resolution[0], self.world_generation.resolution[1] }, .white);
    if (self.world_generation.seed) |seed| commons.print("    seed: {d},\n", .{seed}, .white);
    commons.print("    octaves: {d},\n", .{self.world_generation.octaves}, .white);
    commons.print("    persistence: {d},\n", .{self.world_generation.persistence}, .white);
    commons.print("    lacunarity: {d},\n", .{self.world_generation.lacunarity}, .white);
    commons.print("    frequency: {d},\n", .{self.world_generation.frequency}, .white);
    commons.print("    amplitude: {d},\n", .{self.world_generation.amplitude}, .white);
    commons.print("}},\n", .{}, .white);
    commons.print("server: struct {{\n", .{}, .white);
    commons.print("    port: {d},\n", .{self.server.port}, .white);
    commons.print("}}\n", .{}, .white);
}
