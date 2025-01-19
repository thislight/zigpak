const std = @import("std");
const Prefix = @import("../root.zig").Prefix;
const maxInt = std.math.maxInt;

pub fn prefix(len: u32) Prefix {
    var result: Prefix = .{};
    switch (len) {
        0...0b00001111 => {
            result.appendAssumeCapacity(0b10010000 | (0b00001111 & @as(u8, @truncate(len))));
        },
        (0b00001111 + 1)...maxInt(u16) => {
            result.appendAssumeCapacity(0xdc);
            result.writer().writeInt(u16, @truncate(len), .big) catch unreachable;
        },
        maxInt(u16) + 1...maxInt(u32) => {
            result.appendAssumeCapacity(0xdd);
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
