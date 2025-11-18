const std = @import("std");
const rl = @import("raylib");

const commons = @import("commons");
const socket_packet = @import("socket_packet");
const rcamera = Game.rcamera;

const InGame = @import("state").InGame;
const Game = @import("Game.zig");

/// input handling
pub fn handleKeys(in_game: *InGame, game: *Game) !void {
    // pan the camera with middle mouse
    if (in_game.camera) |*camera| {
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
        } else if (!in_game.mouse_is_enabled)
            toggleMouse(&in_game.mouse_is_enabled);

        if (rl.isMouseButtonPressed(.left)) {
            if (game.client) |client| {
                if (getMouseToWorld(in_game, game)) |pos| {
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
        for (in_game.lights.items) |*l|
            l.intensity -= 0.1;
    }

    if (rl.isKeyPressed(.equal)) {
        for (in_game.lights.items) |*l|
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
fn getMouseToWorld(in_game: *const InGame, game: *Game) ?rl.Vector3 {
    if (in_game.camera) |camera| {
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
