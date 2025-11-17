const std = @import("std");

const rl = @import("raylib");

const commons = @import("commons");
const ui = @import("ui.zig");
const socket_packet = @import("socket_packet");
const rcamera = Game.rcamera;

const Game = @import("game");

const Self = @This();

camera: ?rl.Camera3D = null,
camera_mode: enum { first_person, isometric } = .isometric,
camera_sens: f32 = 0.1,
mouse_is_enabled: bool = true,

pub fn init() Self {
    return .{};
}

/// input handling
fn handleKeys(self: *Self, game: *Game) !void {
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
        } else if (!self.mouse_is_enabled)
            toggleMouse(&self.mouse_is_enabled);

        if (rl.isMouseButtonPressed(.left)) {
            if (game.client) |client| {
                if (self.getMouseToWorld(game)) |pos| {
                    const move_player = socket_packet.MovePlayer.init(.init(pos.x, pos.z));
                    const move_player_string = try std.json.Stringify.valueAlloc(game.alloc, move_player, .{});
                    defer game.alloc.free(move_player_string);

                    try client.send(move_player_string);
                }
            }
        }
    }

    // debug light intensity
    if (rl.isKeyPressed(.minus)) {
        for (game.lights.items) |*l|
            l.intensity -= 0.1;
    }

    if (rl.isKeyPressed(.equal)) {
        for (game.lights.items) |*l|
            l.intensity += 0.1;
    }
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

/// gets equivalent in-world position from 2d cursor position
fn getMouseToWorld(self: *const Self, game: *Game) ?rl.Vector3 {
    if (self.camera) |camera| {
        if (game.client) |client| {
            if (client.game_data.world_data) |world_data| {
                for (world_data.models) |model| {
                    if (model) |m| {
                        const mouse_pos_ray = rl.getScreenToWorldRay(rl.getMousePosition(), camera);
                        const mouse_world_collision = rl.getRayCollisionMesh(mouse_pos_ray, m.meshes[0], m.transform);
                        if (mouse_world_collision.point.equals(.zero()) != 0)
                            // if collision returns v3(0), skip this model
                            continue
                        else
                            // else return this collision point
                            return mouse_world_collision.point;
                    }
                }
            }
        }
    }

    return null;
}

/// resets camera back to the middle of the world
fn resetCamera(self: *Self, game: *Game) void {
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
                    world_data.genModels(game.settings, game.light_shader) catch |err| {
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
    try self.handleKeys(game);

    if (self.camera) |*camera|
        Game.Light.updateLights(camera, game.light_shader, game.lights);

    // render step
    rl.beginDrawing();
    rl.clearBackground(.sky_blue);

    if (self.camera) |c| c.begin();

    // draw lights and models
    game.light_shader.activate();

    for (game.lights.items) |l| rl.drawSphere(l.position, 10, l.color);

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
                    rl.drawModel(m, .zero(), 1.0, .white);
                } else unreachable;
            }
        }
    }

    rl.gl.rlEnableBackfaceCulling();

    game.light_shader.deactivate();

    if (self.camera) |c| c.end();

    self.drawUi(game);

    rl.endDrawing();
}
