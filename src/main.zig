const std = @import("std");
const math = std.math;
const assert = std.debug.assert;
const print = std.debug.print;

const zgpu = @import("zgpu");
const zmath = @import("zmath");
const mul = zmath.mul;
const zglfw = @import("zglfw");
const wgpu = zgpu.wgpu;
const zstbi = @import("zstbi");

const window = @import("./window.zig");
const manager = @import("./resources_manager.zig");
const camera = @import("./camera.zig");
const gpu = @import("./gpu.zig");
const input = @import("./input.zig");

const embedded_font_data = @embedFile("./FiraCode-Medium.ttf");
const content_dir = @import("build_options").assets;

// Application state struct
const App = struct {
    window: window.Window,
    resources: manager.Resources,
    gpu: gpu.GlobalState,
    camera: *camera.Camera,
    input_handler: *input.InputEventHandler,

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
        const gpu_state = try gpu.GlobalState.init(allocator, window_state.z_window);

        const cam = try allocator.create(camera.Camera);
        cam.* = camera.Camera.init(
            camera.CameraType{ .ortogonal = camera.OrtogonalCamera.init(5.0) },
            // camera.CameraType{ .perspective = camera.PerspectiveCamera.init(0.500) },
            window_state.ratio(),
            0.01,
            100,
        );

        const input_handler = try allocator.create(input.InputEventHandler);
        input_handler.* = input.InputEventHandler.init(allocator, cam);

        input.init(window_state.z_window, input_handler);
        return App{
            .window = window_state,
            .resources = resources,
            .gpu = gpu_state,
            .camera = cam,
            .input_handler = input_handler,
        };
    }

    // Cleanup
    fn deinit(self: *App, allocator: std.mem.Allocator) void {
        self.input_handler.deinit();
        allocator.destroy(self.input_handler);
        allocator.destroy(self.camera);
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

    // setup buffers
    print("Setup Buffers\n", .{});
    var queue = gctx.device.getQueue();
    var geo_buffer = try gpu.GeometryBuffer.init(gpu_state.ctx.device, &app.resources.geometry);
    defer geo_buffer.release();
    geo_buffer.write_buffers(queue);

    var uniform_data = gpu.Uniforms{
        .projection_matrix = app.camera.projection_matrix,
        .view_matrix = app.camera.view_matrix,
        .time = @floatCast(zglfw.getTime()),
        .color = .{ 0.0, 1.0, 0.4, 1.0 },
    };

    // position camera
    uniform_data.view_matrix = mul(zmath.translation(0.0, 0.0, 2.0), uniform_data.view_matrix);

    print("Start Game Loop\n", .{});
    while (!z_window.shouldClose() and z_window.getKey(.escape) != .press) {
        // poll system and GPU
        zglfw.pollEvents();
        gctx.device.tick();

        // handle input
        app.input_handler.handle_events();

        // update
        uniform_data.time = @floatCast(zglfw.getTime());
        uniform_data.projection_matrix = app.camera.projection_matrix;
        uniform_data.view_matrix = app.camera.view_matrix;
        queue.writeBuffer(
            gpu_state.uniforms.uniform_buffer,
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
                render_pass.setPipeline(app.gpu.pipeline);
                render_pass.setVertexBuffer(
                    0,
                    geo_buffer.point_buffer,
                    0,
                    app.resources.geometry.point_data.items.len * @sizeOf(f32),
                );
                render_pass.setVertexBuffer(
                    1,
                    geo_buffer.color_buffer,
                    0,
                    app.resources.geometry.color_data.items.len * @sizeOf(f32),
                );
                render_pass.setIndexBuffer(
                    geo_buffer.index_buffer,
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
                zgpu.endReleasePass(render_pass);
            }

            break :commands encoder.finish(null);
        };
        defer commands.release();
        gctx.submit(&.{commands});

        const exec_type = gctx.present();
        if (exec_type == .swap_chain_resized) {
            app.window.resize();
            app.camera.resize(app.window.ratio());
            gpu_state.update_depth_texture();
        }
    }
}

fn update_model() zmath.Mat {}
