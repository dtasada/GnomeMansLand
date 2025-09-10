const rl = @import("raylib");
const std = @import("std");
const commons = @import("../commons.zig");

const FontSize = enum(i32) {
    title = 96,
    body = 40,
};

const Anchor = enum {
    topleft,
    center,
};

pub const Text = Text_(false);
pub const TextVariable = Text_(true);

pub var chalk_font: rl.Font = undefined;
pub var gwathlyn_font: rl.Font = undefined;

/// Button struct.
pub const Button = struct {
    text: Text_(false),

    padding_x: f32,
    padding_y: f32,
    hitbox: rl.Rectangle,
    hover_anim_bar_width: f32,

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
        var self = Button{
            .text = try Text.init(.{
                .body = settings.text,
                .x = settings.x,
                .y = settings.y,
                .font_size = settings.font_size,
                .font = settings.font orelse chalk_font,
                .spacing = settings.text_spacing,
                .color = settings.text_color,
                .anchor = .topleft,
            }),
            .padding_x = settings.padding_x,
            .padding_y = settings.padding_y,
            .hitbox = undefined,
            .hover_anim_bar_width = 0.0,
        };
        self.hitbox = self.getHitbox();

        return self;
    }

    pub fn getHitbox(self: *Button) rl.Rectangle {
        const text_dimensions = rl.measureTextEx(
            self.text.font,
            commons.getCString(self.text.body),
            @floatFromInt(@intFromEnum(self.text.font_size)),
            self.text.spacing,
        );

        return rl.Rectangle.init(
            self.text.x - self.padding_x,
            self.text.y - self.padding_y,
            text_dimensions.x + self.padding_x * 2.0,
            text_dimensions.y + self.padding_y * 2.0,
        );
    }

    pub fn update(self: *Button, action: anytype, args: anytype) !void {
        self.text.update();

        // draw underlines
        rl.drawRectangleRec(.init(self.hitbox.x, self.hitbox.y + self.hitbox.height - 12.0, self.hitbox.width, 2.0), .gray);
        rl.drawRectangleRec(.init(self.hitbox.x, self.hitbox.y + self.hitbox.height - 12.0, self.hover_anim_bar_width, 2.0), .light_gray);

        if (rl.checkCollisionPointRec(rl.getMousePosition(), self.hitbox)) {
            // increase hover animation bar length
            self.hover_anim_bar_width = @min(self.hover_anim_bar_width + 4.0, self.hitbox.width * 0.67);

            if (rl.isMouseButtonPressed(.left))
                switch (@typeInfo(@typeInfo(@TypeOf(action)).@"fn".return_type.?)) {
                    .error_union => try @call(.auto, action, args),
                    else => @call(.auto, action, args),
                };
        } else {
            // increase hover animation bar length
            self.hover_anim_bar_width = @max(self.hover_anim_bar_width - 4.0, 0.0);
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
                else // otherwise, base it on location of the last one.
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
        if (fields.len != self.buttons.len) {
            commons.print("Amount of tuples passed to ButtonSet.update must equal amount of buttons passed in ButtonSet.init\n", .{}, .red);
            return error.ButtonSetNotMatching;
        }

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
            var self = Text_(M){
                .body = settings.body,
                .x = settings.x,
                .y = settings.y,
                .font = settings.font orelse chalk_font,
                .font_size = settings.font_size,
                .spacing = settings.spacing,
                .color = settings.color,
                .anchor = settings.anchor,
                .hitbox = undefined,
            };
            self.hitbox = self.getHitbox();

            return self;
        }

        /// Returns hitbox for text. Optionally pass in a text length
        fn getHitbox(self: *Text_(M)) rl.Rectangle {
            const dimensions = rl.measureTextEx(
                self.font,
                commons.getCString(self.body),
                @floatFromInt(@intFromEnum(self.font_size)),
                self.spacing,
            );
            return rl.Rectangle.init(self.x, self.y, dimensions.x, @floatFromInt(@intFromEnum(self.font_size)));
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
    last_backspaced: ?i64,
    backspace_fast: bool,
    anim_bar_len: f32,

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
                .font = settings.font orelse chalk_font,
                .font_size = settings.font_size,
                .spacing = settings.spacing,
                .color = settings.color,
                .anchor = settings.anchor,
            }),
            .len = settings.default_body.len,
            .last_backspaced = null,
            .backspace_fast = false,
            .anim_bar_len = 0.0,
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
        const min_length = 96.0;
        const base_bar_len = @max(min_length, self.content.hitbox.width);

        // draw base underline
        rl.drawRectangleRec(
            .init(
                self.content.hitbox.x,
                self.content.hitbox.y + self.content.hitbox.height - 12.0,
                base_bar_len,
                2.0,
            ),
            .gray,
        );

        // draw anime underline
        self.anim_bar_len = if (self.anim_bar_len + 1 < self.content.hitbox.width)
            self.anim_bar_len + 1.0
        else
            @max(self.anim_bar_len - 1.0, 0.0);
        rl.drawRectangleRec(
            .init(
                self.content.hitbox.x,
                self.content.hitbox.y + self.content.hitbox.height - 12.0,
                self.anim_bar_len,
                2.0,
            ),
            .light_gray,
        );

        if (rl.isKeyDown(.backspace) and self.len > 0) {
            if (self.last_backspaced) |t| {
                // backspace only if it's been half a second or it's been 50 ms since last delete
                const now = std.time.milliTimestamp();
                if (now - t > 500 or self.backspace_fast and now - t > 50) {
                    self.last_backspaced = now;
                    self.len -= 1;
                    self.backspace_fast = true;
                }
            } else {
                self.last_backspaced = std.time.milliTimestamp();
                self.len -= 1;
            }
        } else {
            // when releasing backspace, reset last_backspaced and back_space fast
            self.backspace_fast = false;
            self.last_backspaced = null;

            var key = rl.getCharPressed(); // get char pressed
            while (key != 0) { // loop until all chars have been processed
                if (self.len < self.content.body.len - 1) {
                    self.content.body[self.len] = @intCast(key); // set last character to key
                    self.len += 1; // increase len
                }
                key = rl.getCharPressed(); // get next char
            }
        }
        self.content.hitbox = self.content.getHitbox(); // draw underline for length of buffer

        self.content.body[self.len] = 0; // set last char to '\0' so its readable as a cstring
        self.content.drawBuffer(self.content.body[0..self.len]);
    }
};
