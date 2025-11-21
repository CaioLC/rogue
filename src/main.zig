const std = @import("std");
const math = std.math;
const assert = std.debug.assert;
const print = std.debug.print;
const content_dir = @import("build_options").assets;

const zgpu = @import("zgpu");
const zglfw = @import("zglfw");
const wgpu = zgpu.wgpu;
const zstbi = @import("zstbi");

const window = @import("./window.zig");
const manager = @import("./resources_manager.zig");
const camera = @import("./camera.zig");
const gpu = @import("./gpu.zig");

const embedded_font_data = @embedFile("./FiraCode-Medium.ttf");

// Application state struct
const AppState = struct {
    window: window.Window,
    resources: manager.Resources,
    gpu: gpu.GlobalState,
    camera: camera.Camera,

    fn init(allocator: std.mem.Allocator) !AppState {
        // change current working directory to where the executable is located.
        {
            var buffer: [1024]u8 = undefined;
            const path = std.fs.selfExeDirPath(buffer[0..]) catch ".";
            std.debug.print("{s}", .{path});
            std.posix.chdir(path) catch {};
        }

        const window_state = try window.Window.init();
        const resources = try manager.Resources.load(allocator, content_dir);
        const gpu_state = try gpu.GlobalState.init(allocator, window_state.z_window, resources.geometry);
        const cam = camera.Camera.init(
            camera.CameraType{ .ortogonal = camera.OrtogonalCamera{ .scale = 2.0 } },
            window_state.ratio(),
            0.001,
            100,
        );
        return AppState{
            .window = window_state,
            .resources = resources,
            .gpu = gpu_state,
            .camera = cam,
        };
    }

    // Cleanup
    fn deinit(self: *AppState, allocator: std.mem.Allocator) void {
        self.gpu.release(allocator);
        self.resources.deinit();
        self.window.deinit();
    }
};

pub fn main() !void {
    // SETUP
    // allocator
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    // state
    var app_state = try AppState.init(gpa);
    print("AppState initialized\n", .{});
    defer app_state.deinit(gpa);

    // UPDATE
    const z_window = app_state.window.z_window;
    var gpu_state = app_state.gpu;
    const gctx = gpu_state.ctx;
    const pipeline = app_state.gpu.pipeline;

    var queue = gctx.device.getQueue();
    gpu_state.buffers_manager.write_buffers(queue, app_state.resources.geometry);
    print("Write Queue initialized\n", .{});

    var uniform_data = gpu.Uniforms{
        .projection_matrix = app_state.camera.projection_matrix,
        .view_matrix = app_state.camera.view_matrix,
        .model_matrix = app_state.camera.model_matrix,
        .time = @floatCast(zglfw.getTime()),
        .color = .{ 0.0, 1.0, 0.4, 1.0 },
    };

    while (!z_window.shouldClose() and z_window.getKey(.escape) != .press) {
        zglfw.pollEvents();
        // poll GPU
        gctx.device.tick();

        // update uniforms
        uniform_data.time = @floatCast(zglfw.getTime());
        uniform_data.projection_matrix = app_state.camera.projection_matrix;
        // const uniform_stride = try gpu.stride(
        //     @sizeOf(gpu.Uniforms),
        //     gctx.device,
        // );
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
                    app_state.resources.geometry.point_data.items.len * @sizeOf(f32),
                );
                render_pass.setVertexBuffer(
                    1,
                    gpu_state.buffers_manager.color_buffer,
                    0,
                    app_state.resources.geometry.color_data.items.len * @sizeOf(f32),
                );
                render_pass.setIndexBuffer(
                    gpu_state.buffers_manager.index_buffer,
                    wgpu.IndexFormat.uint16,
                    0,
                    app_state.resources.geometry.index_data.items.len * @sizeOf(u16),
                );
                render_pass.setBindGroup(
                    0,
                    gpu_state.bindings.uniforms_bind_group,
                    &[_]u32{0.0},
                );
                render_pass.drawIndexed(
                    @intCast(app_state.resources.geometry.index_data.items.len),
                    1,
                    0,
                    0,
                    0,
                );
                // render_pass.setBindGroup(
                //     0,
                //     gpu_state.bindings.uniforms_bind_group,
                //     &[_]u32{uniform_stride},
                // );
                // render_pass.drawIndexed(
                //     @intCast(app_state.resources.geometry.index_data.items.len),
                //     1,
                //     0,
                //     0,
                //     0,
                // );
                defer zgpu.endReleasePass(render_pass);
            }

            break :commands encoder.finish(null);
        };
        defer commands.release();
        gctx.submit(&.{commands});

        const exec_type = gctx.present();
        if (exec_type == .swap_chain_resized) {
            app_state.window.update();
            app_state.camera.update(app_state.window.ratio());
            gpu_state.update_depth_texture();
        }
    }
}
