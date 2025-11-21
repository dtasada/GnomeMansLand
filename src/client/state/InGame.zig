const std = @import("std");

const rl = @import("raylib");

const commons = @import("commons");
const ui = @import("ui.zig");
const socket_packet = @import("socket_packet");
const rcamera = Game.rcamera;
const input = Game.input;

const Game = @import("game");

const Self = @This();

camera: ?rl.Camera3D = null,
camera_mode: enum { first_person, isometric } = .isometric,
camera_sens: f32 = 0.1,
mouse_is_enabled: bool = true,

lights: std.ArrayList(Game.Light) = .{},
light_shader: rl.Shader,

pub fn init(alloc: std.mem.Allocator) !Self {
    var self: Self = .{
        .light_shader = try getLightShader(),
    };

    try self.lights.append(alloc, Game.Light.init(
        .point,
        .init(200, 200, 0),
        .zero(),
        .white,
        1.0,
        self.light_shader,
    ));

    return self;
}

pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
    self.lights.deinit(alloc);
    self.light_shader.unload();
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

/// resets camera back to the middle of the world
pub fn resetCamera(self: *Self, game: *Game) void {
    if (game.client) |client| {
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

fn drawUi(self: *const Self, game: *Game) void {
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
    if (game.client) |client| {
        if (client.game_data.world_data) |world_data| {
            rl.drawText(rl.textFormat("World: %dx%d, Complete: %d", .{
                world_data.size.x,
                world_data.size.y,
                @as(i32, if (world_data.allFloatsDownloaded()) 1 else 0),
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

pub fn update(self: *Self, game: *Game) !void {
    // loading screen
    if (game.client) |client| {
        if (client.game_data.world_data) |*world_data| {
            if (!world_data.allFloatsDownloaded() or !world_data.allModelsGenerated()) {
                rl.beginDrawing();
                rl.clearBackground(.black);

                var buf: [33]u8 = undefined; // hardcoded 33 bytes bc that's the longest possible string.
                const body = if (!world_data.allFloatsDownloaded())
                    try std.fmt.bufPrint(&buf, "Downloading world ({}%)...", .{
                        @divFloor(100 * world_data._height_map_filled, world_data.height_map.len),
                    })
                else if (!world_data.allModelsGenerated()) blk: {
                    world_data.genModels(game.settings, self.light_shader) catch |err| {
                        commons.print("Failed to generate model: {}", .{err}, .red);
                    };
                    break :blk try std.fmt.bufPrint(&buf, "Generating world models ({}%)...", .{
                        @divFloor(100 * world_data.models_generated, world_data.models.len),
                    });
                } else unreachable;

                var loading_screen_text = try ui.Text.init(.{
                    .x = @as(f32, @floatFromInt(rl.getScreenWidth())) / 2.0,
                    .y = @as(f32, @floatFromInt(rl.getScreenHeight())) / 2.0,
                    .anchor = .center,
                    .body = body,
                });

                loading_screen_text.update();

                rl.endDrawing();
                return;
            }
        }
    }

    // update step
    try input.handleKeys(self, game);

    if (self.camera) |*camera|
        Game.Light.updateLights(camera, self.light_shader, self.lights);

    // render step
    rl.beginDrawing();
    rl.clearBackground(.sky_blue);

    if (self.camera) |c| c.begin();

    // draw lights and models
    self.light_shader.activate();

    for (self.lights.items) |l| rl.drawSphere(l.position, 10, l.color);

    rl.gl.rlDisableBackfaceCulling();

    if (game.client) |client| {
        if (client.game_data.world_data) |*world_data| {
            if (self.camera == null)
                self.resetCamera(game);

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
            if (world_data.allModelsGenerated()) {
                for (world_data.models) |model| if (model) |m| {
                    m.draw(.zero(), 1.0, .white);
                } else unreachable;
            }
        }
    }

    rl.gl.rlEnableBackfaceCulling();

    self.light_shader.deactivate();

    if (self.camera) |c| c.end();

    self.drawUi(game);

    rl.endDrawing();
}
