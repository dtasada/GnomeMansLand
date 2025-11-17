const std = @import("std");

const Module = struct {
    name: []const u8,
    mod: *std.Build.Module,

    pub fn init(name: []const u8, mod: *std.Build.Module) Module {
        return .{
            .name = name,
            .mod = mod,
        };
    }

    /// Adds every Module in `mods` as an import to `self`
    pub fn addImports(self: *const Module, mods: []const Module) Module {
        for (mods) |i| self.mod.addImport(i.name, i.mod);
        return self.*;
    }

    /// Adds a single import to `self`
    pub fn addImport(self: *const Module, mod: Module) void {
        self.mod.addImport(mod.name, mod.mod);
    }

    /// Adds `self` as import to each Module in `mods`
    pub fn importTo(self: *const Module, mods: []const Module) void {
        for (mods) |m| m.addImport(self.*);
    }
};

const Modules = struct {
    build: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,

    pub fn init(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) Modules {
        return .{
            .build = b,
            .target = target,
            .optimize = optimize,
        };
    }

    /// Creates a Module
    pub fn create(self: *const Modules, import_name: []const u8, root_source_file: []const u8) Module {
        return .{
            .name = import_name,
            .mod = self.build.createModule(.{
                .root_source_file = self.build.path(root_source_file),
                .target = self.target,
                .optimize = self.optimize,
            }),
        };
    }
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "gnome_mans_land",
        .root_module = exe_mod,
    });

    const modules = Modules.init(b, target, optimize);

    const raylib_dep = b.dependency("raylib_zig", .{ .target = target, .optimize = optimize });
    const raylib_artifact = raylib_dep.artifact("raylib");

    const raylib_mod: Module = .init("raylib", raylib_dep.module("raylib"));
    const raygui_mod: Module = .init("raygui", raylib_dep.module("raygui"));
    const network_mod: Module = .init("network", b.dependency("network", .{}).module("network"));

    const commons_mod = modules.create("commons", "src/commons.zig");

    const socket_packet_mod = modules.create("socket_packet", "src/socket_packet.zig");

    const client_mod = modules.create("client", "src/client/Client.zig");
    const server_mod = modules.create("server", "src/server/Server.zig");
    network_mod.importTo(&.{ client_mod, server_mod });
    socket_packet_mod.addImport(server_mod);

    const states_mod = modules.create("states", "src/client/states/states.zig");

    const game_mod = modules.create("game", "src/client/game/Game.zig").addImports(&.{ raygui_mod, states_mod });

    // add raylib, client and server to both game and states
    raylib_mod.importTo(&.{ game_mod, states_mod });
    client_mod.importTo(&.{ game_mod, states_mod });
    server_mod.importTo(&.{ game_mod, states_mod });

    // add game to states and client
    game_mod.importTo(&.{ states_mod, client_mod });

    // add commons to everything
    commons_mod.importTo(&.{
        socket_packet_mod,
        client_mod,
        server_mod,
        states_mod,
        game_mod,
    });

    // add socket_packet to everything
    socket_packet_mod.importTo(&.{
        server_mod,
        states_mod,
        game_mod,
    });

    exe.root_module.addImport("game", game_mod.mod);
    exe.root_module.addImport("commons", commons_mod.mod);

    exe.linkLibrary(raylib_artifact);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
