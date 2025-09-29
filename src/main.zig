const std = @import("std");
const math = std.math;
const assert = std.debug.assert;
const print = std.debug.print;
const content_dir = @import("build_options").assets;

const zglfw = @import("zglfw");
const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;
const zmath = @import("zmath");
const zstbi = @import("zstbi");

const manager = @import("./resources_manager.zig");
const gpu = @import("./gpu.zig");

const window_title = "zig-gamedev: test windows";
const embedded_font_data = @embedFile("./FiraCode-Medium.ttf");

// Application state struct
const AppState = struct {
    window: *zglfw.Window,
    gpu: gpu.GlobalState,
    point_data: std.ArrayList(f32),
    color_data: std.ArrayList(f32),
    index_data: std.ArrayList(u16),
};

fn initWindow() !*zglfw.Window {
    try zglfw.init();
    zglfw.windowHint(.client_api, .no_api);
    const window = try zglfw.createWindow(800, 500, window_title, null);
    window.setSizeLimits(400, 400, -1, -1);
    return window;
}

fn initApp(allocator: std.mem.Allocator) !AppState {
    // change current working directory to where the executable is located.
    {
        var buffer: [1024]u8 = undefined;
        const path = std.fs.selfExeDirPath(buffer[0..]) catch ".";
        std.debug.print("{s}", .{path});
        std.posix.chdir(path) catch {};
    }

    const window = try initWindow();
    const gpu_state = try gpu.GlobalState.init(allocator, window);

    var point_data = std.ArrayList(f32).init(allocator);
    errdefer point_data.deinit();
    var color_data = std.ArrayList(f32).init(allocator);
    errdefer color_data.deinit();
    var index_data = std.ArrayList(u16).init(allocator);
    errdefer index_data.deinit();
    try manager.loadGeometry(
        allocator,
        content_dir[0..content_dir.len] ++ "geometry",
        &point_data,
        &color_data,
        &index_data,
    );

    return AppState{
        .window = window,
        .gpu = gpu_state,
        .point_data = point_data,
        .color_data = color_data,
        .index_data = index_data,
    };
}

// Cleanup
fn deinitApp(app: *AppState, allocator: std.mem.Allocator) void {
    app.point_data.deinit();
    app.color_data.deinit();
    app.index_data.deinit();
    app.gpu.release(allocator);
    zglfw.terminate();
}

pub fn main() !void {
    // SETUP
    // allocator
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    // state
    var app_state = try initApp(gpa);
    print("AppState initialized\n", .{});
    defer deinitApp(&app_state, gpa);

    // set buffers
    // points buffer
    const point_buffer = gpu.create_buffer(
        app_state.gpu.ctx.device,
        "Vertex Position Buffer",
        wgpu.BufferUsage{ .copy_dst = true, .vertex = true },
        app_state.point_data.items.len * @sizeOf(f32),
        wgpu.U32Bool.false,
    );
    defer point_buffer.release();

    // color buffer
    const color_buffer = gpu.create_buffer(
        app_state.gpu.ctx.device,
        "Vertex Color Buffer",
        wgpu.BufferUsage{ .copy_dst = true, .vertex = true },
        app_state.color_data.items.len * @sizeOf(f32),
        wgpu.U32Bool.false,
    );
    defer color_buffer.release();

    // idx buffer
    const index_count: u32 = @intCast(app_state.index_data.items.len);
    const index_buffer = gpu.create_buffer(
        app_state.gpu.ctx.device,
        "Index Buffer",
        wgpu.BufferUsage{ .copy_dst = true, .index = true },
        app_state.index_data.items.len * @sizeOf(u16),
        wgpu.U32Bool.false,
    );
    defer index_buffer.release();

    // unifom buffer
    const uniform_buffer = gpu.create_buffer(
        app_state.gpu.ctx.device,
        "Time Uniform Buffer",
        wgpu.BufferUsage{ .copy_dst = true, .uniform = true },
        4 * @sizeOf(f32),
        wgpu.U32Bool.false,
    );
    defer uniform_buffer.release();
    print("BufState initialized\n", .{});

    // UPDATE
    const window = app_state.window;
    const gctx = app_state.gpu.ctx;
    const pipeline = app_state.gpu.pipeline;

    var queue = gctx.device.getQueue();
    const current_time: f32 = 1.0;
    queue.writeBuffer(point_buffer, 0, f32, app_state.point_data.items);
    queue.writeBuffer(color_buffer, 0, f32, app_state.color_data.items);
    queue.writeBuffer(index_buffer, 0, u16, app_state.index_data.items);
    queue.writeBuffer(uniform_buffer, 0, f32, &.{current_time});
    print("Write Queue initialized\n", .{});

    while (!window.shouldClose() and window.getKey(.escape) != .press) {
        zglfw.pollEvents();
        // poll GPU
        gctx.device.tick();

        // render things
        const swapchain_texv = gctx.swapchain.getCurrentTextureView();
        defer swapchain_texv.release();

        const commands = commands: {
            const encoder = gctx.device.createCommandEncoder(null);
            defer encoder.release();

            const render_pass_color_attachment = &[_]wgpu.RenderPassColorAttachment{
                .{
                    .view = swapchain_texv,
                    .resolve_target = null,
                    .load_op = wgpu.LoadOp.clear,
                    .store_op = wgpu.StoreOp.store,
                    .clear_value = wgpu.Color{
                        .r = 0.9,
                        .g = 0.9,
                        .b = 0.9,
                        .a = 1.0,
                    },
                },
            };
            const render_pass_desc = wgpu.RenderPassDescriptor{
                .color_attachment_count = 1,
                .color_attachments = render_pass_color_attachment,
                .depth_stencil_attachment = null,
                .timestamp_writes = null,
            };

            // GUI pass
            {
                const render_pass = encoder.beginRenderPass(render_pass_desc);
                render_pass.setPipeline(pipeline);
                render_pass.setVertexBuffer(
                    0,
                    point_buffer,
                    0,
                    app_state.point_data.items.len * @sizeOf(f32),
                );
                render_pass.setVertexBuffer(
                    1,
                    color_buffer,
                    0,
                    app_state.color_data.items.len * @sizeOf(f32),
                );
                render_pass.setIndexBuffer(
                    index_buffer,
                    wgpu.IndexFormat.uint16,
                    0,
                    app_state.index_data.items.len * @sizeOf(u16),
                );
                render_pass.drawIndexed(
                    index_count,
                    1,
                    0,
                    0,
                    0,
                );
                defer zgpu.endReleasePass(render_pass);
            }

            break :commands encoder.finish(null);
        };
        defer commands.release();
        gctx.submit(&.{commands});
        _ = gctx.present();
    }
}
