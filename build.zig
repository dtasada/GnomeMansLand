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
    pub inline fn addImports(self: *const Module, mods: []const Module) void {
        for (mods) |i| self.mod.addImport(i.name, i.mod);
    }

    /// Adds a single import to `self`
    pub fn addImport(self: *const Module, mod: Module) void {
        self.mod.addImport(mod.name, mod.mod);
    }
};

const Modules = struct {
    build: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,

    pub fn init(
        b: *std.Build,
        target: std.Build.ResolvedTarget,
        optimize: std.builtin.OptimizeMode,
    ) Modules {
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

    const exe = b.addExecutable(.{
        .name = "gnome_mans_land",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const modules = Modules.init(b, target, optimize);

    const raylib_dep = b.dependency("raylib_zig", .{ .target = target, .optimize = optimize });
    const raylib_artifact = raylib_dep.artifact("raylib");

    // dependencies
    const raylib_mod = Module.init("raylib", raylib_dep.module("raylib"));
    const raygui_mod = Module.init("raygui", raylib_dep.module("raygui"));
    const network_mod = Module.init("network", b.dependency("network", .{}).module("network"));
    const s2s_mod = Module.init("s2s", b.dependency("s2s", .{}).module("s2s"));

    // internal packages
    const socket_packet_mod = modules.create("socket_packet", "src/socket_packet.zig");
    const commons_mod = modules.create("commons", "src/commons.zig");
    const client_mod = modules.create("client", "src/client/Client.zig");
    const server_mod = modules.create("server", "src/server/Server.zig");
    const state_mod = modules.create("state", "src/client/state/State.zig");
    const game_mod = modules.create("game", "src/client/game/Game.zig");

    client_mod.addImports(&.{ commons_mod, game_mod, network_mod, s2s_mod, socket_packet_mod });
    server_mod.addImports(&.{ commons_mod, network_mod, s2s_mod, socket_packet_mod });
    state_mod.addImports(&.{ client_mod, commons_mod, game_mod, raylib_mod, server_mod, socket_packet_mod });
    game_mod.addImports(&.{ client_mod, commons_mod, raygui_mod, raylib_mod, server_mod, socket_packet_mod, state_mod });
    socket_packet_mod.addImports(&.{ commons_mod, server_mod });

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

    // check for lsp
    const exe_check = b.addExecutable(.{
        .name = "dmr",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    exe_check.root_module.addImport("game", game_mod.mod);
    exe_check.root_module.addImport("commons", commons_mod.mod);

    const check = b.step("check", "Check if gnome_mans_land compiles");
    check.dependOn(&exe_check.step);
}
