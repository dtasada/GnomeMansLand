//! Wrapper for general game state and loop
const std = @import("std");

const rg = @import("raygui");
const rl = @import("raylib");

const Server = @import("../server/Server.zig");
const Client = @import("Client.zig");
const GameData = @import("GameData.zig");
const Light = @import("Light.zig");
const Settings = @import("Settings.zig");
const states = @import("states/states.zig");

const commons = @import("../commons.zig");
const socket_packet = @import("../socket_packet.zig");
const rcamera = @import("rcamera.zig");
const ui = @import("ui.zig");

const Self = @This();

_gpa: std.heap.GeneralPurposeAllocator(.{}),
_settings_parsed: std.json.Parsed(Settings),
alloc: std.mem.Allocator,
settings: Settings,
camera: ?rl.Camera3D,
camera_mode: enum { first_person, isometric },
light_shader: rl.Shader,
lights: std.ArrayList(Light) = .empty,
mouse_is_enabled: bool,
client: ?*Client,
server: ?*Server,

state: enum { lobby, game, lobby_settings, client_setup, server_setup },
lobby: states.Lobby,
lobby_settings: states.LobbySettings,
client_setup: states.ClientSetup,
server_setup: states.ServerSetup,

// additional camera attributes
pan_sensitivity: f32 = 0.1,

pub fn init(alloc: std.mem.Allocator) !*Self {
    var self: *Self = try alloc.create(Self);
    errdefer alloc.destroy(self);

    self._gpa = .init;
    self.alloc = self._gpa.allocator();

    self._settings_parsed = try parseSettings(self.alloc);
    errdefer self._settings_parsed.deinit();

    self.settings = self._settings_parsed.value;

    self.camera = null;

    self.camera_mode = .isometric;

    try self.setupLights();
    errdefer self.lights.deinit(self.alloc);

    self.mouse_is_enabled = true;
    self.state = .lobby;

    self.client = null;
    self.server = null;

    ui.chalk_font = try rl.loadFontEx("resources/fonts/chalk.ttf", 256, null);
    ui.gwathlyn_font = try rl.loadFontEx("resources/fonts/gwathlyn.ttf", 256, null);

    self.lobby = try states.Lobby.init(self.alloc);
    self.lobby_settings = try states.LobbySettings.init(self.alloc);
    self.server_setup = try states.ServerSetup.init(self.alloc, self);
    self.client_setup = try states.ClientSetup.init(self.alloc, self);

    return self;
}

pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
    ui.chalk_font.unload();
    ui.gwathlyn_font.unload();

    self.client_setup.deinit(self.alloc);
    self.server_setup.deinit(self.alloc);
    self.lobby.deinit(self.alloc);
    self.lobby_settings.deinit(self.alloc);

    if (self.client) |c| c.deinit(self.alloc);
    if (self.server) |s| s.deinit(self.alloc);

    self.lights.deinit(self.alloc);
    self.light_shader.unload();

    defer alloc.destroy(self);
    defer _ = self._gpa.deinit();
    defer self._settings_parsed.deinit();

    const settings_string: []u8 = std.json.Stringify.valueAlloc(self.alloc, self._settings_parsed.value, .{ .whitespace = .indent_4 }) catch |err| {
        commons.print("Couldn't save settings to './settings.json': {}\n", .{err}, .red);
        return;
    };
    defer self.alloc.free(settings_string);

    const settings_file: std.fs.File = std.fs.cwd().createFile("./settings.json", .{}) catch |err| {
        commons.print("Couldn't save settings to './settings.json': {}\n", .{err}, .red);
        return;
    };

    var settings_buf: [1024]u8 = undefined;
    var file_writer = settings_file.writer(&settings_buf);
    const interface = &file_writer.interface;
    interface.writeAll(settings_string) catch |err| {
        commons.print("Couldn't save settings to './settings.json': {}\n", .{err}, .red);
        return;
    };
    interface.flush() catch |err| {
        commons.print("Couldn't save settings to './settings.json': {}\n", .{err}, .red);
        return;
    };
}

/// wraps mouse around screen so the cursor won't leave the window
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

/// toggles is_enabled and enables or disables cursor.
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

