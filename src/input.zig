const std = @import("std");
const zglfw = @import("zglfw");
const camera = @import("./camera.zig");

const InputEventsTag = enum {
    mouse_scroll_y,
    key_pressed,
};
const InputEvent = union(InputEventsTag) {
    mouse_scroll_y: f64,
    key_pressed: zglfw.Key,
};

pub const InputEventHandler = struct {
    input_events: std.ArrayList(InputEvent),
    camera: *camera.Camera,

    pub fn init(allocator: std.mem.Allocator, cam: *camera.Camera) InputEventHandler {
        return .{ .input_events = std.ArrayList(InputEvent).init(allocator), .camera = cam };
    }

    pub fn deinit(self: *InputEventHandler) void {
        self.input_events.deinit();
    }

    pub fn handle_events(self: *InputEventHandler) void {
        for (self.input_events.items) |item| {
            switch (item) {
                .mouse_scroll_y => {
                    self.camera.zoom(@floatCast(item.mouse_scroll_y));
                    std.debug.print("mouse scroll event: {}\n", .{item.mouse_scroll_y});
                },
                .key_pressed => {
                    const key = item.key_pressed;
                    if (key == zglfw.Key.d) {
                        self.camera.move_x(1.0);
                    }
                    if (key == zglfw.Key.a) {
                        self.camera.move_x(-1.0);
                    }
                    if (key == zglfw.Key.w) {
                        self.camera.move_y(1.0);
                    }
                    if (key == zglfw.Key.s) {
                        self.camera.move_y(-1.0);
                    }
                }
            }
        }
        self.input_events.clearAndFree();
    }
};

pub fn init(window: *zglfw.Window, event_handler: *InputEventHandler) void {
    // store the pointer to the input event handler
    zglfw.Window.setUserPointer(window, event_handler);
    // keyboard input
    _ = zglfw.setKeyCallback(window, &key_callback);
    // cursor
    _ = zglfw.setCursorPosCallback(window, &cursor_callback);
    _ = zglfw.setMouseButtonCallback(window, &mouse_button_callback);
    _ = zglfw.setScrollCallback(window, &scroll_callback);
}

// input
// pub const KeyFn = *const fn (*Window, Key, scancode: c_int, Action, Mods) callconv(.C) void;
fn key_callback(window: *zglfw.Window, key: zglfw.Key, _: c_int, action: zglfw.Action, _: zglfw.Mods) callconv(.C) void {
    const event_handler = zglfw.Window.getUserPointer(window, InputEventHandler);
    if (event_handler) |input| {
        if (action == zglfw.Action.press) {
            std.debug.print("Send press key event: {}\n", .{key});
            input.input_events.append(InputEvent{ .key_pressed = key }) catch |err| {
                std.debug.print("Append Event failed: {}", .{err});
            };
        }
    } else {
        std.debug.print("Key Event: {} {}\n", .{ key, action });
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
    window: *zglfw.Window,
    xoffset: f64,
    yoffset: f64,
) callconv(.C) void {
    const event_handler = zglfw.Window.getUserPointer(window, InputEventHandler);
    if (event_handler) |input| {
        std.debug.print("Send Offset: {}\n", .{yoffset});
        input.input_events.append(InputEvent{ .mouse_scroll_y = yoffset }) catch |err| {
            std.debug.print("Append Event failed: {}", .{err});
        };
    } else {
        std.debug.print("scrolling: X: {} | Y: {}", .{ xoffset, yoffset });
    }
}
