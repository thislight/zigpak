const std = @import("std");
const Float = @import("./root.zig").Float;

pub fn countSm(value: comptime_int) usize {
    return serializeSm(std.io.null_writer, value) catch unreachable;
}

pub fn serializeSm(writer: anytype, value: comptime_int) !usize {
    const wontLosePrecision = @as(f32, @floatCast(value)) == value;

    if (wontLosePrecision) {
        return Float(f32).serialize(writer, @floatCast(value));
    } else {
        return Float(f64).serialize(writer, @floatCast(value));
    }
}

pub fn writeSm(dst: []u8, value: comptime_float) usize {
    var stream = std.io.fixedBufferStream(dst);
    return serializeSm(stream.writer(), value) catch unreachable;
}

pub const count = countSm;
pub const serialize = serializeSm;
pub const write = writeSm;
