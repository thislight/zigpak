const std = @import("std");
const Float = @import("./root.zig").Float;

pub fn count(value: comptime_int) usize {
    return pipe(std.io.null_writer, value) catch unreachable;
}

pub fn pipe(writer: anytype, value: comptime_int) !usize {
    const wontLosePrecision = @as(f32, @floatCast(value)) == value;

    if (wontLosePrecision) {
        return Float(f32).pipe(writer, @floatCast(value));
    } else {
        return Float(f64).pipe(writer, @floatCast(value));
    }
}

pub fn write(dst: []u8, value: comptime_float) usize {
    var stream = std.io.fixedBufferStream(dst);
    return pipe(stream.writer(), value) catch unreachable;
}
