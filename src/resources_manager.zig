const std = @import("std");
const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;

pub const Resources = struct {
    mesh: Mesh,

    pub fn load(allocator: std.mem.Allocator, content_dir: []const u8) !Resources {
        const mesh_path = try std.fs.path.join(allocator, &.{ content_dir, "/geometry" });
        defer allocator.free(mesh_path);

        const mesh = try Mesh.loadCustom(allocator, mesh_path);
        return Resources{ .mesh = mesh };
    }

    pub fn deinit(self: *Resources) void {
        self.mesh.deinit();
    }
};

pub const Mesh = struct {
    point_data: std.ArrayList(f32),
    color_data: std.ArrayList(f32),
    index_data: std.ArrayList(u16),

    fn loadCustom(
        allocator: std.mem.Allocator,
        path: []const u8,
    ) !Mesh {
        var file = std.fs.cwd().openFile(path, .{}) catch |err| {
            std.log.err("failed to open file '{s}'; {s}", .{ path, @errorName(err) });
            return err;
        };
        defer file.close();

        var point_data = std.ArrayList(f32).init(allocator);
        var color_data = std.ArrayList(f32).init(allocator);
        var index_data = std.ArrayList(u16).init(allocator);

        const Section = enum {
            none,
            points,
            colors,
            indices,
        };
        var current_section: Section = .none;
        var line_buffer = std.ArrayList(u8).init(allocator);
        defer line_buffer.deinit();
        var line_no: usize = 0;
        while (true) {
            file
                .reader()
                .streamUntilDelimiter(
                line_buffer.writer(),
                '\n',
                null,
            ) catch |err| switch (err) {
                error.EndOfStream => break,
                else => |e| return e,
            };

            line_no += 1;

            // Handle Windows line endings
            if (line_buffer.items.len > 0 and line_buffer.items[line_buffer.items.len - 1] == '\r') {
                _ = line_buffer.pop();
            }

            const line = line_buffer.items;

            if (std.mem.eql(u8, line, "[points]")) {
                current_section = .points;
            } else if (std.mem.eql(u8, line, "[colors]")) {
                current_section = .colors;
            } else if (std.mem.eql(u8, line, "[indices]")) {
                current_section = .indices;
            } else if (line.len == 0 or line[0] == '#') {} else switch (current_section) {
                .points => {
                    var tokens = std.mem.tokenizeScalar(u8, line, ' ');
                    while (tokens.next()) |token| {
                        // std.debug.print("\npoint token: {s}\n", .{token});
                        const value = try std.fmt.parseFloat(f32, token);
                        try point_data.append(value);
                    }
                },
                .colors => {
                    var tokens = std.mem.tokenizeScalar(u8, line, ' ');
                    while (tokens.next()) |token| {
                        const value = try std.fmt.parseFloat(f32, token);
                        try color_data.append(value);
                    }
                },
                .indices => {
                    var tokens = std.mem.tokenizeScalar(u8, line, ' ');
                    while (tokens.next()) |token| {
                        const value = try std.fmt.parseInt(u16, token, 10);
                        try index_data.append(value);
                    }
                },
                .none => {},
            }
            line_buffer.clearRetainingCapacity();
        }
        // round buffers:
        var remainder: usize = point_data.items.len * @sizeOf(f32) % 4;
        if (remainder != 0) {
            unreachable;
        }
        remainder = color_data.items.len * @sizeOf(f32) % 4;
        if (remainder != 0) {
            unreachable;
        }
        remainder = index_data.items.len * @sizeOf(f16) % 4;
        if (remainder != 0) {
            _ = try index_data.addManyAsSlice(@divExact(remainder, @sizeOf(f16)));
        }

        return Mesh{
            .point_data = point_data,
            .color_data = color_data,
            .index_data = index_data,
        };
    }

    fn deinit(self: *Mesh) void {
        self.point_data.deinit();
        self.color_data.deinit();
        self.index_data.deinit();
    }
};

pub fn loadShaderModule(
    allocator: std.mem.Allocator,
    path: []const u8,
    device: wgpu.Device,
) !wgpu.ShaderModule {
    const buffer = std.fs.cwd().readFileAllocOptions(
        allocator,
        path,
        std.math.maxInt(usize),
        null,
        @alignOf(u8),
        0,
    ) catch |err| {
        std.log.err("failed to read file '{s}'; {s}", .{ path, @errorName(err) });
        return err;
    };
    defer allocator.free(buffer);

    const shader_code_desc = wgpu.ShaderModuleWGSLDescriptor{
        .chain = .{
            .next = null,
            .struct_type = wgpu.StructType.shader_module_wgsl_descriptor,
        },
        .code = @ptrCast(buffer.ptr),
    };
    return device.createShaderModule(
        .{ .next_in_chain = &shader_code_desc.chain },
    );
}
