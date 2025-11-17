//! Wrapper for general game state and loop
const std = @import("std");

const rg = @import("raygui");
const rl = @import("raylib");

const states = @import("states/states.zig");
const commons = @import("../commons.zig");
const socket_packet = @import("../socket_packet.zig");
const rcamera = @import("rcamera.zig");
const ui = @import("ui.zig");

const Server = @import("../server/Server.zig");
const Client = @import("Client.zig");
const GameData = @import("GameData.zig");
const Light = @import("Light.zig");
const Settings = @import("Settings.zig");

const Self = @This();

_gpa: std.heap.GeneralPurposeAllocator(.{}) = .init,
camera: ?rl.Camera3D = null,
camera_mode: enum { first_person, isometric } = .isometric,
camera_sens: f32 = 0.1,
lights: std.ArrayList(Light) = .empty,
mouse_is_enabled: bool = true,
client: ?*Client = null,
server: ?*Server = null,
state: enum {
    lobby,
    game,
    lobby_settings,
    client_setup,
    server_setup,
} = .lobby,

_settings_parsed: std.json.Parsed(Settings),
alloc: std.mem.Allocator,
settings: Settings,
light_shader: rl.Shader,

lobby: states.Lobby,
lobby_settings: states.LobbySettings,
client_setup: states.ClientSetup,
server_setup: states.ServerSetup,

pub fn init(alloc: std.mem.Allocator) !*Self {
    var self: *Self = try alloc.create(Self);
    errdefer alloc.destroy(self);

    self.* = .{
        ._settings_parsed = undefined,
        .alloc = undefined,
        .settings = undefined,
        .light_shader = undefined,

        .lobby = undefined,
        .lobby_settings = undefined,
        .client_setup = undefined,
        .server_setup = undefined,
    };

    self.alloc = self._gpa.allocator();

    self._settings_parsed = try parseSettings(self.alloc);
    errdefer self._settings_parsed.deinit();
    self.settings = self._settings_parsed.value;

    self.setupRaylib();

    try self.setupLights();
    errdefer self.lights.deinit(self.alloc);

    ui.chalk_font = try rl.loadFontEx("resources/fonts/chalk.ttf", 128, null);
    ui.gwathlyn_font = try rl.loadFontEx("resources/fonts/gwathlyn.ttf", 128, null);

    self.lobby = try states.Lobby.init(self.alloc);
    self.lobby_settings = try states.LobbySettings.init(self.alloc);
    self.server_setup = try states.ServerSetup.init(self.alloc, self);
    self.client_setup = try states.ClientSetup.init(self.alloc, self);

    return self;
}

pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
    defer rl.closeWindow();
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

    const settings_string: []u8 = std.json.Stringify.valueAlloc(
        self.alloc,
        self._settings_parsed.value,
        .{ .whitespace = .indent_4 },
    ) catch |err| {
        commons.print(
            "Couldn't save settings to './settings.json': {}\n",
            .{err},
            .red,
        );
        return;
    };

    defer self.alloc.free(settings_string);

    const settings_file = std.fs.cwd().createFile("./settings.json", .{}) catch |err| {
        commons.print(
            "Couldn't save settings to './settings.json': {}\n",
            .{err},
            .red,
        );
        return;
    };

    var settings_buf: [1024]u8 = undefined;
    var file_writer = settings_file.writer(&settings_buf);
    const interface = &file_writer.interface;
    interface.writeAll(settings_string) catch |err| {
        commons.print(
            "Couldn't save settings to './settings.json': {}\n",
            .{err},
            .red,
        );
        return;
    };

    interface.flush() catch |err| {
        commons.print(
            "Couldn't save settings to './settings.json': {}\n",
            .{err},
            .red,
        );
        return;
    };
}

/// Set up Raylib window and corresponding settings
fn setupRaylib(self: *const Self) void {
    rl.setConfigFlags(.{
        .vsync_hint = true,
        .window_resizable = true,
        .msaa_4x_hint = true,
    });

    rl.setTraceLogLevel(.warning);
    rl.initWindow(
        self.settings.video.resolution[0],
        self.settings.video.resolution[1],
        "Gnome Man's Land",
    );

    rl.setExitKey(.null);
    rl.setTargetFPS(60);

    // Draw a blank frame and then resize to trigger UI layout fix.
    // This ensures the window is fully processed by the OS before we send a resize event.
    rl.beginDrawing();
    rl.clearBackground(.black);
    rl.endDrawing();
    const width = rl.getScreenWidth();
    const height = rl.getScreenHeight();
    rl.setWindowSize(width, height + 1);
    rl.setWindowSize(width, height);
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

/// main game loop
pub fn loop(self: *Self) !void {
    while (!rl.windowShouldClose()) {
        switch (self.state) {
            .lobby => try self.lobby.update(self),
            .lobby_settings => try self.lobby_settings.update(self),
            .client_setup => try self.client_setup.update(self),
            .server_setup => try self.server_setup.update(self),
            .game => try states.InGame.update(self),
        }
    }
}
