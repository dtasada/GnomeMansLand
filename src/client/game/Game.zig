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
pub const input = @import("input.zig");

const Self = @This();

gpa: std.heap.DebugAllocator(.{}),
alloc: std.mem.Allocator,

client: ?*Client = null,
server: ?*Server = null,

_settings_parsed: std.json.Parsed(Settings),
settings: Settings,

state: State,

pub fn init(alloc: std.mem.Allocator) !*Self {
    var self: *Self = try alloc.create(Self);
    errdefer alloc.destroy(self);

    self.gpa = .init;
    const inner_alloc = self.gpa.allocator();
    const settings_parsed = try parseSettings(inner_alloc);
    errdefer settings_parsed.deinit();
    const settings = settings_parsed.value;

    setupRaylib(settings);

    ui.chalk_font = try rl.loadFontEx("resources/fonts/chalk.ttf", 128, null);
    ui.gwathlyn_font = try rl.loadFontEx("resources/fonts/gwathlyn.ttf", 128, null);

    self.* = .{
        .gpa = self.gpa,
        ._settings_parsed = settings_parsed,
        .alloc = inner_alloc,
        .settings = settings,
        .state = try .init(inner_alloc, settings),
    };

    return self;
}

pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
    self.state.deinit();

    ui.chalk_font.unload();
    ui.gwathlyn_font.unload();

    if (self.client) |c| c.deinit(self.alloc);
    if (self.server) |s| s.deinit(self.alloc);

    defer rl.closeWindow();

    defer alloc.destroy(self);
    defer _ = self.gpa.deinit();
    defer self._settings_parsed.deinit();

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
        return;
    };
    defer self.alloc.free(settings_string);

    const settings_file = std.fs.cwd().createFile("./settings.json", .{}) catch |err| {
        commons.print(
            "Couldn't create settings file './settings.json': {}\n",
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
            "Couldn't write to settings file './settings.json': {}\n",
            .{err},
            .red,
        );
        return;
    };

    interface.flush() catch |err| {
        commons.print(
            "Couldn't flush settings file './settings.json': {}\n",
            .{err},
            .red,
        );
        return;
    };
}

/// Set up Raylib window and corresponding settings
fn setupRaylib(settings: Settings) void {
    rl.setConfigFlags(.{
        .vsync_hint = true,
        .window_resizable = true,
        .msaa_4x_hint = true,
        .window_topmost = true,
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

/// parses settings from "./settings.json"
fn parseSettings(alloc: std.mem.Allocator) !std.json.Parsed(Settings) {
    const file = try std.fs.cwd().readFileAlloc(alloc, "./settings.json", 4096);
    defer alloc.free(file);

    return std.json.parseFromSlice(Settings, alloc, file, .{});
}

pub const Context = struct {
    alloc: std.mem.Allocator,
    settings: *Settings,
    client: *?*Client,
    server: *?*Server,
    state: *State,
};

/// main game loop
pub fn loop(self: *Self) !void {
    while (!rl.windowShouldClose())
        try self.state.update(self);
}

pub fn reinitServer(self: *Self) !void {
    if (self.server) |s| s.deinit(self.alloc);
    self.server = try Server.init(self.alloc, self.settings.server);
}

pub fn reinitClient(self: *Self, nickname: []const u8) !void {
    if (self.client) |client| client.deinit(self.alloc);

    const client_connect = socket_packet.ClientConnect.init(nickname);
    self.client = try Client.init(self.alloc, self.settings, client_connect);
}
