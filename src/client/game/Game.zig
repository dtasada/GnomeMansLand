//! Wrapper for general game state and loop
const std = @import("std");

const rg = @import("raygui");
const rl = @import("raylib");

const State = @import("state");
const commons = @import("commons");
const socket_packet = @import("socket_packet");
const ui = State.ui;

const Server = @import("server");
const Client = @import("client");

pub const Settings = Client.Settings;
pub const GameData = @import("GameData.zig");
pub const Light = @import("Light.zig");
pub const rcamera = @import("rcamera.zig");

const Self = @This();

_gpa: std.heap.GeneralPurposeAllocator(.{}),
lights: std.ArrayList(Light) = .{},
client: ?*Client = null,
server: ?*Server = null,

_settings_parsed: std.json.Parsed(Settings),
alloc: std.mem.Allocator,
settings: Settings,
light_shader: rl.Shader,

state: State,

pub fn init(alloc: std.mem.Allocator) !*Self {
    var self: *Self = try alloc.create(Self);
    errdefer alloc.destroy(self);

    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    const inner_alloc = gpa.allocator();
    const settings_parsed = try parseSettings(inner_alloc);
    errdefer settings_parsed.deinit();
    const settings = settings_parsed.value;

    setupRaylib(settings);

    ui.chalk_font = try rl.loadFontEx("resources/fonts/chalk.ttf", 128, null);
    ui.gwathlyn_font = try rl.loadFontEx("resources/fonts/gwathlyn.ttf", 128, null);

    self.* = .{
        ._gpa = gpa,
        ._settings_parsed = settings_parsed,
        .alloc = inner_alloc,
        .settings = settings,
        .light_shader = try getLightShader(),
        .state = try .init(inner_alloc, settings),
    };

    errdefer self.lights.deinit(self.alloc);
    try self.lights.append(self.alloc, Light.init(
        .point,
        .init(200, 200, 0),
        .zero(),
        .white,
        1,
        self.light_shader,
    ));

    return self;
}

pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
    // Defer closing the window to the very end of the application's lifecycle.
    defer rl.closeWindow();

    // Defer the final memory cleanup in LIFO order. This will be the last block to execute.
    // 3. Destroy the Game object itself using the original allocator.
    defer alloc.destroy(self);
    // 2. Deinitialize the GeneralPurposeAllocator, which frees self.alloc.
    defer _ = self._gpa.deinit();
    // 1. Deinitialize the parsed settings structure.
    defer self._settings_parsed.deinit();

    // 1. Deinitialize all game states and their UI components.
    self.state.deinit(self.alloc);

    // 2. Unload fonts now that no UI components are using them.
    ui.chalk_font.unload();
    ui.gwathlyn_font.unload();

    // 3. Deinitialize client and server if they exist.
    if (self.client) |c| c.deinit(self.alloc);
    if (self.server) |s| s.deinit(self.alloc);

    // 4. Deinitialize other game resources.
    self.lights.deinit(self.alloc);
    self.light_shader.unload();

    // 5. Try to save settings to file. This uses self.alloc, which is still valid.
    const settings_string: []u8 = std.json.Stringify.valueAlloc(
        self.alloc,
        self.settings,
        .{ .whitespace = .indent_4 },
    ) catch |err| {
        commons.print(
            "Couldn't stringify settings for saving: {}\n",
            .{err},
            .red,
        );
        return; // The deferred memory cleanup will still execute.
    };
    // Defer freeing the settings string immediately after it's used.
    defer self.alloc.free(settings_string);

    const settings_file = std.fs.cwd().createFile("./settings.json", .{}) catch |err| {
        commons.print(
            "Couldn't create settings file './settings.json': {}\n",
            .{err},
            .red,
        );
        return; // The deferred memory cleanup will still execute.
    };

    var settings_buf: [1024]u8 = undefined;
    var file_writer = settings_file.writer(&settings_buf);
    const interface = &file_writer.interface;
    interface.writeAll(settings_string) catch |err| {
        commons.print(
            "Couldn't write to settings file './settings.json': {}\n",
            .{err},
            .red,
        );
        return; // The deferred memory cleanup will still execute.
    };

    interface.flush() catch |err| {
        commons.print(
            "Couldn't flush settings file './settings.json': {}\n",
            .{err},
            .red,
        );
        return; // The deferred memory cleanup will still execute.
    };
}

/// Set up Raylib window and corresponding settings
fn setupRaylib(settings: Settings) void {
    rl.setConfigFlags(.{
        .vsync_hint = true,
        .window_resizable = true,
        .msaa_4x_hint = true,
    });

    rl.setTraceLogLevel(.warning);
    rl.initWindow(
        settings.video.resolution[0],
        settings.video.resolution[1],
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
fn getLightShader() !rl.Shader {
    const light_shader = try rl.loadShader("./resources/shaders/lighting.vert.glsl", "./resources/shaders/lighting.frag.glsl");
    light_shader.locs[@intFromEnum(rl.ShaderLocationIndex.vector_view)] = rl.getShaderLocation(light_shader, "viewPos");
    const ambient_loc = rl.getShaderLocation(light_shader, "ambient");
    const ambient: [4]f32 = .{ 0.1, 0.1, 0.1, 1.0 };
    rl.setShaderValue(light_shader, ambient_loc, &ambient, .vec4);

    return light_shader;
}

/// parses settings from "./settings.json"
fn parseSettings(alloc: std.mem.Allocator) !std.json.Parsed(Settings) {
    const file = try std.fs.cwd().readFileAlloc(alloc, "./settings.json", 4096);
    defer alloc.free(file);

    return std.json.parseFromSlice(Settings, alloc, file, .{});
}

/// main game loop
pub fn loop(self: *Self) !void {
    while (!rl.windowShouldClose())
        try self.state.update(self);
}
