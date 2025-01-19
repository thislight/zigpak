const std = @import("std");
const Prefix = @import("../root.zig").Prefix;
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

/// Write the prefix into std.io `writer`.
pub fn pipe(writer: anytype, len: u32) !usize {
    switch (len) {
        0...0b00001111 => {
            try writer.writeByte(0b10010000 | (0b00001111 & @as(u8, @truncate(len))));
            return 1;
        },
        (0b00001111 + 1)...maxInt(u16) => {
            try writer.writeByte(0xdc);
            try writer.writeInt(u16, @truncate(len), .big);
            return 3;
        },
        maxInt(u16) + 1...maxInt(u32) => {
            try writer.writeByte(0xdd);
            try writer.writeInt(u32, len, .big);
            return 5;
        },
    }
}
