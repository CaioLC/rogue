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
};

fn initWindow() !*zglfw.Window {
    try zglfw.init();
    zglfw.windowHint(.client_api, .no_api);
    const window = try zglfw.createWindow(1200, 800, window_title, null);
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

    return AppState{
        .window = window,
        .gpu = gpu_state,
    };
}

// Cleanup
fn deinitApp(app: *AppState, allocator: std.mem.Allocator) void {
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

    // UPDATE
    const window = app_state.window;
    var gpu_state = app_state.gpu;
    const gctx = gpu_state.ctx;
    const pipeline = app_state.gpu.pipeline;

    var queue = gctx.device.getQueue();
    gpu_state.buffers_manager.write_buffers(queue);
    print("Write Queue initialized\n", .{});

    const focal_len: f32 = 0.5;
    const ratio = gpu_state.window_state.ratio();
    var uniform_data = gpu.Uniforms{
        .projection_matrix = .{
            focal_len, 0.0, 0.0, 0.0,
            0.0, focal_len * ratio, 0.0, 0.0,
            0.0, 0.0, 1.0, 0.0,
            0.0, 0.0, 0.0, 1.0,
        },
        .view_matrix = .{
            1.0, 0.0, 0.0, 0.0,
            0.0, 1.0, 0.0, 0.0,
            0.0, 0.0, 1.0, 0.0,
            0.0, 0.0, 0.0, 1.0,
        },
        .model_matrix = .{
            1.0, 0.0, 0.0, 0.0,
            0.0, 1.0, 0.0, 0.0,
            0.0, 0.0, 1.0, 0.0,
            0.0, 0.0, 0.0, 1.0,
        },
        .time = @floatCast(zglfw.getTime()),
        .color = .{ 0.0, 1.0, 0.4, 1.0 },
    };

    while (!window.shouldClose() and window.getKey(.escape) != .press) {
        zglfw.pollEvents();
        // poll GPU
        gctx.device.tick();

        // update uniforms
        uniform_data.time = @floatCast(zglfw.getTime());

        const uniform_stride = try gpu.stride(
            @sizeOf(gpu.Uniforms),
            gctx.device,
        );
        queue.writeBuffer(
            gpu_state.buffers_manager.uniform_buffer,
            0,
            gpu.Uniforms,
            &.{uniform_data},
        );

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
            const depth_stencil_attachment = wgpu.RenderPassDepthStencilAttachment{
                .view = gpu_state.depth_texture.texture_view,
                .depth_clear_value = 1.0,
                .depth_load_op = .clear,
                .depth_store_op = .store,
                .depth_read_only = .false,
                .stencil_clear_value = 0,
                .stencil_read_only = .true,
            };

            const render_pass_desc = wgpu.RenderPassDescriptor{
                .color_attachment_count = 1,
                .color_attachments = render_pass_color_attachment,
                // .depth_stencil_attachment = null,
                .depth_stencil_attachment = &depth_stencil_attachment,
                .timestamp_writes = null,
            };

            // GUI pass
            {
                const render_pass = encoder.beginRenderPass(render_pass_desc);
                render_pass.setPipeline(pipeline);
                render_pass.setVertexBuffer(
                    0,
                    gpu_state.buffers_manager.point_buffer,
                    0,
                    gpu_state.buffers_manager.point_data.items.len * @sizeOf(f32),
                );
                render_pass.setVertexBuffer(
                    1,
                    gpu_state.buffers_manager.color_buffer,
                    0,
                    gpu_state.buffers_manager.color_data.items.len * @sizeOf(f32),
                );
                render_pass.setIndexBuffer(
                    gpu_state.buffers_manager.index_buffer,
                    wgpu.IndexFormat.uint16,
                    0,
                    gpu_state.buffers_manager.index_data.items.len * @sizeOf(u16),
                );
                render_pass.setBindGroup(
                    0,
                    gpu_state.bindings.uniforms_bind_group,
                    &[_]u32{0.0},
                );
                render_pass.drawIndexed(
                    gpu_state.buffers_manager.index_count(),
                    1,
                    0,
                    0,
                    0,
                );
                render_pass.setBindGroup(
                    0,
                    gpu_state.bindings.uniforms_bind_group,
                    &[_]u32{uniform_stride},
                );
                render_pass.drawIndexed(
                    gpu_state.buffers_manager.index_count(),
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

        const exec_type = gctx.present();
        if (exec_type == .swap_chain_resized) {
            gpu_state.update_depth_texture(window);
            // TODO: update projection matrix ratio
        }
    }
}