/// sets game.light_shader and game.lights
fn setupLights(self: *Self) !void {
    self.light_shader = try rl.loadShader("./resources/shaders/lighting.vert.glsl", "./resources/shaders/lighting.frag.glsl");
    self.light_shader.locs[@intFromEnum(rl.ShaderLocationIndex.vector_view)] = rl.getShaderLocation(self.light_shader, "viewPos");
    const ambient_loc = rl.getShaderLocation(self.light_shader, "ambient");
    const ambient: [4]f32 = .{ 0.1, 0.1, 0.1, 1.0 };
    rl.setShaderValue(self.light_shader, ambient_loc, &ambient, .vec4);

    self.lights = try std.ArrayList(Light).initCapacity(self.alloc, 32);
    try self.lights.append(self.alloc, Light.init(
        .point,
        rl.Vector3.init(200, 200, 0),
        rl.Vector3.zero(),
        .white,
        1,
        self.light_shader,
    ));
}

/// parses settings from "./settings.json"
fn parseSettings(alloc: std.mem.Allocator) !std.json.Parsed(Settings) {
    const file = try std.fs.cwd().readFileAlloc(alloc, "./settings.json", 4096);
    defer alloc.free(file);

    return std.json.parseFromSlice(Settings, alloc, file, .{});
}

/// resets camera back to the middle of the world
fn resetCamera(self: *Self) void {
    if (self.client) |client| {
        if (client.game_data.world_data) |world_data| {
            // Use more reasonable camera positioning to avoid precision issues
            const center_x = @as(f32, @floatFromInt(world_data.size.x)) * 0.5;
            const center_z = @as(f32, @floatFromInt(world_data.size.y)) * 0.5;
            const camera_height = @as(f32, @floatFromInt(@max(world_data.size.x, world_data.size.y))); // Adjust height based on map size

            rcamera.MAX_FOV = camera_height * 2.0;

            self.camera = .{
                .fovy = rcamera.MAX_FOV,
                .position = rl.Vector3.init(center_x, camera_height, center_z + camera_height * 0.5),
                .projection = .orthographic,
                .target = rl.Vector3.init(center_x, 0.0, center_z),
                .up = rl.Vector3.init(0, 1, 0),
            };
        }
    }
}

/// input handling
fn handleKeys(self: *Self) !void {
    // pan the camera with middle mouse
    if (self.camera) |*camera| {
        if (rl.isMouseButtonDown(.middle)) {
            const camDir = camera.target.subtract(camera.position).normalize();
            const worldUp = rcamera.getUp(camera);
            const camRight = camDir.crossProduct(worldUp).normalize();
            const camUp = camRight.crossProduct(camDir);

            const delta = rl.getMouseDelta();
            const move_vector = camRight
                .scale(-delta.x)
                .add(camUp.scale(delta.y))
                .scale(2.0 / 9.0) // magic ratio that works
                .scale(camera.fovy / 200);
            camera.position = camera.position.add(move_vector);
            camera.target = camera.target.add(move_vector);
        }
        //
        // reset camera pan offset
        if (rl.isKeyPressed(.z)) {
            camera.position = .{ .x = 256, .y = 256, .z = 256 };
            camera.target = .{ .x = 0, .y = 0, .z = 0 };
        }

        const m = 5;
        camera.fovy = @max(@min(rcamera.MAX_FOV, camera.fovy + -m * rl.getMouseWheelMove()), rcamera.MIN_FOV);

        // pan the camera
        if (rl.isMouseButtonDown(.right)) {
            centerMouse();
            rcamera.update(camera, .third_person);
        } else if (!self.mouse_is_enabled) toggleMouse(&self.mouse_is_enabled);

        if (rl.isMouseButtonPressed(.left)) {
            if (self.client) |client| {
                if (self.getMouseToWorld()) |pos| {
                    const move_player = socket_packet.MovePlayer.init(.init(pos.x, pos.z));
                    const move_player_string = try std.json.Stringify.valueAlloc(self.alloc, move_player, .{});
                    defer self.alloc.free(move_player_string);

                    try client.send(move_player_string);
                }
            }
        }
    }

    // debug light intensity
    if (rl.isKeyPressed(.minus)) {
        for (self.lights.items) |*l|
            l.intensity -= 0.1;
    }

    if (rl.isKeyPressed(.equal)) {
        for (self.lights.items) |*l|
            l.intensity += 0.1;
    }
}

