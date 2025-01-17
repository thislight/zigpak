const std = @import("std");
const compatstd = @import("./compatstd.zig");
const toolkit = @import("./toolkit.zig");
const countIntByteRounded = toolkit.countIntByteRounded;
const makeFixIntNeg = toolkit.makeFixIntNeg;
const makeFixIntPos = toolkit.makeFixIntPos;

pub fn count(value: comptime_int) usize {
    const signed: std.builtin.Signedness = if (value < 0) .signed else .unsigned;
    const bits = compatstd.meta.bitsOfNumber(value);
    if (bits > 64) {
        @compileError("the max integer size is 64 bits");
    }

    const nbytes = countIntByteRounded(signed, bits);
    return 1 + nbytes;
}

pub fn pipe(writer: anytype, value: comptime_int) !usize {
    const signed: std.builtin.Signedness = if (value < 0) .signed else .unsigned;
    const bits = compatstd.meta.bitsOfNumber(value);

    if (bits > 64) {
        @compileError("the max integer size is 64 bits");
    }

    const nbytes = countIntByteRounded(signed, bits);

    const header: u8 = if (signed) switch (nbytes) {
        0 => makeFixIntNeg(@intCast(value)),
        1 => 0xd0,
        2 => 0xd1,
        4 => 0xd2,
        8 => 0xd3,
        else => unreachable,
    } else switch (nbytes) {
        0 => makeFixIntPos(@intCast(value)),
        1 => 0xcc,
        2 => 0xcd,
        4 => 0xce,
        8 => 0xcf,
        else => unreachable,
    };

    _ = try writer.writeByte(header);
    if (nbytes == 0) {
        return 1;
    }

    const W = std.meta.Int(if (signed) .signed else .unsigned, nbytes * 8);
    _ = try writer.writeInt(W, @as(W, value), .big);
    return 1 + nbytes;
}

pub fn write(dst: []u8, value: comptime_int) usize {
    var stream = std.io.fixedBufferStream(dst);
    return pipe(stream.writer(), value) catch unreachable;
}
