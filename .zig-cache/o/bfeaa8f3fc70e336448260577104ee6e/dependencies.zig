pub const packages = struct {
    pub const @"N-V-__8AABHMqAWYuRdIlflwi8gksPnlUMQBiSxAqQAAZFms" = struct {
        pub const available = true;
        pub const build_root = "/Users/dt/.cache/zig/p/N-V-__8AABHMqAWYuRdIlflwi8gksPnlUMQBiSxAqQAAZFms";
        pub const deps: []const struct { []const u8, []const u8 } = &.{};
    };
    pub const @"N-V-__8AAJl1DwBezhYo_VE6f53mPVm00R-Fk28NPW7P14EQ" = struct {
        pub const available = false;
    };
    pub const @"N-V-__8AAOQabwCjOjMI2uUTw4Njc0tAUOO6Lw2kCydLbvVG" = struct {
        pub const build_root = "/Users/dt/.cache/zig/p/N-V-__8AAOQabwCjOjMI2uUTw4Njc0tAUOO6Lw2kCydLbvVG";
        pub const deps: []const struct { []const u8, []const u8 } = &.{};
    };
    pub const @"pretty-0.10.4-Tm65r5pKAQDdxCFNtL6huo7lHc_HWn6v4VO5WaTufpRQ" = struct {
        pub const build_root = "/Users/dt/.cache/zig/p/pretty-0.10.4-Tm65r5pKAQDdxCFNtL6huo7lHc_HWn6v4VO5WaTufpRQ";
        pub const build_zig = @import("pretty-0.10.4-Tm65r5pKAQDdxCFNtL6huo7lHc_HWn6v4VO5WaTufpRQ");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
    pub const @"raylib-5.5.0-whq8uBlJxwRAvOHHNQIi8WS0QTbQJcdx7FbjSSOnPn6n" = struct {
        pub const build_root = "/Users/dt/.cache/zig/p/raylib-5.5.0-whq8uBlJxwRAvOHHNQIi8WS0QTbQJcdx7FbjSSOnPn6n";
        pub const build_zig = @import("raylib-5.5.0-whq8uBlJxwRAvOHHNQIi8WS0QTbQJcdx7FbjSSOnPn6n");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
            .{ "xcode_frameworks", "N-V-__8AABHMqAWYuRdIlflwi8gksPnlUMQBiSxAqQAAZFms" },
            .{ "emsdk", "N-V-__8AAJl1DwBezhYo_VE6f53mPVm00R-Fk28NPW7P14EQ" },
        };
    };
    pub const @"raylib_zig-5.6.0-dev-KE8REH9ABQBo9v5YfUwPYdgihp7NNFOr_2FJOiVJH7bH" = struct {
        pub const build_root = "/Users/dt/.cache/zig/p/raylib_zig-5.6.0-dev-KE8REH9ABQBo9v5YfUwPYdgihp7NNFOr_2FJOiVJH7bH";
        pub const build_zig = @import("raylib_zig-5.6.0-dev-KE8REH9ABQBo9v5YfUwPYdgihp7NNFOr_2FJOiVJH7bH");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
            .{ "raylib", "raylib-5.5.0-whq8uBlJxwRAvOHHNQIi8WS0QTbQJcdx7FbjSSOnPn6n" },
            .{ "raygui", "N-V-__8AAOQabwCjOjMI2uUTw4Njc0tAUOO6Lw2kCydLbvVG" },
        };
    };
    pub const @"toml-0.3.0-bV14BaN6AQCB2xK3BdZJxb7s5cMYTlnPwfWt2RO-U6mr" = struct {
        pub const build_root = "/Users/dt/.cache/zig/p/toml-0.3.0-bV14BaN6AQCB2xK3BdZJxb7s5cMYTlnPwfWt2RO-U6mr";
        pub const build_zig = @import("toml-0.3.0-bV14BaN6AQCB2xK3BdZJxb7s5cMYTlnPwfWt2RO-U6mr");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
};

pub const root_deps: []const struct { []const u8, []const u8 } = &.{
    .{ "raylib_zig", "raylib_zig-5.6.0-dev-KE8REH9ABQBo9v5YfUwPYdgihp7NNFOr_2FJOiVJH7bH" },
    .{ "toml", "toml-0.3.0-bV14BaN6AQCB2xK3BdZJxb7s5cMYTlnPwfWt2RO-U6mr" },
    .{ "pretty", "pretty-0.10.4-Tm65r5pKAQDdxCFNtL6huo7lHc_HWn6v4VO5WaTufpRQ" },
};
