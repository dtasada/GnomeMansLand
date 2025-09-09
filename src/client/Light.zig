//! Basic lighting implementation
const rl = @import("raylib");
const std = @import("std");
const Self = @This();

const LightType = enum(i32) { directional = 0, point = 1 };

var lightsCount: i32 = 0;

type: LightType,
enabled: bool,
position: rl.Vector3,
target: rl.Vector3,
color: rl.Color,
intensity: f32,

enabledLoc: i32,
typeLoc: i32,
positionLoc: i32,
targetLoc: i32,
colorLoc: i32,

pub fn init(type_: LightType, position: rl.Vector3, target: rl.Vector3, color: rl.Color, intensity: f32, shader: rl.Shader) Self {
    var light = Self{
        .enabled = true,
        .type = type_,
        .position = position,
        .target = target,
        .color = color,
        .intensity = intensity,

        .enabledLoc = rl.getShaderLocation(shader, rl.textFormat("lights[%i].enabled", .{lightsCount})),
        .typeLoc = rl.getShaderLocation(shader, rl.textFormat("lights[%i].type", .{lightsCount})),
        .positionLoc = rl.getShaderLocation(shader, rl.textFormat("lights[%i].position", .{lightsCount})),
        .targetLoc = rl.getShaderLocation(shader, rl.textFormat("lights[%i].target", .{lightsCount})),
        .colorLoc = rl.getShaderLocation(shader, rl.textFormat("lights[%i].color", .{lightsCount})),
    };

    light.update(shader);
    lightsCount += 1;

    return light;
}

fn update(self: *const Self, shader: rl.Shader) void {
    const enabled: i32 = @intFromBool(self.enabled);
    rl.setShaderValue(shader, self.enabledLoc, &enabled, .int);

    // const type_: i32 = @intFromEnum(self.type);
    // rl.setShaderValue(shader, self.typeLoc, &type_, .int);
    rl.setShaderValue(shader, self.typeLoc, &self.type, .int);

    const position: [3]f32 = .{ self.position.x, self.position.y, self.position.z };
    rl.setShaderValue(shader, self.positionLoc, &position, .vec3);

    const target: [3]f32 = .{ self.target.x, self.target.y, self.target.z };
    rl.setShaderValue(shader, self.targetLoc, &target, .vec3);

    const color: [4]f32 = .{
        @as(f32, @floatFromInt(self.color.r)) * self.intensity / 255,
        @as(f32, @floatFromInt(self.color.g)) * self.intensity / 255,
        @as(f32, @floatFromInt(self.color.b)) * self.intensity / 255,
        @as(f32, @floatFromInt(self.color.a)) * self.intensity / 255,
    };
    rl.setShaderValue(shader, self.colorLoc, &color, .vec4);
}

pub fn updateLights(camera: *rl.Camera, light_shader: rl.Shader, lights: std.ArrayList(Self)) void {
    const cameraPos: [3]f32 = .{ camera.position.x, camera.position.y, camera.position.z };
    rl.setShaderValue(light_shader, light_shader.locs[@intFromEnum(rl.ShaderLocationIndex.vector_view)], &cameraPos, .vec3);
    for (lights.items) |l| l.update(light_shader);
}
