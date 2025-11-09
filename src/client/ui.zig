const rl = @import("raylib");
const std = @import("std");

const commons = @import("../commons.zig");

const MAX_LEN: usize = 64;

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

pub inline fn getRight(hitbox: rl.Rectangle) f32 {
    return hitbox.x + hitbox.width;
}

/// Button struct.
pub const Button = struct {
    text: Text_(false),
    text_cstr: [MAX_LEN:0]u8,

    padding_x: f32,
    padding_y: f32,
    hitbox: rl.Rectangle,
    hover_anim_bar_width: f32,

    pub fn init(
        settings: struct {
            text: []const u8,
            x: f32,
            y: f32,
            font: ?rl.Font = null,
            font_size: FontSize = .body,
            padding_x: f32 = 4.0,
            padding_y: f32 = 4.0,
            text_spacing: f32 = 2.0,
            text_color: rl.Color = .white,
        },
    ) !Button {
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
            .text_cstr = undefined,
        };
        self.hitbox = self.getHitbox();

        return self;
    }

    pub fn getHitbox(self: *Button) rl.Rectangle {
        commons.toSentinel(self.text.body, &self.text_cstr);

        const text_dimensions = rl.measureTextEx(
            self.text.font,
            &self.text_cstr,
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

    pub fn deinit(self: *const ButtonSet, alloc: std.mem.Allocator) void {
        alloc.free(self.buttons);
    }

    pub fn update(self: *const ButtonSet, actions_and_args: anytype) !void {
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
        body_cstr: [MAX_LEN:0]u8,

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
                .body_cstr = undefined,
            };
            self.hitbox = self.getHitbox();

            return self;
        }

        /// Returns hitbox for text.
        pub fn getHitbox(self: *Text_(M)) rl.Rectangle {
            commons.toSentinel(self.body, &self.body_cstr);

            const dimensions = rl.measureTextEx(
                self.font,
                &self.body_cstr,
                @floatFromInt(@intFromEnum(self.font_size)),
                self.spacing,
            );
            return rl.Rectangle.init(self.x, self.y, dimensions.x, @floatFromInt(@intFromEnum(self.font_size)));
        }

        /// Draws text on the screen.
        pub fn update(self: *Text_(M)) void {
            self.drawBuffer(self.body);
        }

        /// Actually draws the text on the screen. buf is passed to allow drawing any buffer.
        /// Kinda bs but necessary for TextBox lol
        pub fn drawBuffer(self: *Text_(M), buf: string_type) void {
            commons.toSentinel(buf, &self.body_cstr);

            rl.drawTextEx(
                self.font,
                &self.body_cstr,
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

/// Allocates MAX_LEN bytes. Don't forget to deinit
pub const BoxLabel = struct {
    label: []const u8,
    max_len: usize, // input size excluding sentinel
    default_value: []const u8,
};

pub const TextBox = struct {
    label: Text,
    inner_text: TextVariable,
    len: usize,
    max_len: usize,
    focused: bool,
    last_backspaced: ?i64,
    backspace_fast: bool,
    anim_bar_len: f32,

    // NEW fields for cursor handling / blinking
    cursor_pos: usize, // position of caret in [0..len]
    cursor_last_blink: i64, // last time caret blink toggled
    cursor_visible: bool, // current visible state of caret
    till_cursor_cstr: [MAX_LEN:0]u8,

    pub fn init(alloc: std.mem.Allocator, settings: struct {
        x: f32,
        y: f32,
        default_body: []const u8 = "",
        label: []const u8 = "",
        font: ?rl.Font = null,
        font_size: FontSize = .body,
        spacing: f32 = 2.0,
        color: rl.Color = .white,
        anchor: Anchor = .topleft,
        max_len: usize = MAX_LEN,
    }) !TextBox {
        const label = try Text.init(.{
            .x = settings.x,
            .y = settings.y,
            .body = settings.label,
        });
        var self = TextBox{
            .inner_text = try TextVariable.init(.{
                .x = getRight(label.hitbox) + 16.0,
                .y = settings.y,
                .body = "", // gets set right after this
                .font = settings.font orelse chalk_font,
                .font_size = settings.font_size,
                .spacing = settings.spacing,
                .color = settings.color,
                .anchor = settings.anchor,
            }),
            .label = label,
            .len = settings.default_body.len,
            .max_len = settings.max_len,
            .focused = false,
            .last_backspaced = null,
            .backspace_fast = false,
            .anim_bar_len = 0.0,

            // initialize new cursor fields
            .cursor_pos = settings.default_body.len,
            .cursor_last_blink = std.time.milliTimestamp(),
            .cursor_visible = true,
            .till_cursor_cstr = undefined,
        };

        self.inner_text.body = try alloc.alloc(u8, settings.max_len + 1);
        @memset(self.inner_text.body, 0);
        @memcpy(self.inner_text.body[0..settings.default_body.len], settings.default_body);
        return self;
    }

    pub fn deinit(self: *const TextBox, alloc: std.mem.Allocator) void {
        alloc.free(self.inner_text.body);
    }

    pub fn update(self: *TextBox) !void {
        const min_length = 96.0;
        const base_bar_len = @max(min_length, self.inner_text.hitbox.width);

        // draw base underline
        rl.drawRectangleRec(
            .init(
                self.inner_text.hitbox.x,
                self.inner_text.hitbox.y + self.inner_text.hitbox.height - 12.0,
                base_bar_len,
                2.0,
            ),
            .gray,
        );

        // draw anime underline
        self.anim_bar_len = if (self.anim_bar_len + 1 < self.inner_text.hitbox.width)
            self.anim_bar_len + 1.0
        else
            @max(self.anim_bar_len - 1.0, 0.0);
        rl.drawRectangleRec(
            .init(
                self.inner_text.hitbox.x,
                self.inner_text.hitbox.y + self.inner_text.hitbox.height - 12.0,
                self.anim_bar_len,
                2.0,
            ),
            .light_gray,
        );

        if (rl.isMouseButtonPressed(.left)) {
            self.focused = rl.checkCollisionPointRec(rl.getMousePosition(), self.getShadowHitbox());
            // when focusing with mouse, set cursor to end by default
            if (self.focused) self.cursor_pos = self.len;
        }

        if (self.focused) {
            if (rl.isKeyPressed(.right) and self.cursor_pos < self.len) {
                self.cursor_pos += 1;
                // reset blink so caret is visible right after move
                self.cursor_visible = true;
                self.cursor_last_blink = std.time.milliTimestamp();
            }
            if (rl.isKeyPressed(.left) and self.cursor_pos > 0) {
                self.cursor_pos -= 1;
                self.cursor_visible = true;
                self.cursor_last_blink = std.time.milliTimestamp();
            }

            if (rl.isKeyDown(.backspace) and self.len > 0) {
                if (self.last_backspaced) |t| {
                    const now = std.time.milliTimestamp();
                    if (now - t > 500 or self.backspace_fast and now - t > 50) {
                        self.last_backspaced = now;
                        // if cursor is at > 0, remove the char before cursor
                        if (self.cursor_pos > 0) {
                            // shift left from cursor_pos..len-1 into (cursor_pos-1)..
                            for (self.cursor_pos..self.len) |i|
                                self.inner_text.body[i - 1] = self.inner_text.body[i];

                            self.len -= 1;
                            self.cursor_pos -= 1;
                            self.backspace_fast = true;
                        }
                    }
                } else {
                    self.last_backspaced = std.time.milliTimestamp();
                    if (self.cursor_pos > 0) {
                        for (self.cursor_pos..self.len) |i|
                            self.inner_text.body[i - 1] = self.inner_text.body[i];

                        self.len -= 1;
                        self.cursor_pos -= 1;
                    }
                }
            } else {
                // releasing backspace, reset last_backspaced and back_space fast
                self.backspace_fast = false;
                self.last_backspaced = null;

                // --- insert typed characters at cursor (not only at the end) ---
                var key = rl.getCharPressed(); // get char pressed
                while (key != 0) { // loop until all chars processed
                    if (self.len < self.inner_text.body.len - 1) {
                        // shift right from cursor_pos..len-1 into (cursor_pos+1)..
                        var i: usize = self.len;
                        while (i > self.cursor_pos) : (i -= 1) {
                            self.inner_text.body[i] = self.inner_text.body[i - 1];
                        }

                        // insert the key at cursor_pos
                        self.inner_text.body[self.cursor_pos] = @intCast(key);
                        self.len += 1;
                        self.cursor_pos += 1;

                        // reset blink so caret appears immediately
                        self.cursor_visible = true;
                        self.cursor_last_blink = std.time.milliTimestamp();
                    }
                    key = rl.getCharPressed(); // get next char
                }
            }
        } else {
            // if not focused, reset backspace state
            self.backspace_fast = false;
            self.last_backspaced = null;
        }

        self.inner_text.hitbox = self.inner_text.getHitbox(); // update hitbox for current buffer
        self.inner_text.body[self.len] = 0; // sentinel
        self.inner_text.drawBuffer(self.inner_text.body[0..self.len]);

        // caret blinking and drawing
        const now = std.time.milliTimestamp();
        if (now - self.cursor_last_blink > 500) {
            self.cursor_visible = !self.cursor_visible;
            self.cursor_last_blink = now;
        }

        if (self.focused and self.cursor_visible) {
            // measure width of text up to cursor_pos to place caret
            commons.toSentinel(self.inner_text.body[0..self.cursor_pos], &self.till_cursor_cstr);

            const pre_dim = rl.measureTextEx(
                self.inner_text.font,
                &self.till_cursor_cstr,
                @floatFromInt(@intFromEnum(self.inner_text.font_size)),
                self.inner_text.spacing,
            );
            const caret_x = self.inner_text.hitbox.x + pre_dim.x;
            const caret_rect = rl.Rectangle.init(caret_x, self.inner_text.hitbox.y, 2.0, self.inner_text.hitbox.height);
            rl.drawRectangleRec(caret_rect, .white);
        }
    }

    /// Returns biggest possible hitbox given the maximum length and font size
    pub fn getShadowHitbox(self: *TextBox) rl.Rectangle {
        var shadow_hitbox = self.inner_text.getHitbox();
        shadow_hitbox.width = shadow_hitbox.height * @as(f32, @floatFromInt(self.max_len));
        return shadow_hitbox;
    }
};

pub const TextBoxSet = struct {
    boxes: []TextBox,
    labels: []Text,

    pub fn initSpecific(alloc: std.mem.Allocator, boxes: []TextBox) !TextBoxSet {
        const self = TextBoxSet{ .boxes = try alloc.alloc(TextBox, boxes.len) };

        @memcpy(self.boxes, boxes);

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
            padding_between_boxes: f32 = 4.0,
        },
        labels: []const BoxLabel,
    ) !TextBoxSet {
        const self = TextBoxSet{
            .boxes = try alloc.alloc(TextBox, labels.len),
            .labels = try alloc.alloc(Text, labels.len),
        };
        errdefer alloc.free(self.boxes);
        errdefer alloc.free(self.labels);

        var longest_label_x: f32 = 0.0;
        for (labels, 0..) |label, i| {
            self.labels[i] = try Text.init(.{
                .body = label.label,
                .x = settings.top_left_x,
                .y = if (i == 0) // if the first one, just base it on topleft
                    settings.top_left_y
                else // otherwise, base it on location of the last one.
                    self.labels[i - 1].y + self.labels[i - 1].hitbox.height + settings.padding_between_boxes,
                .font_size = settings.font_size,
                .font = settings.font orelse chalk_font,
                .color = settings.text_color,
            });
            longest_label_x = @max(longest_label_x, self.labels[i].hitbox.width);
        }

        for (self.labels, 0..) |label, i| {
            self.boxes[i] = try TextBox.init(alloc, .{
                .x = label.x + longest_label_x + 16.0,
                .y = label.y,
                .font = settings.font,
                .font_size = settings.font_size,
                .max_len = labels[i].max_len,
                .default_body = @constCast(labels[i].default_value),
            });
        }

        return self;
    }

    pub fn deinit(self: *const TextBoxSet, alloc: std.mem.Allocator) void {
        for (self.boxes) |*text_box| text_box.deinit(alloc);

        alloc.free(self.boxes);
        alloc.free(self.labels);
    }

    /// Pass in references to strings. Writes sentinel at the end.
    pub fn update(self: *TextBoxSet, references: []const []u8) !void {
        if (references.len != self.boxes.len) {
            commons.print(
                "Amount of references passed to TextBoxSet.update must equal amount of labels passed in TextBoxSet.init\n",
                .{},
                .red,
            );
            return error.TextBoxSetNotMatching;
        }

        for (self.labels) |*label| label.update();

        for (references, 0..) |ref, i| {
            try self.boxes[i].update();
            const len = self.boxes[i].len;
            if (len > 0 and ref.len > len) {
                @memcpy(ref[0..len], self.boxes[i].inner_text.body[0..len]);
                ref[len] = 0;
            } else if (len == 0) ref[0] = 0;
        }
    }

    pub fn getHitbox(self: *const TextBoxSet) rl.Rectangle {
        return .{
            .x = self.labels[0].x,
            .y = self.labels[0].y,
            .width = self.boxes[0].inner_text.getHitbox().width,
            .height = self.boxes[0].inner_text.getHitbox().height * @as(f32, @floatFromInt(self.boxes.len)),
        };
    }
};
