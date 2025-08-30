const rl = @import("raylib");
const std = @import("std");
const rg = @import("raygui");
const Camera = @import("rcamera.zig");
const Light = @import("light.zig");
const Settings = @import("settings.zig");
const WorldGen = @import("worldgen.zig");
const Server = @import("server.zig");
const Client = @import("client.zig");

const Self = @This();

_gpa: std.heap.GeneralPurposeAllocator(.{}),
_settings_parsed: std.json.Parsed(Settings),
alloc: std.mem.Allocator,
settings: *Settings,
world_gen: WorldGen,
camera_fp: rl.Camera3D,
camera_tp: rl.Camera3D,
camera_mode: enum { first_person, isometric },
light_shader: rl.Shader,
lights: std.ArrayList(Light) = .empty,
mouse_is_enabled: bool,
state: enum { lobby, game },
client: ?*Client,
server: ?*Server,

fn centerMouse() void {
    const margin = 24;
    const x = rl.getMouseX();
    const y = rl.getMouseY();
    const center_x = @divFloor(rl.getScreenWidth(), 2);
    const center_y = @divFloor(rl.getScreenHeight(), 2);

    if (x >= rl.getScreenWidth() - margin or x <= margin)
        rl.setMousePosition(center_x, y);
    if (y >= rl.getScreenHeight() - margin or y <= margin)
        rl.setMousePosition(x, center_y);
}

fn toggleMouse(is_enabled: *bool) void {
    is_enabled.* = !is_enabled.*;

    if (is_enabled.*) {
        rl.enableCursor();
        rl.showCursor();
    } else {
        rl.disableCursor();
        rl.hideCursor();
    }
}

fn setupLights(self: *Self) !void {
    self.light_shader = try rl.loadShader("./resources/shaders/lighting.vert.glsl", "./resources/shaders/lighting.frag.glsl");
    self.light_shader.locs[@intFromEnum(rl.ShaderLocationIndex.vector_view)] = rl.getShaderLocation(self.light_shader, "viewPos");
    const ambient_loc = rl.getShaderLocation(self.light_shader, "ambient");
    const ambient: [4]f32 = .{ 0.1, 0.1, 0.1, 1.0 };
    rl.setShaderValue(self.light_shader, ambient_loc, &ambient, .vec4);

    self.lights = try std.ArrayList(Light).initCapacity(self.alloc, 32);
    try self.lights.append(self.alloc, Light.init(.point, rl.Vector3.init(200, 200, 200), rl.Vector3.zero(), .white, 1, self.light_shader));
    // try lights.append(alloc, Light.init(.point, rl.Vector3.init(-2, 20, -2), rl.Vector3.zero(), .yellow, 0.5, light_shader));
    // try lights.append(alloc, Light.init(.point, rl.Vector3.init(2, 20, 2), rl.Vector3.zero(), .red, 0.5, light_shader));
    // try lights.append(alloc, Light.init(.point, rl.Vector3.init(-2, 20, 2), rl.Vector3.zero(), .green, 0.5, light_shader));
    // try lights.append(alloc, Light.init(.point, rl.Vector3.init(2, 20, -2), rl.Vector3.zero(), .blue, 0.5, light_shader));
}

fn parseConfig(alloc: std.mem.Allocator) !std.json.Parsed(Settings) {
    const file = try std.fs.cwd().readFileAlloc(alloc, "./config.json", 4096);
    defer alloc.free(file);

    return try std.json.parseFromSlice(Settings, alloc, file, .{});
}

pub fn init(alloc: std.mem.Allocator) !*Self {
    var self: *Self = try alloc.create(Self);

    self._gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    self.alloc = self._gpa.allocator();

    self._settings_parsed = try parseConfig(self.alloc);
    self.settings = &self._settings_parsed.value;

    self.world_gen = try WorldGen.init(self.alloc, self.settings);

    self.camera_tp = .{
        .fovy = 100,
        .position = rl.Vector3.one().scale(@floatFromInt(self.world_gen.size.x)),
        .projection = .orthographic,
        .target = rl.Vector3.zero(),
        .up = rl.Vector3.init(0, 1, 0),
    };

    self.camera_fp = .{
        .fovy = 90,
        .position = rl.Vector3.zero(),
        .projection = .perspective,
        .target = rl.Vector3.init(1, 0, 0),
        .up = rl.Vector3.init(0, 1, 0),
    };

    self.camera_mode = .isometric;

    try self.setupLights();
    self.world_gen.model.materials[0].shader = self.light_shader;

    self.mouse_is_enabled = false;
    self.state = .lobby;

    self.client = null;
    self.server = null;

    return self;
}

