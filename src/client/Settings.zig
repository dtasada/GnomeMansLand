//! Container for game configuration pulled from config.json
const std = @import("std");
const ServerSettings = @import("../server/Settings.zig");

video: struct {
    resolution: [2]i32,
    framerate: i32,
},

multiplayer: struct {
    server_host: []u8,
    server_port: u16,
    polling_rate: u64, // in milliseconds
},

server: ServerSettings,

pub fn print(self: *const @This()) void {
    std.debug.print("video: struct {{\n", .{});
    std.debug.print("    resolution: {d}, {d},\n", .{ self.video.resolution[0], self.video.resolution[1] });
    std.debug.print("    framerate: {d},\n", .{self.video.framerate});
    std.debug.print("}},\n", .{});
    std.debug.print("multiplayer: struct {{\n", .{});
    std.debug.print("    server_host: {s},\n", .{self.multiplayer.server_host});
    std.debug.print("    server_port: {d},\n", .{self.multiplayer.server_port});
    std.debug.print("    server_polling_interval: {d},\n", .{self.multiplayer.polling_rate});
    std.debug.print("}},\n", .{});
    std.debug.print("world_generation: struct {{\n", .{});
    std.debug.print("    resolution: {d}, {d},\n", .{ self.world_generation.resolution[0], self.world_generation.resolution[1] });
    if (self.world_generation.seed) |seed| std.debug.print("    seed: {d},\n", .{seed});
    std.debug.print("    octaves: {d},\n", .{self.world_generation.octaves});
    std.debug.print("    persistence: {d},\n", .{self.world_generation.persistence});
    std.debug.print("    lacunarity: {d},\n", .{self.world_generation.lacunarity});
    std.debug.print("    frequency: {d},\n", .{self.world_generation.frequency});
    std.debug.print("    amplitude: {d},\n", .{self.world_generation.amplitude});
    std.debug.print("}},\n", .{});
    std.debug.print("server: struct {{\n", .{});
    std.debug.print("    port: {d},\n", .{self.server.port});
    std.debug.print("}}\n", .{});
}
