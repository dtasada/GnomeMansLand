const rl = @import("raylib");
const std = @import("std");
const rg = @import("raygui");
const Camera = @import("rcamera.zig");
const Light = @import("light.zig");
const Settings = @import("settings.zig");
const WorldGen = @import("worldgen.zig");
const Server = @import("server.zig");
const Client = @import("client.zig");

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

fn setupRaylib() void {
    const screenWidth = 1280;
    const screenHeight = 720;

    rl.setConfigFlags(.{
        .window_highdpi = true,
        .vsync_hint = true,
        .window_resizable = true,
        .msaa_4x_hint = true,
    });

    rl.initWindow(screenWidth, screenHeight, "Gnome Man's Land");
    rl.setExitKey(.null);
    rl.setTargetFPS(60);
    rl.disableCursor();
    rl.hideCursor();
}

fn setupLights(alloc: std.mem.Allocator) !struct { rl.Shader, std.ArrayList(Light) } {
    const light_shader = rl.loadShader("./resources/shaders/lighting.vert.glsl", "./resources/shaders/lighting.frag.glsl") catch unreachable;
    light_shader.locs[@intFromEnum(rl.ShaderLocationIndex.vector_view)] = rl.getShaderLocation(light_shader, "viewPos");
    const ambient_loc = rl.getShaderLocation(light_shader, "ambient");
    const ambient: [4]f32 = .{ 0.1, 0.1, 0.1, 1.0 };
    rl.setShaderValue(light_shader, ambient_loc, &ambient, .vec4);

    var lights = try std.ArrayList(Light).initCapacity(alloc, 32);
    try lights.append(alloc, Light.init(.point, rl.Vector3.init(200, 200, 200), rl.Vector3.zero(), .white, 1, light_shader));
    // try lights.append(alloc, Light.init(.point, rl.Vector3.init(-2, 20, -2), rl.Vector3.zero(), .yellow, 0.5, light_shader));
    // try lights.append(alloc, Light.init(.point, rl.Vector3.init(2, 20, 2), rl.Vector3.zero(), .red, 0.5, light_shader));
    // try lights.append(alloc, Light.init(.point, rl.Vector3.init(-2, 20, 2), rl.Vector3.zero(), .green, 0.5, light_shader));
    // try lights.append(alloc, Light.init(.point, rl.Vector3.init(2, 20, -2), rl.Vector3.zero(), .blue, 0.5, light_shader));

    return .{ light_shader, lights };
}

fn parseConfig(alloc: std.mem.Allocator) !std.json.Parsed(Settings) {
    const file = std.fs.cwd().readFileAlloc(alloc, "./config.json", 4096) catch unreachable;
    defer alloc.free(file);

    return try std.json.parseFromSlice(Settings, alloc, file, .{});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    setupRaylib();
    defer rl.closeWindow();

    var settings_parsed = try parseConfig(alloc);
    defer settings_parsed.deinit();
    const settings = &settings_parsed.value;

    var wg = try WorldGen.init(alloc, settings);
    defer wg.deinit(alloc);

    var camera3 = rl.Camera3D{
        .fovy = 100,
        .position = rl.Vector3.one().scale(@floatFromInt(wg.size[0])),
        .projection = .orthographic,
        .target = rl.Vector3.zero(),
        .up = rl.Vector3.init(0, 1, 0),
    };

    var camera1 = rl.Camera3D{
        .fovy = 90,
        .position = rl.Vector3.zero(),
        .projection = .perspective,
        .target = rl.Vector3.init(1, 0, 0),
        .up = rl.Vector3.init(0, 1, 0),
    };

    var camera_is_first_person = false;

    const light_shader, var lights = try setupLights(alloc);
    wg.model.materials[0].shader = light_shader;

    defer light_shader.unload();
    defer lights.deinit(alloc);

    var mouse = false;
    var game_state: enum { lobby, game } = .lobby;

    var server: ?Server = null;
    var client: ?Client = null;

    defer {
        if (client) |*c| c.deinit();
        if (server) |*s| s.deinit();
    }

    while (!rl.windowShouldClose()) {
        if (game_state == .lobby) {
            if (!mouse) toggleMouse(&mouse);
            rl.beginDrawing();
            rl.clearBackground(.black);

            if (rg.button(.init(12, 92, 256, 72), "Host server")) {
                if (server == null) server = try Server.init(settings);
            }

            if (rg.button(.init(12, 192, 256, 72), "Connect to server")) {
                if (client == null) client = try Client.init(settings);
                game_state = .game;
            }

            rl.endDrawing();
            continue;
        }

        // update step
        if (rl.isMouseButtonDown(.right)) {
            if (mouse) toggleMouse(&mouse);

            centerMouse();
            if (camera_is_first_person)
                Camera.update(&camera1, .first_person)
            else
                Camera.update(&camera3, .third_person);
        } else if (!mouse) toggleMouse(&mouse);

        if (rl.isKeyPressed(.minus)) {
            for (lights.items) |*l|
                l.intensity -= 0.1;
        }

        if (rl.isKeyPressed(.equal)) {
            for (lights.items) |*l|
                l.intensity += 0.1;
        }

        if (rl.isKeyPressed(.k))
            camera_is_first_person = !camera_is_first_person;

        if (rl.isKeyPressed(.space))
            try client.?.sendMessage("ping!");

        Light.updateLights(&(if (camera_is_first_person) camera1 else camera3), light_shader, lights);

        // render step
        rl.beginDrawing();
        rl.clearBackground(.black);

        rl.beginMode3D(if (camera_is_first_person) camera1 else camera3);
        light_shader.activate();

        for (lights.items) |l| rl.drawSphere(l.position, 10, l.color);

        rl.gl.rlDisableBackfaceCulling();
        rl.drawModel(wg.model, rl.Vector3.zero(), 1.0, .white);
        rl.gl.rlEnableBackfaceCulling();

        light_shader.deactivate();

        rl.endMode3D();

        rl.drawText(rl.textFormat("Camera x: %.1f, y: %.1f, z: %.1f", .{
            camera3.position.x,
            camera3.position.y,
            camera3.position.z,
        }), 12, 12, 24, .white);

        rl.drawText(rl.textFormat("Mouse x: %d, y: %d", .{
            rl.getMouseX(),
            rl.getMouseY(),
        }), 12, 32, 24, .white);

        rl.drawText(rl.textFormat("FPS: %d", .{rl.getFPS()}), 12, 52, 24, .white);

        rl.endDrawing();
    }
}
