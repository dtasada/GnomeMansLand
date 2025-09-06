//! Wrapper for general game state and loop
const std = @import("std");

const rg = @import("raygui");
const rl = @import("raylib");

const Camera = @import("rcamera.zig");
const Client = @import("Client.zig");
const ClientGameData = @import("ClientGameData.zig");
const commons = @import("commons.zig");
const Light = @import("Light.zig");
const Server = @import("Server.zig");
const Settings = @import("Settings.zig");
const SocketPacket = @import("SocketPacket.zig");

const Self = @This();

_gpa: std.heap.GeneralPurposeAllocator(.{}),
_settings_parsed: std.json.Parsed(Settings),
alloc: std.mem.Allocator,
settings: *const Settings,
camera: rl.Camera3D,
camera_mode: enum { first_person, isometric },
light_shader: rl.Shader,
lights: std.ArrayList(Light) = .empty,
mouse_is_enabled: bool,
state: enum { lobby, game },
client: ?*Client,
server: ?*Server,

// additional camera attributes
pan_sensitivity: f32 = 0.1,

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
    try self.lights.append(self.alloc, Light.init(
        .point,
        rl.Vector3.init(200, 200, 200),
        rl.Vector3.zero(),
        .white,
        1,
        self.light_shader,
    ));
}

fn parseConfig(alloc: std.mem.Allocator) !std.json.Parsed(Settings) {
    const file = try std.fs.cwd().readFileAlloc(alloc, "./config.json", 4096);
    defer alloc.free(file);

    return try std.json.parseFromSlice(Settings, alloc, file, .{});
}

pub fn init(alloc: std.mem.Allocator) !*Self {
    var self: *Self = try alloc.create(Self);

    self._gpa = .init;
    self.alloc = self._gpa.allocator();

    self._settings_parsed = try parseConfig(self.alloc);
    self.settings = &self._settings_parsed.value;

    self.camera = .{
        .fovy = 100,
        .position = rl.Vector3.one().scale(@floatFromInt(self.settings.world_generation.resolution[0])),
        .projection = .orthographic,
        .target = rl.Vector3.zero(),
        .up = rl.Vector3.init(0, 1, 0),
    };

    self.camera_mode = .isometric;

    try self.setupLights();

    self.mouse_is_enabled = true;
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
    self._settings_parsed.deinit();
    _ = self._gpa.deinit();
}

fn handleKeys(self: *Self) !void {
    // pan the camera with middle mouse
    if (rl.isMouseButtonDown(.middle)) {
        const camDir = self.camera.target.subtract(self.camera.position).normalize();
        const worldUp = Camera.getUp(&self.camera);
        const camRight = camDir.crossProduct(worldUp).normalize();
        const camUp = camRight.crossProduct(camDir);

        const delta = rl.getMouseDelta();
        const move_vector = camRight
            .scale(-delta.x).add(camUp
                .scale(delta.y))
            .scale(2.0 / 9.0) // magic ratio that works
            .scale(self.camera.fovy / 200);
        self.camera.position = self.camera.position.add(move_vector);
        self.camera.target = self.camera.target.add(move_vector);
    }

    // reset camera pan offset
    if (rl.isKeyPressed(.z)) {
        std.debug.print("asd\n", .{});
        self.camera.position = rl.Vector3{ .x = 256, .y = 256, .z = 256 };
        self.camera.target = rl.Vector3{ .x = 0, .y = 0, .z = 0 };
    }

    const m = 5;
    self.camera.fovy = @max(@min(Camera.MAX_FOV, self.camera.fovy + -m * rl.getMouseWheelMove()), Camera.MIN_FOV);

    // pan the camera
    if (rl.isMouseButtonDown(.right)) {
        // if (self.mouse_is_enabled) toggleMouse(&self.mouse_is_enabled);

        centerMouse();
        Camera.update(&self.camera, .third_person);
    } else if (!self.mouse_is_enabled) toggleMouse(&self.mouse_is_enabled);

    // debug light intensity
    if (rl.isKeyPressed(.minus)) {
        for (self.lights.items) |*l|
            l.intensity -= 0.1;
    }

    if (rl.isKeyPressed(.equal)) {
        for (self.lights.items) |*l|
            l.intensity += 0.1;
    }

    // client-server ping
    if (rl.isKeyPressed(.space))
        try self.client.?.sendMessage("ping!");
}

