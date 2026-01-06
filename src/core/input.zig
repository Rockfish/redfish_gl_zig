const std = @import("std");
const zglfw = @import("zglfw");

const EnumSet = std.EnumSet;

pub const Input = struct {
    first_mouse: bool = false,
    mouse_x: f32 = 0.0,
    mouse_y: f32 = 0.0,
    mouse_right_button: bool = false,
    mouse_left_button: bool = false,
    key_presses: EnumSet(zglfw.Key),
    key_processed: EnumSet(zglfw.Key),
    key_shift: bool = false,
    key_alt: bool = false,

    const Self = @This();

    pub fn init(scr_width: f32, scr_height: f32) Self {
        return .{
            .first_mouse = true,
            .mouse_x = scr_width * 0.5,
            .mouse_y = scr_height * 0.5,
            .mouse_right_button = false,
            .mouse_left_button = false,
            .key_presses = EnumSet(zglfw.Key).initEmpty(),
            .key_processed = EnumSet(zglfw.Key).initEmpty(),
            .key_shift = false,
            .key_alt = false,
        };
    }

    pub fn handleKey(self: *Self, key: zglfw.Key, action: zglfw.Action, mods: zglfw.Mods) void {
        switch (action) {
            .press => self.key_presses.insert(key),
            .release => {
                self.key_presses.remove(key);
                self.key_processed.remove(key);
            },
            else => {},
        }

        self.key_shift = mods.shift;
        self.key_alt = mods.alt;
    }
};
