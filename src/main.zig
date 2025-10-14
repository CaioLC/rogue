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
    const gctx = app_state.gpu.ctx;
    const pipeline = app_state.gpu.pipeline;

    // initialize buffers
    const geometry = content_dir[0..content_dir.len] ++ "geometry";
    var buffers_manager = try gpu.BuffersManager.init(
        gpa,
        gctx.device,
        geometry,
    );
    defer buffers_manager.release();

    // initialize bind_groups
    const bindings = gpu.Bindings.init(
        app_state.gpu,
        buffers_manager.uniform_buffer,
    );

    var queue = gctx.device.getQueue();
    buffers_manager.write_buffers(queue);
    print("Write Queue initialized\n", .{});

    // initialize z-buffer
    const window_size = app_state.window.getSize();
    const depth_texture_format = wgpu.TextureFormat.depth24_plus;
    const depth_texture_desc = wgpu.TextureDescriptor{
        .dimension = wgpu.TextureDimension.tdim_2d,
        .format = depth_texture_format,
        .mip_level_count = 1,
        .sample_count = 1,
        // .size = .{ 1882, 2260, 1 },
        .size = wgpu.Extent3D{
            .width = @intCast(window_size[0]),
            .height = @intCast(window_size[1]),
            .depth_or_array_layers = 1,
        },
        .usage = .{ .render_attachment = true },
        .view_format_count = 1,
        .view_formats = &[_]wgpu.TextureFormat{
            depth_texture_format,
        },
    };
    var depth_texture = gctx.device.createTexture(depth_texture_desc);
    defer depth_texture.release();
    defer depth_texture.destroy();

    const depth_texture_view_desc = wgpu.TextureViewDescriptor{
        .aspect = .depth_only,
        .base_array_layer = 0,
        .array_layer_count = 1,
        .base_mip_level = 0,
        .mip_level_count = 1,
        .dimension = .tvdim_2d,
        .format = depth_texture_format,
    };
    var depth_texture_view = depth_texture.createView(depth_texture_view_desc);
    defer depth_texture_view.release();

    while (!window.shouldClose() and window.getKey(.escape) != .press) {
        zglfw.pollEvents();
        // poll GPU
        gctx.device.tick();

        // update uniforms
        const uniform_data = gpu.Uniforms{
            .time = @floatCast(zglfw.getTime()),
            .color = .{ 0.0, 1.0, 0.4, 1.0 },
        };
        const uniform_stride = try gpu.stride(
            @sizeOf(gpu.Uniforms),
            gctx.device,
        );
        queue.writeBuffer(
            buffers_manager.uniform_buffer,
            0,
            gpu.Uniforms,
            &.{uniform_data},
        );

        // uniform_data.time = -1.0;
        // uniform_data.color = .{ 1.0, 1.0, 1.0, 0.7 };
        // queue.writeBuffer(
        //     buffers_manager.uniform_buffer,
        //     uniform_stride,
        //     gpu.Uniforms,
        //     &.{uniform_data},
        // );
        //
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
                .view = depth_texture_view,
                .depth_clear_value = 1.0,
                .depth_load_op = .clear,
                .depth_store_op = .store,
                .depth_read_only = .false,
                .stencil_clear_value = 0,
                // .stencil_load_op = .clear,
                // .stencil_store_op = .store,
                .stencil_read_only = .true,
            };

            const render_pass_desc = wgpu.RenderPassDescriptor{
                .color_attachment_count = 1,
                .color_attachments = render_pass_color_attachment,
                .depth_stencil_attachment = &depth_stencil_attachment,
                .timestamp_writes = null,
            };

            // GUI pass
            {
                const render_pass = encoder.beginRenderPass(render_pass_desc);
                render_pass.setPipeline(pipeline);
                render_pass.setVertexBuffer(
                    0,
                    buffers_manager.point_buffer,
                    0,
                    buffers_manager.point_data.items.len * @sizeOf(f32),
                );
                render_pass.setVertexBuffer(
                    1,
                    buffers_manager.color_buffer,
                    0,
                    buffers_manager.color_data.items.len * @sizeOf(f32),
                );
                render_pass.setIndexBuffer(
                    buffers_manager.index_buffer,
                    wgpu.IndexFormat.uint16,
                    0,
                    buffers_manager.index_data.items.len * @sizeOf(u16),
                );
                render_pass.setBindGroup(
                    0,
                    bindings.uniforms_bind_group,
                    &[_]u32{0.0},
                );
                render_pass.drawIndexed(
                    buffers_manager.index_count(),
                    1,
                    0,
                    0,
                    0,
                );
                render_pass.setBindGroup(
                    0,
                    bindings.uniforms_bind_group,
                    &[_]u32{uniform_stride},
                );
                render_pass.drawIndexed(
                    buffers_manager.index_count(),
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
