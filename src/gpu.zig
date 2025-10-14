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
            Uniforms.bind_group_layout(ctx.device),
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

    const depth_stencil_state = wgpu.DepthStencilState{
        .depth_compare = wgpu.CompareFunction.less,
        .depth_write_enabled = true,
        .format = .depth24_plus,
        .stencil_read_mask = 0,
        .stencil_write_mask = 0,
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
        .depth_stencil = &depth_stencil_state,
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

pub const BuffersManager = struct {
    point_data: std.ArrayList(f32),
    color_data: std.ArrayList(f32),
    index_data: std.ArrayList(u16),
    point_buffer: wgpu.Buffer,
    color_buffer: wgpu.Buffer,
    index_buffer: wgpu.Buffer,
    uniform_buffer: wgpu.Buffer,

    pub fn init(
        allocator: std.mem.Allocator,
        device: wgpu.Device,
        geo_path: []const u8,
    ) !BuffersManager {
        var point_data = std.ArrayList(f32).init(allocator);
        errdefer point_data.deinit();
        var color_data = std.ArrayList(f32).init(allocator);
        errdefer color_data.deinit();
        var index_data = std.ArrayList(u16).init(allocator);
        errdefer index_data.deinit();

        try manager.loadGeometry(
            allocator,
            geo_path,
            &point_data,
            &color_data,
            &index_data,
        );

        std.debug.print("Initialize Buffers\n", .{});
        const point_buffer = create_buffer(
            device,
            "Vertex Position Buffer",
            wgpu.BufferUsage{ .copy_dst = true, .vertex = true },
            point_data.items.len * @sizeOf(f32),
            wgpu.U32Bool.false,
        );

        // color buffer
        const color_buffer = create_buffer(
            device,
            "Vertex Color Buffer",
            wgpu.BufferUsage{ .copy_dst = true, .vertex = true },
            color_data.items.len * @sizeOf(f32),
            wgpu.U32Bool.false,
        );

        // idx buffer
        const index_buffer = create_buffer(
            device,
            "Index Buffer",
            wgpu.BufferUsage{ .copy_dst = true, .index = true },
            index_data.items.len * @sizeOf(u16),
            wgpu.U32Bool.false,
        );

        // unifom buffer
        const uniform_buffer = create_buffer(
            device,
            "Time Uniform Buffer",
            wgpu.BufferUsage{ .copy_dst = true, .uniform = true },
            try stride(@sizeOf(Uniforms), device) + @sizeOf(Uniforms),
            wgpu.U32Bool.false,
        );

        return BuffersManager{
            .point_data = point_data,
            .color_data = color_data,
            .index_data = index_data,
            .point_buffer = point_buffer,
            .color_buffer = color_buffer,
            .index_buffer = index_buffer,
            .uniform_buffer = uniform_buffer,
        };
    }

    pub fn release(self: *BuffersManager) void {
        self.point_data.deinit();
        self.color_data.deinit();
        self.index_data.deinit();
        self.index_buffer.release();
        self.color_buffer.release();
        self.point_buffer.release();
        self.uniform_buffer.release();
    }

    pub fn index_count(self: *BuffersManager) u32 {
        return @intCast(self.index_data.items.len);
    }

    pub fn write_buffers(self: *BuffersManager, queue: wgpu.Queue) void {
        queue.writeBuffer(self.point_buffer, 0, f32, self.point_data.items);
        queue.writeBuffer(self.color_buffer, 0, f32, self.color_data.items);
        queue.writeBuffer(self.index_buffer, 0, u16, self.index_data.items);
    }
};

pub const Bindings = struct {
    uniforms_bind_group: wgpu.BindGroup,

    pub fn init(gpu_state: GlobalState, uniform_buffer: wgpu.Buffer) Bindings {
        // initialize bind groups
        const bindings = [_]wgpu.BindGroupEntry{
            Uniforms.bind_group(uniform_buffer),
        };
        const bind_group_desc = wgpu.BindGroupDescriptor{
            .layout = gpu_state.bind_group_layouts[0],
            .entry_count = bindings.len,
            .entries = &bindings,
        };
        const bind_group = gpu_state.ctx.device.createBindGroup(bind_group_desc);
        return Bindings{
            .uniforms_bind_group = bind_group,
        };
    }
    pub fn release(self: *Bindings) void {
        defer self.uniforms_bind_group.release();
    }
};

pub const Uniforms = struct {
    color: [4]f32,
    time: f32,
    _pad: [3]f32 = undefined,

    fn bind_group_layout(device: wgpu.Device) wgpu.BindGroupLayout {
        const binding_layout = wgpu.BindGroupLayoutEntry{
            .binding = 0,
            .visibility = wgpu.ShaderStage{ .vertex = true, .fragment = true },
            .buffer = .{
                .binding_type = wgpu.BufferBindingType.uniform,
                .min_binding_size = @sizeOf(Uniforms),
                .has_dynamic_offset = wgpu.U32Bool.true,
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

    fn bind_group(uniforms_buffer: wgpu.Buffer) wgpu.BindGroupEntry {
        return wgpu.BindGroupEntry{
            .binding = 0,
            .buffer = uniforms_buffer,
            .offset = 0,
            .size = @sizeOf(Uniforms),
        };
    }
};

pub fn stride(size: u32, device: wgpu.Device) !u32 {
    var limits = wgpu.SupportedLimits{};
    const success: bool = device.getLimits(&limits);
    if (success) {
        const min_offset = limits.limits.min_uniform_buffer_offset_alignment;
        const multiples = size / min_offset;
        return min_offset * (1 + multiples);
    } else {
        std.debug.print("Failed to get limits", .{});
        return error.GetLimitsFailed;
    }
}

pub fn inspect_device(allocator: std.mem.Allocator, device: wgpu.Device) !void {
    const feature_count = device.enumerateFeatures(null);
    var features = try std.ArrayList(wgpu.FeatureName).initCapacity(
        allocator,
        feature_count,
    );
    defer features.deinit();
    _ = device.enumerateFeatures(features.items.ptr);

    std.debug.print("Device Features: \n", .{});
    std.debug.print(" - count: {}: \n", .{feature_count});
    for (features.items) |feat| {
        std.debug.print(" - {}", .{feat});
    }

    var limits = wgpu.SupportedLimits{};
    const success: bool = device.getLimits(&limits);
    if (success) {
        std.debug.print("Device Limits: \n", .{});
        std.debug.print(" - min uniform buffer offset alignment {}\n", .{limits.limits.min_uniform_buffer_offset_alignment});
    } else {
        std.debug.print("Failed to get limits", .{});
    }
}
