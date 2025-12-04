const std = @import("std");
const zglfw = @import("zglfw");

pub fn init(window: *zglfw.Window) void {
    // keyboard input
    _ = zglfw.setKeyCallback(window, &key_callback);
    // cursor
    _ = zglfw.setCursorPosCallback(window, &cursor_callback);
    _ = zglfw.setMouseButtonCallback(window, &mouse_button_callback);
    _ = zglfw.setScrollCallback(window, &scroll_callback);
}

// input
// pub const KeyFn = *const fn (*Window, Key, scancode: c_int, Action, Mods) callconv(.C) void;
fn key_callback(_: *zglfw.Window, key: zglfw.Key, _: c_int, action: zglfw.Action, _: zglfw.Mods) callconv(.C) void {
    if (key == zglfw.Key.e and action == zglfw.Action.press) {
        std.debug.print("Key E pressed!\n", .{});
    }
}

fn cursor_callback(
    _: *zglfw.Window,
    _: f64,
    _: f64,
) callconv(.C) void {
    // std.debug.print("Cursor position: X: {} | Y: {}", .{ xpos, ypos });
}

fn mouse_button_callback(
    _: *zglfw.Window,
    button: zglfw.MouseButton,
    action: zglfw.Action,
    _: zglfw.Mods,
) callconv(.C) void {
    if (button == zglfw.MouseButton.left and action == zglfw.Action.press) {
        std.debug.print("Mouse-left pressed!\n", .{});
    }
}

fn scroll_callback(
    _: *zglfw.Window,
    xoffset: f64,
    yoffset: f64,
) callconv(.C) void {
    std.debug.print("scrolling: X: {} | Y: {}", .{ xoffset, yoffset });
}
