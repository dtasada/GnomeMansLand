const rl = @import("raylib");
const std = @import("std");
const commons = @import("../commons.zig");

const FontSize = enum(i32) {
    title = 48,
    body = 24,
};

const Anchor = enum {
    topleft,
    center,
};

pub const Text = Text_(false);
pub const TextVariable = Text_(true);

/// Button struct.
pub const Button = struct {
    text: Text_(false),

    padding_x: f32,
    padding_y: f32,
    hitbox: rl.Rectangle,

    pub fn init(settings: struct {
        text: []const u8,
        x: f32,
        y: f32,
        font: ?rl.Font = null,
        font_size: FontSize = .body,
        padding_x: f32 = 4.0,
        padding_y: f32 = 4.0,
        text_spacing: f32 = 2.0,
        text_color: rl.Color = .white,
    }) !Button {
        const text = try Text.init(.{
            .body = settings.text,
            .x = settings.x,
            .y = settings.y,
            .font_size = settings.font_size,
            .font = settings.font orelse try rl.getFontDefault(),
            .spacing = settings.text_spacing,
            .color = settings.text_color,
            .anchor = .topleft,
        });
        const text_dimensions = rl.measureTextEx(
            text.font,
            commons.getCString(text.body),
            @floatFromInt(@intFromEnum(text.font_size)),
            text.spacing,
        );

        return .{
            .text = text,
            .padding_x = settings.padding_x,
            .padding_y = settings.padding_y,
            .hitbox = rl.Rectangle.init(
                text.x - settings.padding_x,
                text.y - settings.padding_y,
                text_dimensions.x + settings.padding_x * 2.0,
                text_dimensions.y + settings.padding_y * 2.0,
            ),
        };
    }

    pub fn update(self: *Button, action: anytype, args: anytype) !void {
        rl.drawRectangleRec(self.hitbox, .red);

        self.text.update();

        if (rl.checkCollisionPointRec(rl.getMousePosition(), self.hitbox) and rl.isMouseButtonPressed(.left)) {
            try @call(.auto, action, args);
        }
    }
};

/// Container for a list of vertically stacked buttons.
pub const ButtonSet = struct {
    buttons: []Button,

    pub fn initSpecific(alloc: std.mem.Allocator, buttons: []Button) !ButtonSet {
        const self = ButtonSet{ .buttons = try alloc.alloc(Button, buttons.len) };

        @memcpy(self.buttons, buttons);

        return self;
    }

    pub fn initGeneric(
        alloc: std.mem.Allocator,
        settings: struct {
            top_left_x: f32,
            top_left_y: f32,
            font: ?rl.Font = null,
            font_size: FontSize = .body,
            padding_x: f32 = 4.0,
            padding_y: f32 = 4.0,
            text_spacing: f32 = 2.0,
            text_color: rl.Color = .white,
            padding_between_buttons: f32 = 4.0,
        },
        button_texts: []const []const u8,
    ) !ButtonSet {
        const self = ButtonSet{ .buttons = try alloc.alloc(Button, button_texts.len) };
        errdefer alloc.free(self.buttons);

        for (button_texts, 0..) |text, i|
            self.buttons[i] = try Button.init(.{
                .text = text,
                .x = settings.top_left_x,
                .y = if (i == 0) // if the first one, just base it on topleft
                    settings.top_left_y
                else // othewise, base it on location of the last one.
                    self.buttons[i - 1].text.y + self.buttons[i - 1].hitbox.height + settings.padding_between_buttons,
                .font = settings.font,
                .font_size = settings.font_size,
                .padding_x = settings.padding_x,
                .padding_y = settings.padding_y,
                .text_spacing = settings.text_spacing,
                .text_color = settings.text_color,
            });

        return self;
    }

    pub fn deinit(self: *ButtonSet, alloc: std.mem.Allocator) void {
        alloc.free(self.buttons);
    }

    pub fn update(self: *ButtonSet, actions_and_args: anytype) !void {
        const fields = std.meta.fields(@TypeOf(actions_and_args));

        inline for (fields, 0..) |field, i| {
            const button_actions_and_args = @field(actions_and_args, field.name);
            const action = button_actions_and_args[0];
            const args = button_actions_and_args[1];
            try self.buttons[i].update(action, args);
        }
    }
};

