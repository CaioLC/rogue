const std = @import("std");
const zglfw = @import("zglfw");
const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;
const manager = @import("./resources_manager.zig");
const content_dir = @import("build_options").assets;

const BufferCtx = struct { ready: bool, buffer: wgpu.Buffer };
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

const Buffers = struct {
    point_buffer: wgpu.Buffer,
    color_buffer: wgpu.Buffer,
    index_buffer: wgpu.Buffer,
    uniform_buffer: wgpu.Buffer,
};

pub const GlobalState = struct {
    ctx: *zgpu.GraphicsContext,
    bind_group_layouts: [1]wgpu.BindGroupLayout,
    pipeline_layout: wgpu.PipelineLayout,
    pipeline: wgpu.RenderPipeline,

    pub fn init(
        allocator: std.mem.Allocator,
        window: *zglfw.Window,
    ) !GlobalState {
        const ctx = try initGraphicsContext(allocator, window);

        const bind_group_layouts = [_]wgpu.BindGroupLayout{
            utime_bind_group_layout(ctx.device),
        };
        const pipeline_layout = create_pipeline_layout(
            ctx.device,
            &bind_group_layouts,
        );
        const pipeline = try create_render_pipeline(
            allocator,
            ctx,
            pipeline_layout,
        );

        return .{
            .ctx = ctx,
            .bind_group_layouts = bind_group_layouts,
            .pipeline_layout = pipeline_layout,
            .pipeline = pipeline,
        };
    }

    pub fn release(
        state: *GlobalState,
        allocator: std.mem.Allocator,
    ) void {
        defer state.ctx.destroy(allocator);
        defer state.pipeline.release();
        defer state.pipeline_layout.release();
        defer for (state.bind_group_layouts) |group| {
            group.release();
        };
    }
};

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

fn create_render_pipeline(
    allocator: std.mem.Allocator,
    gctx: *zgpu.GraphicsContext,
    layout: wgpu.PipelineLayout,
) !wgpu.RenderPipeline {
    const shader_module = try manager.loadShaderModule(
        allocator,
        content_dir[0..content_dir.len] ++ "shader.wgsl",
        gctx.device,
    );
    defer shader_module.release();

    // vertex
    const vertex_state = create_vertex_state(shader_module);

    // fragment
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
        .vertex = vertex_state,
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
        .layout = layout,
    };

    return gctx.device.createRenderPipeline(pipeline_desc);
}

fn create_vertex_state(shader_module: wgpu.ShaderModule) wgpu.VertexState {
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

fn create_pipeline_layout(
    device: wgpu.Device,
    bind_group_layouts: []const wgpu.BindGroupLayout,
) wgpu.PipelineLayout {
    const layout_desc = wgpu.PipelineLayoutDescriptor{
        .bind_group_layout_count = bind_group_layouts.len,
        .bind_group_layouts = bind_group_layouts.ptr,
    };
    return device.createPipelineLayout(layout_desc);
}

fn utime_bind_group_layout(device: wgpu.Device) wgpu.BindGroupLayout {
    const binding_layout = wgpu.BindGroupLayoutEntry{
        .binding = 0,
        .visibility = wgpu.ShaderStage{ .vertex = true },
        .buffer = .{
            .binding_type = wgpu.BufferBindingType.uniform,
            .min_binding_size = 4 * @sizeOf(f32),
        },
    };
    const bind_group_layout_desc = wgpu.BindGroupLayoutDescriptor{
        .entry_count = 1,
        .entries = &[_]wgpu.BindGroupLayoutEntry{
            binding_layout,
        },
    };
    return device.createBindGroupLayout(bind_group_layout_desc);
}

pub fn utime_bind_group(utime_buffer: wgpu.Buffer) wgpu.BindGroupEntry {
    return wgpu.BindGroupEntry{
        .binding = 0,
        .buffer = utime_buffer,
        .offset = 0,
        .size = 4 * @sizeOf(f32),
    };
}

pub fn create_buffer(
    device: wgpu.Device,
    label: ?[*:0]const u8,
    usage: wgpu.BufferUsage,
    size: u64,
    mapped_at_creation: wgpu.U32Bool,
) wgpu.Buffer {
    const buf_desc = wgpu.BufferDescriptor{
        .label = label,
        .usage = usage,
        .size = size,
        .mapped_at_creation = mapped_at_creation,
    };
    return device.createBuffer(buf_desc);
}
