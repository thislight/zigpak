const std = @import("std");
const Prefix = @import("../root.zig").Prefix;
const ContainerType = @import("../root.zig").ContainerType;
const maxInt = std.math.maxInt;

pub fn prefix(len: u32) Prefix {
    var result: Prefix = .{};
    _ = pipe(result.writer(), len) catch unreachable;
    return result;
}

pub fn count(len: u32) usize {
    return @call(.always_inline, pipe, .{ std.io.null_writer, len }) catch unreachable;
}

pub fn write(dst: []u8, len: u32) usize {
    const p = prefix(len);
    @memcpy(dst, p.constSlice());
    return p.len;
}

/// Write the prefix into the std.io `writer`.
pub fn pipe(writer: anytype, len: u32) !usize {
    switch (len) {
        0...maxInt(u8) => {
            _ = try writer.write(&.{
                @intFromEnum(ContainerType.bin8),
                @as(u8, @truncate(len)),
            });
            return 2;
        },
        maxInt(u8) + 1...maxInt(u16) => {
            try writer.writeByte(@intFromEnum(ContainerType.bin16));
            try writer.writeInt(u16, @truncate(len), .big);
            return 3;
        },
        maxInt(u16) + 1...maxInt(u32) => {
            try writer.writeByte(@intFromEnum(ContainerType.bin32));
            try writer.writeInt(u32, len, .big);
            return 5;
        },
    }
}

pub fn pipeVal(writer: anytype, value: []const u8) !usize {
    const sz0 = try pipe(writer, @intCast(value.len));
    const sz1 = try writer.write(value);
    return sz0 + sz1;
}