fn drawUi(self: *Self) void {
    if (self.camera) |camera| {
        rl.drawText(rl.textFormat("Camera x: %.1f, y: %.1f, z: %.1f", .{
            camera.position.x,
            camera.position.y,
            camera.position.z,
        }), 12, 12, 24, .white);
    }

    rl.drawText(rl.textFormat("Mouse 2D x: %d, y: %d", .{
        rl.getMouseX(),
        rl.getMouseY(),
    }), 12, 32, 24, .white);

    rl.drawText(rl.textFormat("FPS: %d", .{rl.getFPS()}), 12, 52, 24, .white);

    // Add world data debugging
    if (self.client) |client| {
        if (client.game_data.world_data) |world_data| {
            rl.drawText(rl.textFormat("World: %dx%d, Complete: %d", .{
                world_data.size.x,
                world_data.size.y,
                @as(i32, if (world_data.isComplete()) 1 else 0),
            }), 12, 72, 24, .white);

            const chunks_total = world_data.models.len;
            var chunks_loaded: u32 = 0;
            for (world_data.models) |model| {
                if (model != null) chunks_loaded += 1;
            }

            rl.drawText(rl.textFormat("Chunks: %d/%d loaded", .{ chunks_loaded, chunks_total }), 12, 112, 24, .white);
        }
    }
}

/// gets equivalent in-world position from 2d cursor position
fn getMouseToWorld(self: *Self) ?rl.Vector3 {
    if (self.camera) |camera| {
        if (self.client) |client| {
            if (client.game_data.world_data) |world_data| {
                for (world_data.models) |model| {
                    if (model) |m| {
                        const mouse_pos_ray = rl.getScreenToWorldRay(rl.getMousePosition(), camera);
                        const mouse_world_collision = rl.getRayCollisionMesh(mouse_pos_ray, m.meshes[0], m.transform);
                        return mouse_world_collision.point;
                    }
                }
            }
        }
    }

    return null;
}

/// main game loop
pub fn loop(self: *Self) !void {
    while (!rl.windowShouldClose()) {
        switch (self.state) {
            .lobby => try self.lobby.update(self),
            .lobby_settings => try self.lobby_settings.update(self),
            .client_setup => try self.client_setup.update(self),
            .server_setup => try self.server_setup.update(self),
            .game => {
                // update step
                try self.handleKeys();

                if (self.camera) |*camera|
                    Light.updateLights(camera, self.light_shader, self.lights);

                // render step
                rl.beginDrawing();
                rl.clearBackground(.sky_blue);

                if (self.camera) |c| c.begin();

                // draw lights and models
                self.light_shader.activate();

                for (self.lights.items) |l| rl.drawSphere(l.position, 10, l.color);

                rl.gl.rlDisableBackfaceCulling();

                if (self.client) |client| {
                    if (client.game_data.world_data) |*world_data| {
                        if (self.camera == null)
                            self.resetCamera();

                        // Draw players
                        for (client.game_data.players.items) |player| {
                            if (player.position) |pos| {
                                rl.drawCube(rl.Vector3.init(
                                    pos.x,
                                    world_data.getHeight(@intFromFloat(pos.x), @intFromFloat(pos.y)),
                                    pos.y,
                                ), 8, 50, 8, .red);
                            }
                        }

                        // Enhanced model rendering with debugging
                        for (world_data.models, 0..) |model, i| {
                            if (model) |m| {
                                rl.drawModel(m, .zero(), 1.0, .white);
                            } else if (world_data.isComplete())
                                world_data.genModel(self.settings, self.light_shader) catch |err| {
                                    commons.print("Failed to generate model {}: {}", .{ i, err }, .red);
                                };
                        }
                    }
                }

                rl.gl.rlEnableBackfaceCulling();

                self.light_shader.deactivate();

                if (self.camera) |c| c.end();

                self.drawUi();

                rl.endDrawing();
            },
        }
    }
}
