const std = @import("std");
const Prefix = @import("../root.zig").Prefix;
const maxInt = std.math.maxInt;
const log2 = std.math.log2;

/// Generate a ext prefix.
pub fn prefix(len: u32, extype: i8) Prefix {
    var result: Prefix = .{};
    switch (len) {
        1, 2, 4, 8, 16 => |b| {
            result.appendAssumeCapacity(0xd4 + log2(b));
            result.writer().writeInt(i8, extype, .big) catch unreachable;
        },
        0...maxInt(u8) => {
            result.appendSliceAssumeCapacity(&.{ 0xc7, @truncate(len) });
            result.writer().writeInt(i8, extype, .big) catch unreachable;
        },
        maxInt(u8) + 1...maxInt(u16) => {
            result.appendAssumeCapacity(0xc8);
            result.writer().writeInt(u16, @truncate(len), .big) catch unreachable;
            result.writer().writeInt(i8, extype, .big) catch unreachable;
        },
        maxInt(u16) + 1...maxInt(u32) => {
            result.appendAssumeCapacity(0xc9);
            result.writer().writeInt(u32, @truncate(len), .big) catch unreachable;
            result.writer().writeInt(i8, extype, .big) catch unreachable;
        },
    }
    return result;
}

pub fn count(len: u32, extype: i8) usize {
    return @call(.always_inline, prefix, .{ len, extype }).len;
}

pub fn write(dst: []u8, len: u32, extype: i8) usize {
    const p = prefix(len, extype);
    @memcpy(dst, p.constSlice());
    return p.len;
}

pub fn pipe(writer: anytype, len: u32, extype: i8) !usize {
    const p = prefix(len, extype);
    return try writer.write(p.constSlice());
}

pub fn pipeVal(writer: anytype, extype: i8, value: []const u8) !usize {
    const sz0 = try pipe(writer, @intCast(value.len), extype);
    const sz1 = try writer.write(value);
    return sz0 + sz1;
}
