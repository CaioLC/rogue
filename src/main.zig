const std = @import("std");
const math = std.math;
const assert = std.debug.assert;
const rogue = @import("rogue");
const zglfw = @import("zglfw");
const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;
const zstbi = @import("zstbi");

const content_dir = @import("build_options").assets;
const window_title = "zig-gamedev: test windows";
const embedded_font_data = @embedFile("./FiraCode-Medium.ttf");

const shader_source =
    \\ @vertex
    \\fn vs_main(@location(0) in_vertex_position: vec2f) -> @builtin(position) vec4f {
    \\    return vec4f(in_vertex_position, 0.0, 1.0);
    \\}
    \\
    \\@fragment
    \\fn fs_main() -> @location(0) vec4f {
    \\    return vec4f(0.0, 0.4, 1.0, 1.0);
    \\}
;

// Application state struct
const AppState = struct {
    window: *zglfw.Window,
    gctx: *zgpu.GraphicsContext,
    pipeline: wgpu.RenderPipeline,
};

const BufferCtx = struct { ready: bool, buffer: wgpu.Buffer };

fn initWindow() !*zglfw.Window {
    try zglfw.init();
    zglfw.windowHint(.client_api, .no_api);
    const window = try zglfw.createWindow(800, 500, window_title, null);
    window.setSizeLimits(400, 400, -1, -1);
    return window;
}

fn initGraphicsContext(allocator: std.mem.Allocator, window: *zglfw.Window) !*zgpu.GraphicsContext {
    return try zgpu.GraphicsContext.create(
        allocator,
        .{
            .window = window,
            .fn_getTime = @ptrCast(&zglfw.getTime),
            .fn_getFramebufferSize = @ptrCast(&zglfw.Window.getFramebufferSize),
            .fn_getWin32Window = @ptrCast(&zglfw.getWin32Window),
            .fn_getX11Display = @ptrCast(&zglfw.getX11Display),
            .fn_getX11Window = @ptrCast(&zglfw.getX11Window),
            .fn_getWaylandDisplay = @ptrCast(&zglfw.getWaylandDisplay),
            .fn_getWaylandSurface = @ptrCast(&zglfw.getWaylandWindow),
            .fn_getCocoaWindow = @ptrCast(&zglfw.getCocoaWindow),
        },
        .{},
    );
}

fn createRenderPipeline(gctx: *zgpu.GraphicsContext) !wgpu.RenderPipeline {
    const shader_code_desc = wgpu.ShaderModuleWGSLDescriptor{
        .chain = .{
            .next = null,
            .struct_type = wgpu.StructType.shader_module_wgsl_descriptor,
        },
        .code = shader_source,
    };
    const shader_module = gctx.device.createShaderModule(
        .{ .next_in_chain = &shader_code_desc.chain },
    );
    defer shader_module.release();

    const color_blend = wgpu.BlendState{
        .color = .{
            .operation = wgpu.BlendOperation.add,
            .src_factor = wgpu.BlendFactor.src_alpha,
            .dst_factor = wgpu.BlendFactor.one_minus_src_alpha,
        },
        .alpha = .{
            .operation = wgpu.BlendOperation.add,
            .src_factor = wgpu.BlendFactor.zero,
            .dst_factor = wgpu.BlendFactor.one,
        },
    };
    const color_target = &[_]wgpu.ColorTargetState{
        .{
            .format = gctx.swapchain_descriptor.format,
            .blend = &color_blend,
            .write_mask = wgpu.ColorWriteMask.all,
            .next_in_chain = null,
        },
    };
    const frag_state = wgpu.FragmentState{
        .module = shader_module,
        .entry_point = "fs_main",
        .constant_count = 0,
        .constants = null,
        .target_count = 1,
        .targets = color_target,
    };

    const pipeline_desc = wgpu.RenderPipelineDescriptor{
        .vertex = .{
            .buffer_count = 0,
            .buffers = null,
            .module = shader_module,
            .entry_point = "vs_main",
            .constant_count = 0,
            .constants = null,
        },
        .primitive = .{
            .topology = wgpu.PrimitiveTopology.triangle_list,
            .strip_index_format = wgpu.IndexFormat.undef,
            .front_face = wgpu.FrontFace.ccw,
            .cull_mode = wgpu.CullMode.none, // TODO: set to front, once bugs are cleared
        },
        .fragment = &frag_state,
        .depth_stencil = null,
        .multisample = .{
            .count = 1,
            .mask = 0xffff_ffff, // ~0u in the original
            .alpha_to_coverage_enabled = false,
        },
        .layout = null,
    };

    return gctx.device.createRenderPipeline(pipeline_desc);
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
    const gctx = try initGraphicsContext(allocator, window);
    const pipeline = try createRenderPipeline(gctx);

    return AppState{
        .window = window,
        .gctx = gctx,
        .pipeline = pipeline,
    };
}

