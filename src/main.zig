const std = @import("std");
const math = std.math;
const assert = std.debug.assert;
const print = std.debug.print;
const content_dir = @import("build_options").assets;

const zgpu = @import("zgpu");
const zmath = @import("zmath");
const zglfw = @import("zglfw");
const wgpu = zgpu.wgpu;
const zstbi = @import("zstbi");

const window = @import("./window.zig");
const manager = @import("./resources_manager.zig");
const camera = @import("./camera.zig");
const gpu = @import("./gpu.zig");

const embedded_font_data = @embedFile("./FiraCode-Medium.ttf");

// Application state struct
const App = struct {
    window: window.Window,
    resources: manager.Resources,
    gpu: gpu.GlobalState,
    camera: camera.Camera,

    fn init(allocator: std.mem.Allocator) !App {
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
            camera.CameraType{ .ortogonal = camera.OrtogonalCamera.init(1.0) },
            // camera.CameraType{ .perspective = camera.PerspectiveCamera.init(9.9) },
            window_state.ratio(),
            -100,
            10000,
        );
        return App{
            .window = window_state,
            .resources = resources,
            .gpu = gpu_state,
            .camera = cam,
        };
    }

    // Cleanup
    fn deinit(self: *App, allocator: std.mem.Allocator) void {
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
    var app = try App.init(gpa);
    print("AppState initialized\n", .{});
    defer app.deinit(gpa);

    // UPDATE
    const z_window = app.window.z_window;
    var gpu_state = app.gpu;
    const gctx = gpu_state.ctx;
    const pipeline = app.gpu.pipeline;

    var queue = gctx.device.getQueue();
    gpu_state.buffers_manager.write_buffers(queue, app.resources.geometry);
    print("Write Queue initialized\n", .{});

    var uniform_data = gpu.Uniforms{
        .projection_matrix = app.camera.projection_matrix,
        .view_matrix = app.camera.view_matrix,
        .model_matrix = app.camera.model_matrix,
        .time = @floatCast(zglfw.getTime()),
        .color = .{ 0.0, 1.0, 0.4, 1.0 },
    };

    // rotate world view
    std.debug.print("UNIFORM DATA: {}", .{uniform_data});
    const S = zmath.scaling(0.5, 0.5, 0.5);
    const R1 = zmath.rotationX(-3.0 * 3.14 / 4.0);
    const M = zmath.mul(R1, S);
    uniform_data.model_matrix = zmath.mul(uniform_data.model_matrix, M);

    while (!z_window.shouldClose() and z_window.getKey(.escape) != .press) {
        zglfw.pollEvents();
        // poll GPU
        gctx.device.tick();

        // update uniforms
        uniform_data.time = @floatCast(zglfw.getTime());
        uniform_data.projection_matrix = app.camera.projection_matrix;
        const T = zmath.translation(0.05, 0.0, 0.0);
        const R2 = zmath.rotationZ(-0.05);
        const M2 = zmath.mul(R2, T);
        uniform_data.model_matrix = zmath.mul(M2, uniform_data.model_matrix);
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
                    app.resources.geometry.point_data.items.len * @sizeOf(f32),
                );
                render_pass.setVertexBuffer(
                    1,
                    gpu_state.buffers_manager.color_buffer,
                    0,
                    app.resources.geometry.color_data.items.len * @sizeOf(f32),
                );
                render_pass.setIndexBuffer(
                    gpu_state.buffers_manager.index_buffer,
                    wgpu.IndexFormat.uint16,
                    0,
                    app.resources.geometry.index_data.items.len * @sizeOf(u16),
                );
                render_pass.setBindGroup(
                    0,
                    gpu_state.bindings.uniforms_bind_group,
                    &[_]u32{0.0},
                );
                render_pass.drawIndexed(
                    @intCast(app.resources.geometry.index_data.items.len),
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
            app.window.update();
            app.camera.update(app.window.ratio());
            gpu_state.update_depth_texture();
        }
    }
}
