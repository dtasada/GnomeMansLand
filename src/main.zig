const rl = @import("raylib");
const std = @import("std");
const toml = @import("toml");
const Camera = @import("rcamera.zig");
const Light = @import("light.zig");
const Settings = @import("settings.zig");
const WorldGen = @import("worldgen.zig");

fn centerMouse() void {
    const margin = 24;
    const x = rl.getMouseX();
    const y = rl.getMouseY();
    const centerX = @divFloor(rl.getScreenWidth(), 2);
    const centerY = @divFloor(rl.getScreenHeight(), 2);

    if (x >= rl.getScreenWidth() - margin or x <= margin)
        rl.setMousePosition(centerX, y);
    if (y >= rl.getScreenHeight() - margin or y <= margin)
        rl.setMousePosition(x, centerY);
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

    rl.initWindow(screenWidth, screenHeight, "City");
    rl.setTargetFPS(60);
    rl.disableCursor();
    rl.hideCursor();
}

fn setupLights(alloc: std.mem.Allocator) !struct { rl.Shader, std.ArrayList(Light) } {
    const light_shader = rl.loadShader("./resources/shaders/lighting.vert.glsl", "./resources/shaders/lighting.frag.glsl") catch unreachable;
    light_shader.locs[@intFromEnum(rl.ShaderLocationIndex.vector_view)] = rl.getShaderLocation(light_shader, "viewPos");
    const ambientLoc = rl.getShaderLocation(light_shader, "ambient");
    const ambient: [4]f32 = .{ 0.1, 0.1, 0.1, 1.0 };
    rl.setShaderValue(light_shader, ambientLoc, &ambient, .vec4);

    var lights = try std.ArrayList(Light).initCapacity(alloc, 32);
    try lights.append(alloc, Light.init(.point, rl.Vector3.init(200, 200, 200), rl.Vector3.zero(), .white, 1, light_shader));
    // try lights.append(alloc, Light.init(.point, rl.Vector3.init(-2, 20, -2), rl.Vector3.zero(), .yellow, 0.5, light_shader));
    // try lights.append(alloc, Light.init(.point, rl.Vector3.init(2, 20, 2), rl.Vector3.zero(), .red, 0.5, light_shader));
    // try lights.append(alloc, Light.init(.point, rl.Vector3.init(-2, 20, 2), rl.Vector3.zero(), .green, 0.5, light_shader));
    // try lights.append(alloc, Light.init(.point, rl.Vector3.init(2, 20, -2), rl.Vector3.zero(), .blue, 0.5, light_shader));

    return .{ light_shader, lights };
}

fn parseConfig(alloc: std.mem.Allocator) Settings {
    const file = std.fs.cwd().readFileAlloc(alloc, "./config.json", 4096) catch unreachable;
    defer alloc.free(file);
    const parsed = std.json.parseFromSlice(Settings, alloc, file, .{}) catch |err| std.debug.panic("Error parsing config.json: {}\n", .{err});
    defer parsed.deinit();
    return parsed.value;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    setupRaylib();
    defer rl.closeWindow();

    const settings = parseConfig(alloc);
    var wg = try WorldGen.init(alloc, settings);
    // defer wg.deinit(alloc);

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

    var cameraFirstPerson = false;

    const light_shader, var lights = try setupLights(alloc);
    wg.model.materials[0].shader = light_shader;

    defer light_shader.unload();
    defer lights.deinit(alloc);
    defer wg.model.unload();

    while (!rl.windowShouldClose()) {
        // update step
        if (cameraFirstPerson)
            Camera.update(&camera1, .first_person)
        else
            Camera.update(&camera3, .third_person);

        centerMouse();

        if (rl.isKeyPressed(.minus)) {
            for (lights.items) |*l|
                l.intensity -= 0.1;
        }

        if (rl.isKeyPressed(.equal)) {
            for (lights.items) |*l|
                l.intensity += 0.1;
        }

        if (rl.isKeyPressed(.k)) {
            cameraFirstPerson = !cameraFirstPerson;
        }

        Light.update_lights(&(if (cameraFirstPerson) camera1 else camera3), light_shader, lights);

        // render step
        rl.beginDrawing();
        rl.clearBackground(.black);

        rl.beginMode3D(if (cameraFirstPerson) camera1 else camera3);
        light_shader.activate();

        for (lights.items) |l| rl.drawSphere(l.position, 10, l.color);

        rl.gl.rlDisableBackfaceCulling();
        rl.drawModel(wg.model, rl.Vector3.zero(), 1.0, .white);
        rl.gl.rlEnableBackfaceCulling();

        light_shader.deactivate();

        rl.endMode3D(if (cameraFirstPerson) camera1 else camera3);

        rl.drawText(rl.textFormat("Camera x: %.1f, y: %.1f, z: %.1f", .{
            camera3.position.x,
            camera3.position.y,
            camera3.position.z,
        }), 12, 12, 24, .white);
        rl.drawText(rl.textFormat("Mouse x: %d, y: %d", .{
            rl.getMouseX(),
            rl.getMouseY(),
        }), 12, 32, 24, .white);

        rl.endDrawing();
    }

    wg.deinit(alloc);
}