// Cleanup
fn deinitApp(app: *AppState, allocator: std.mem.Allocator) void {
    app.pipeline.release();
    app.gctx.destroy(allocator);
    zglfw.terminate();
}

fn bufferMapCallback(
    status: wgpu.BufferMapAsyncStatus,
    userdata: ?*anyopaque,
) callconv(.C) void {
    const ctx: *BufferCtx = @alignCast(@ptrCast(userdata));
    ctx.ready = true;
    std.debug.print("{}\n", .{status});

    const buffer_data = ctx.buffer.getConstMappedRange(u8, 0, 16).?;
    for (buffer_data) |value| {
        std.debug.print("{}\n", .{value});
    }
    ctx.buffer.unmap();
}

pub fn wgpuPollEvents(device: wgpu.Device) void {
    device.tick();
}

pub fn main() !void {
    // SETUP
    // allocator
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    // state
    var app_state = try initApp(gpa);
    defer deinitApp(&app_state, gpa);

    // UPDATE
    const window = app_state.window;
    const gctx = app_state.gctx;
    const pipeline = app_state.pipeline;

    var buf_desc = wgpu.BufferDescriptor{
        .label = "Some data buffer",
        .usage = wgpu.BufferUsage{ .copy_dst = true, .copy_src = true },
        .size = 16,
        .mapped_at_creation = wgpu.U32Bool.false,
    };
    const buffer1 = gctx.device.createBuffer(buf_desc);
    defer buffer1.release();

    buf_desc.label = "Output buffer";
    buf_desc.usage = wgpu.BufferUsage{ .copy_dst = true, .map_read = true };
    const buffer2 = gctx.device.createBuffer(buf_desc);
    defer buffer2.release();

    var queue = gctx.device.getQueue();
    const data = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 };
    queue.writeBuffer(buffer1, 0, u8, &data);

    while (!window.shouldClose() and window.getKey(.escape) != .press) {
        zglfw.pollEvents();
        //
        // poll GPU
        gctx.device.tick();
        // render things
        const swapchain_texv = gctx.swapchain.getCurrentTextureView();
        defer swapchain_texv.release();

        const commands = commands: {
            const encoder = gctx.device.createCommandEncoder(null);
            defer encoder.release();
            encoder.copyBufferToBuffer(buffer1, 0, buffer2, 0, 16);

            const render_pass_color_attachment = &[_]wgpu.RenderPassColorAttachment{
                .{
                    .view = swapchain_texv,
                    .resolve_target = null,
                    .load_op = wgpu.LoadOp.clear,
                    .store_op = wgpu.StoreOp.store,
                    .clear_value = wgpu.Color{
                        .r = 0.9,
                        .g = 0.1,
                        .b = 0.2,
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
                render_pass.draw(3, 1, 0, 0);
                defer zgpu.endReleasePass(render_pass);
            }

            break :commands encoder.finish(null);
        };
        defer commands.release();
        gctx.submit(&.{commands});
        _ = gctx.present();

        var buffer_ctx = BufferCtx{ .ready = false, .buffer = buffer2 };
        buffer2.mapAsync(
            wgpu.MapMode{ .read = true },
            0,
            16,
            bufferMapCallback,
            &buffer_ctx,
        );

        while (!buffer_ctx.ready) {
            wgpuPollEvents(gctx.device);
        }
    }
}
