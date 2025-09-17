//! By convention, root.zig is the root source file when making a library.
const std = @import("std");

pub fn loadGeometry(
    allocator: std.mem.Allocator,
    path: *const []u8,
    point_data: *std.ArrayList(f32),
    index_data: *std.ArrayList(u16),
) !void {
    var file = std.fs.cwd().openFile(path, .{}) catch |err| {
        std.log.err("failed to open file '{s}'; {s}", .{ path, @errorName(err) });
        return err;
    };
    defer file.close();

    point_data.clearRetainingCapacity();
    index_data.clearRetainingCapacity();

    const Section = enum {
        none,
        points,
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
        } else if (std.mem.eql(u8, line, "[indices]")) {
            current_section = .indices;
        } else if (line.len == 0 or line[0] == '#') {} else switch (current_section) {
            .points => {
                var tokens = std.mem.tokenizeScalar(u8, line, ' ');
                if (tokens.buffer.len != 4) {
                    std.debug.print("Failed to parse point line {}: {}", .{ line_no, line });
                    return error.BadContentLine;
                }
                while (tokens.next()) |token| {
                    const value = try std.fmt.parseFloat(f32, token);
                    try point_data.append(value);
                }
            },
            .indices => {
                var tokens = std.mem.tokenizeScalar(u8, line, ' ');
                if (tokens.buffer.len != 3) {
                    std.debug.print("Failed to parse index line {}: {}", .{ line_no, line });
                    return error.BadContentLine;
                }
                while (tokens.next()) |token| {
                    const value = try std.fmt.parseFloat(f32, token);
                    try index_data.append(value);
                }
            },
            .none => {},
        }

        line_buffer.clearRetainingCapacity();
    }
}

// pub fn loadShader(path: *const []u8) []u8 {
//     const x = "hello";
//     return []u8;
// }

pub fn bufferedPrint() !void {
    // Stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    const stdout_file = std.fs.File.stdout().deprecatedWriter();
    // Buffering can improve performance significantly in print-heavy programs.
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    try bw.flush(); // Don't forget to flush!
}

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add functionality" {
    try std.testing.expect(add(3, 7) == 10);
}