/// Doesn't allocate memory and takes slice.
/// M is a boolean and represents if the inner body is mutable or not.
fn Text_(M: bool) type {
    const string_type = if (M) []u8 else []const u8;

    return struct {
        body: string_type,
        x: f32, // x of anchor point
        y: f32, // y of anchor point
        font_size: FontSize,
        font: rl.Font,
        spacing: f32,
        color: rl.Color,
        anchor: Anchor,
        hitbox: rl.Rectangle,

        pub fn init(settings: struct {
            body: string_type,
            x: f32,
            y: f32,
            font: ?rl.Font = null,
            font_size: FontSize = .body,
            spacing: f32 = 2.0,
            color: rl.Color = .white,
            anchor: Anchor = .topleft,
        }) !Text_(M) {
            const font = settings.font orelse try rl.getFontDefault();
            const dimensions = rl.measureTextEx(
                font,
                commons.getCString(settings.body),
                @floatFromInt(@intFromEnum(settings.font_size)),
                settings.spacing,
            );
            return .{
                .body = settings.body,
                .x = settings.x,
                .y = settings.y,
                .font = font,
                .font_size = settings.font_size,
                .spacing = settings.spacing,
                .color = settings.color,
                .anchor = settings.anchor,
                .hitbox = rl.Rectangle.init(
                    settings.x,
                    settings.y,
                    dimensions.x,
                    dimensions.y,
                ),
            };
        }

        /// Draws text on the screen.
        pub fn update(self: Text_(M)) void {
            self.drawBuffer(self.body);
        }

        /// Actually draws the text on the screen. buf is passed to allow drawing any buffer.
        /// Kinda bs but necessary for TextBox lol
        pub fn drawBuffer(self: Text_(M), buf: string_type) void {
            rl.drawTextEx(
                self.font,
                commons.getCString(buf),
                switch (self.anchor) {
                    .topleft => .init(self.x, self.y),
                    .center => .init(self.x - self.hitbox.width / 2.0, self.y - self.hitbox.height / 2.0),
                },
                @floatFromInt(@intFromEnum(self.font_size)),
                self.spacing,
                self.color,
            );
        }
    };
}

/// Allocates 64 bytes. Don't forget to deinit
pub const TextBox = struct {
    content: TextVariable,
    len: usize,

    pub fn init(alloc: std.mem.Allocator, settings: struct {
        x: f32,
        y: f32,
        default_body: []const u8 = "",
        font: ?rl.Font = null,
        font_size: FontSize = .body,
        spacing: f32 = 2.0,
        color: rl.Color = .white,
        anchor: Anchor = .topleft,
    }) !TextBox {
        var self = TextBox{
            .content = try TextVariable.init(.{
                .x = settings.x,
                .y = settings.y,
                .body = "",
                .font = settings.font,
                .font_size = settings.font_size,
                .spacing = settings.spacing,
                .color = settings.color,
                .anchor = settings.anchor,
            }),
            .len = settings.default_body.len,
        };

        self.content.body = try alloc.alloc(u8, 64);
        @memset(self.content.body, 0);
        @memcpy(self.content.body[0..settings.default_body.len], settings.default_body);
        return self;
    }

    pub fn deinit(self: *TextBox, alloc: std.mem.Allocator) void {
        alloc.free(self.content.body);
    }

    pub fn update(self: *TextBox) !void {
        const key = rl.getCharPressed();
        if (key != 0 and self.len < self.content.body.len) {
            self.content.body[self.len] = @intCast(key);
            self.len += 1;
        }

        self.content.drawBuffer(self.content.body[0..self.len]);
    }
};
