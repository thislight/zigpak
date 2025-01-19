const std = @import("std");
const Prefix = @import("../root.zig").Prefix;
const ContainerType = @import("../root.zig").ContainerType;
const maxInt = std.math.maxInt;

pub fn prefix(len: u32) Prefix {
    var result: Prefix = .{};
    switch (len) {
        0...maxInt(u8) => {
            result.appendSliceAssumeCapacity(&.{
                @intFromEnum(ContainerType.bin8),
                @as(u8, @truncate(len)),
            });
        },
        maxInt(u8) + 1...maxInt(u16) => {
            result.appendAssumeCapacity(@intFromEnum(ContainerType.bin16));
            result.writer().writeInt(u16, @truncate(len), .big) catch unreachable;
        },
        maxInt(u16) + 1...maxInt(u32) => {
            result.appendAssumeCapacity(@intFromEnum(ContainerType.bin32));
            result.writer().writeInt(u32, len, .big) catch unreachable;
        },
    }
    return result;
}

pub fn count(len: u32) usize {
    return @call(.always_inline, prefix, .{len}).len;
}

pub fn write(dst: []u8, len: u32) usize {
    const p = prefix(len);
    @memcpy(dst, p.constSlice());
    return p.len;
}

pub fn pipe(writer: anytype, len: u32) !usize {
    const p = prefix(len);
    return try writer.write(p.constSlice());
}

pub fn pipeVal(writer: anytype, value: []const u8) !usize {
    const sz0 = try pipe(writer, @intCast(value.len));
    const sz1 = try writer.write(value);
    return sz0 + sz1;
}
