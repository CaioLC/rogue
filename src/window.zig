const std = @import("std");
const zglfw = @import("zglfw");

const window_title = "zig-gamedev: test windows";

pub const Window = struct {
    z_window: *zglfw.Window,
    width: u32,
    height: u32,

    pub fn ratio(self: Window) f32 {
        const w: f32 = @floatFromInt(self.width);
        const h: f32 = @floatFromInt(self.height);
        return w / h;
    }

    pub fn init() !Window {
        const z_window = try initWindow();
        const size = z_window.getSize();
        return .{
            .z_window = z_window,
            .width = @intCast(size[0]),
            .height = @intCast(size[1]),
        };
    }

    pub fn deinit(_: Window) void {
        zglfw.terminate();
    }

    pub fn update(self: *Window) void {
        const size = self.z_window.getSize();
        self.width = @intCast(size[0]);
        self.height = @intCast(size[1]);
    }

    fn initWindow() !*zglfw.Window {
        try zglfw.init();
        zglfw.windowHint(.client_api, .no_api);
        const window = try zglfw.createWindow(1200, 800, window_title, null);
        window.setSizeLimits(400, 400, -1, -1);
        return window;
    }
};