pub fn deinit(self: *Self) void {
    if (self.client) |c| {
        c.deinit();
        self.alloc.destroy(c);
    }

    if (self.server) |s| {
        s.deinit();
        self.alloc.destroy(s);
    }

    self.lights.deinit(self.alloc);
    self.light_shader.unload();
    self.world_gen.deinit(self.alloc);
    self._settings_parsed.deinit();
    _ = self._gpa.deinit();
}

pub fn loop(self: *Self) !void {
    while (!rl.windowShouldClose()) {
        switch (self.state) {
            .lobby => {
                if (!self.mouse_is_enabled) toggleMouse(&self.mouse_is_enabled);
                rl.beginDrawing();
                rl.clearBackground(.black);

                if (rg.button(.init(12, 92, 256, 72), "Host server")) {
                    if (self.server == null) self.server = try Server.init(self.alloc, self.settings);
                }

                if (rg.button(.init(12, 192, 256, 72), "Connect to server")) {
                    if (self.client == null) self.client = try Client.init(self.alloc, self.settings);
                    self.state = .game;
                }

                rl.endDrawing();
                continue;
            },
            else => {
                // update step
                if (rl.isMouseButtonDown(.right)) {
                    if (self.mouse_is_enabled) toggleMouse(&self.mouse_is_enabled);

                    centerMouse();
                    switch (self.camera_mode) {
                        .first_person => Camera.update(&self.camera_fp, .first_person),
                        .isometric => Camera.update(&self.camera_tp, .third_person),
                    }
                } else if (!self.mouse_is_enabled) toggleMouse(&self.mouse_is_enabled);

                if (rl.isKeyPressed(.minus)) {
                    for (self.lights.items) |*l|
                        l.intensity -= 0.1;
                }

                if (rl.isKeyPressed(.equal)) {
                    for (self.lights.items) |*l|
                        l.intensity += 0.1;
                }

                if (rl.isKeyPressed(.k))
                    switch (self.camera_mode) {
                        .first_person => self.camera_mode = .isometric,
                        .isometric => self.camera_mode = .first_person,
                    };

                if (rl.isKeyPressed(.space))
                    try self.client.?.sendMessage("ping!");

                Light.updateLights(&switch (self.camera_mode) {
                    .first_person => self.camera_fp,
                    .isometric => self.camera_tp,
                }, self.light_shader, self.lights);

                // render step
                rl.beginDrawing();
                rl.clearBackground(.black);

                rl.beginMode3D(switch (self.camera_mode) {
                    .first_person => self.camera_fp,
                    .isometric => self.camera_tp,
                });
                self.light_shader.activate();

                for (self.lights.items) |l| rl.drawSphere(l.position, 10, l.color);

                rl.gl.rlDisableBackfaceCulling();
                rl.drawModel(self.world_gen.model, rl.Vector3.zero(), 1.0, .white);
                rl.gl.rlEnableBackfaceCulling();

                self.light_shader.deactivate();

                rl.endMode3D();

                rl.drawText(rl.textFormat("Camera x: %.1f, y: %.1f, z: %.1f", .{
                    self.camera_tp.position.x,
                    self.camera_tp.position.y,
                    self.camera_tp.position.z,
                }), 12, 12, 24, .white);

                rl.drawText(rl.textFormat("Mouse x: %d, y: %d", .{
                    rl.getMouseX(),
                    rl.getMouseY(),
                }), 12, 32, 24, .white);

                rl.drawText(rl.textFormat("FPS: %d", .{rl.getFPS()}), 12, 52, 24, .white);

                rl.endDrawing();
            },
        }
    }
}
