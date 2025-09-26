const std = @import("std");
const math = std.math;
const assert = std.debug.assert;
const zglfw = @import("zglfw");
const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;
const zstbi = @import("zstbi");
const zmath = @import("zmath");

const print = std.debug.print;

const manager = @import("./resources_manager.zig");

const content_dir = @import("build_options").assets;
const window_title = "zig-gamedev: test windows";
const embedded_font_data = @embedFile("./FiraCode-Medium.ttf");

// Application state struct
const AppState = struct {
    window: *zglfw.Window,
    gctx: *zgpu.GraphicsContext,
    pipeline: wgpu.RenderPipeline,
    point_data: std.ArrayList(f32),
    color_data: std.ArrayList(f32),
    index_data: std.ArrayList(u16),
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
    const required_limits = wgpu.RequiredLimits{
        .limits = .{
            .max_vertex_attributes = 1,
            .max_vertex_buffers = 2,
            .max_inter_stage_shader_components = 3,
        },
    };
    const options = zgpu.GraphicsContextOptions{
        .required_limits = &required_limits,
    };
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
        options,
    );
}

fn createVertexState(shader_module: wgpu.ShaderModule) wgpu.VertexState {
    const pos_attr = wgpu.VertexAttribute{
        .shader_location = 0,
        .format = wgpu.VertexFormat.float32x4,
        .offset = 0,
    };
    const pos_buffer_layout = wgpu.VertexBufferLayout{
        .attribute_count = 1,
        .attributes = &[_]wgpu.VertexAttribute{pos_attr},
        .array_stride = @sizeOf(f32) * 4,
        .step_mode = wgpu.VertexStepMode.vertex,
    };
    const color_attr = wgpu.VertexAttribute{
        .shader_location = 1,
        .format = wgpu.VertexFormat.float32x4,
        .offset = 0,
    };
    const color_buffer_layout = wgpu.VertexBufferLayout{
        .attribute_count = 1,
        .attributes = &[_]wgpu.VertexAttribute{color_attr},
        .array_stride = @sizeOf(f32) * 4,
        .step_mode = wgpu.VertexStepMode.vertex,
    };
    return .{
        .buffer_count = 2,
        .buffers = &[_]wgpu.VertexBufferLayout{
            pos_buffer_layout,
            color_buffer_layout,
        },
        .module = shader_module,
        .entry_point = "vs_main",
        .constant_count = 0,
        .constants = null,
    };
}

fn createRenderPipeline(
    allocator: std.mem.Allocator,
    gctx: *zgpu.GraphicsContext,
) !wgpu.RenderPipeline {
    const shader_module = try manager.loadShaderModule(
        allocator,
        content_dir[0..content_dir.len] ++ "shader.wgsl",
        gctx.device,
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
    const color_target = wgpu.ColorTargetState{
        .format = gctx.swapchain_descriptor.format,
        .blend = &color_blend,
        .write_mask = wgpu.ColorWriteMask.all,
        .next_in_chain = null,
    };

    const frag_state = wgpu.FragmentState{
        .module = shader_module,
        .entry_point = "fs_main",
        .constant_count = 0,
        .constants = null,
        .target_count = 1,
        .targets = &[_]wgpu.ColorTargetState{color_target},
    };

    const pipeline_desc = wgpu.RenderPipelineDescriptor{
        .vertex = createVertexState(shader_module),
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
    const pipeline = try createRenderPipeline(allocator, gctx);

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
        .gctx = gctx,
        .pipeline = pipeline,
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

    // points buffer
    var buf_desc = wgpu.BufferDescriptor{
        .label = "Vertex Position Buffer",
        .usage = wgpu.BufferUsage{ .copy_dst = true, .vertex = true },
        .size = app_state.point_data.items.len * @sizeOf(f32),
        .mapped_at_creation = wgpu.U32Bool.false,
    };
    const point_buffer = gctx.device.createBuffer(buf_desc);

    // color buffer
    buf_desc.label = "Vertex Color Buffer";
    buf_desc.size = app_state.color_data.items.len * @sizeOf(f32);
    const color_buffer = gctx.device.createBuffer(buf_desc);

    // idx buffer
    const index_count: u32 = @intCast(app_state.index_data.items.len);
    buf_desc.label = "Index Buffer";
    buf_desc.size = index_count * @sizeOf(u16);
    buf_desc.usage = .{ .copy_dst = true, .index = true };
    const index_buffer = gctx.device.createBuffer(buf_desc);

    var queue = gctx.device.getQueue();
    queue.writeBuffer(point_buffer, 0, f32, app_state.point_data.items);
    queue.writeBuffer(color_buffer, 0, f32, app_state.color_data.items);
    queue.writeBuffer(index_buffer, 0, u16, app_state.index_data.items);

    while (!window.shouldClose() and window.getKey(.escape) != .press) {
        zglfw.pollEvents();
        //
        // poll GPU
        // gctx.device.tick();

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
