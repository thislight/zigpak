const std = @import("std");
const Prefix = @import("../root.zig").Prefix;
const maxInt = std.math.maxInt;
const log2 = std.math.log2;

const AnyExt = @This();

/// Generate an ext prefix.
pub fn prefix(len: u32, extype: i8) Prefix {
    var result: Prefix = .{};
    _ = pipe(result.writer(), len, extype) catch unreachable;
    return result;
}

pub fn count(len: u32, extype: i8) usize {
    return @call(.always_inline, pipe, .{ std.io.null_writer, len, extype }) catch unreachable;
}

test count {
    const t = std.testing;
    try t.expectEqual(2, AnyExt.count(4, 1));
    try t.expectEqual(3, AnyExt.count(0, 1));
    try t.expectEqual(4, AnyExt.count(maxInt(u8) + 1, 1));
    try t.expectEqual(6, AnyExt.count(maxInt(u16) + 1, 1));
}

pub fn write(dst: []u8, len: u32, extype: i8) usize {
    const p = prefix(len, extype);
    @memcpy(dst, p.constSlice());
    return p.len;
}

/// Write the prefix into std.io `writer`.
pub fn pipe(writer: anytype, len: u32, extype: i8) !usize {
    switch (len) {
        1, 2, 4, 8, 16 => |b| {
            try writer.writeByte(0xd4 + log2(b));
            try writer.writeInt(i8, extype, .big);
            return 2;
        },
        0...maxInt(u8) => {
            _ = try writer.write(&.{ 0xc7, @truncate(len) });
            try writer.writeInt(i8, extype, .big);
            return 3;
        },
        maxInt(u8) + 1...maxInt(u16) => {
            try writer.writeByte(0xc8);
            try writer.writeInt(u16, @truncate(len), .big);
            try writer.writeInt(i8, extype, .big);
            return 4;
        },
        maxInt(u16) + 1...maxInt(u32) => {
            try writer.writeByte(0xc9);
            try writer.writeInt(u32, @truncate(len), .big);
            try writer.writeInt(i8, extype, .big);
            return 6;
        },
    }
}

/// Write the value into std.io `writer`.
pub fn pipeVal(writer: anytype, extype: i8, value: []const u8) !usize {
    const sz0 = try pipe(writer, @intCast(value.len), extype);
    const sz1 = try writer.write(value);
    return sz0 + sz1;
}