fn drawUi(self: *Self) void {
    rl.drawText(rl.textFormat("Camera x: %.1f, y: %.1f, z: %.1f", .{
        self.camera.position.x,
        self.camera.position.y,
        self.camera.position.z,
    }), 12, 12, 24, .white);

    rl.drawText(rl.textFormat("Mouse x: %d, y: %d", .{
        rl.getMouseX(),
        rl.getMouseY(),
    }), 12, 32, 24, .white);

    rl.drawText(rl.textFormat("FPS: %d", .{rl.getFPS()}), 12, 52, 24, .white);

    // const layers = [_][:0]const u8{
    //     "water",
    //     "sand",
    //     "grass",
    //     "mountain",
    //     "snow",
    // };
    // rg.setStyle(.default, .{ .default = .text_size }, 24);
    // inline for (0..5) |i| {
    //     const rect = rl.Rectangle.init(140, 100 + @as(f32, @floatFromInt(i)) * 30, 200, 20);
    //     // const up = commons.upper(self.alloc, layers[i]) catch "";
    //     // defer self.alloc.free(up);
    //     const up = layers[i];
    //     _ = rg.slider(rect, up, "asd", &@field(WorldGen.TileData, layers[i]), 0, 1);
    // }
    // _ = rg.slider({.x_f})
}

var nickname_storage: [32]u8 = .{0} ** 32; // zero-initialized
const nickname: [:0]u8 = nickname_storage[0..31 :0]; // length 31, sentinel at index 31

fn drawLobby(self: *Self) !void {
    rl.beginDrawing();
    rl.clearBackground(.black);

    const button_width = 256.0;
    const button_height = 72.0;
    const button_padding = 16.0;
    const center_x = @as(f32, @floatFromInt(rl.getScreenWidth())) / 2.0;
    const center_y = @as(f32, @floatFromInt(rl.getScreenHeight())) / 2.0;
    const server_button_rect = rl.Rectangle.init(
        center_x - button_width / 2.0,
        center_y - button_height - button_padding,
        button_width,
        button_height,
    );

    rg.setStyle(.default, .{ .default = .text_size }, 24);
    if (rg.button(server_button_rect, "Host server")) {
        if (self.server == null) self.server = try Server.init(self.alloc, self.settings);
    }

    const client_button_rect = rl.Rectangle.init(
        center_x - button_width / 2.0,
        center_y,
        button_width,
        button_height,
    );
    if (rg.button(client_button_rect, "Connect to server") and nickname[0] != 0) { // only if nickname isn't empty
        var nickname_trimmed = std.mem.splitAny(u8, nickname, "\x00");
        if (self.client == null) self.client = try Client.init(
            self.alloc,
            self.settings,
            SocketPacket.ClientConnect.init(nickname_trimmed.first()),
        );
        self.state = .game;
    }

    rg.setStyle(.default, .{ .default = .text_size }, 10);

    rl.drawText(
        "Gnome Man's Land",
        @as(i32, @intFromFloat(center_x)) - 220,
        @as(i32, @intFromFloat(server_button_rect.y)) - 128,
        48,
        .white,
    );

    const name_box_width = 192.0;
    const name_box_height = 48.0;
    const name_box_rect = rl.Rectangle.init(
        center_x - name_box_width / 2.0,
        client_button_rect.y + client_button_rect.height + 24,
        name_box_width,
        name_box_height,
    );

    _ = rg.textBox(name_box_rect, nickname, nickname_storage.len, true);

    rl.endDrawing();
}

pub fn loop(self: *Self) !void {
    while (!rl.windowShouldClose()) {
        switch (self.state) {
            .lobby => try self.drawLobby(),
            .game => {
                // update step
                try self.handleKeys();

                Light.updateLights(&self.camera, self.light_shader, self.lights);

                // render step
                rl.beginDrawing();
                rl.clearBackground(.black);

                self.camera.begin();

                // draw lights and models
                self.light_shader.activate();

                for (self.lights.items) |l| rl.drawSphere(l.position, 10, l.color);

                rl.gl.rlDisableBackfaceCulling();
                if (self.client.?.game_data.world_data) |*world_data| {
                    if (world_data.model) |model| {
                        rl.drawModel(model, rl.Vector3.zero(), 1.0, .white);
                    } else {
                        try world_data.genModel(self.settings, self.light_shader);
                    }
                }
                rl.gl.rlEnableBackfaceCulling();

                self.light_shader.deactivate();

                self.camera.end();

                self.drawUi();

                rl.endDrawing();
            },
        }
    }
}
