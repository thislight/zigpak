const std = @import("std");
const compatstd = @import("../compatstd.zig");
const readIntBig = compatstd.mem.readIntBig;
const assert = std.debug.assert;
const absCast = compatstd.math.absCast;
const writeIntBig = compatstd.mem.writeIntBig;
const bytesToValue = std.mem.bytesToValue;
const bytesAsValue = std.mem.bytesAsValue;
const asBytes = std.mem.asBytes;
const maxInt = std.math.maxInt;
const minInt = std.math.minInt;
const pow = std.math.pow;
const comptimePrint = std.fmt.comptimePrint;
const Allocator = std.mem.Allocator;
const log2IntCeil = std.math.log2_int_ceil;
const log2 = std.math.log2;
const readFloatBig = compatstd.mem.readFloatBig;
const writeFloatBig = compatstd.mem.writeFloatBig;
const toolkit = @import("../toolkit.zig");
const countIntByteRounded = toolkit.countIntByteRounded;
const makeFixIntNeg = toolkit.makeFixIntNeg;
const makeFixIntPos = toolkit.makeFixIntPos;

const ComptimeInt = @import("./ComptimeInt.zig");

/// Wrappers of integer type `T`, signed or unsigned.
pub fn Int(T: type) type {
    if (T == comptime_int) {
        return ComptimeInt;
    }

    const signed = compatstd.meta.signednessOf(T) == .signed;
    const bits = @bitSizeOf(T);
    if (bits > 64) {
        @compileError("the max integer size is 64 bits");
    }

    const nbytes = countIntByteRounded(signed, bits);

    return struct {
        /// Count the byte number required.
        pub fn count(_: T) usize {
            return 1 + nbytes;
        }

        fn headerOf(value: T) u8 {
            return if (signed) switch (nbytes) {
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
        }

        /// Write the value into the std.io `writer`.
        pub fn pipe(writer: anytype, value: T) !usize {
            _ = try writer.writeByte(headerOf(value));

            if (nbytes == 0) {
                return 1;
            }

            const W = std.meta.Int(if (signed) .signed else .unsigned, nbytes * 8);
            try writer.writeInt(W, @as(W, value), .big);
            return 1 + nbytes;
        }

        /// Write integer into `dst`.
        ///
        /// This function uses type information from `T` to recognise the type in msgpack.
        /// If the type is `i64`, the value is stored as a 64-bit signed integer; if the type is u24,
        /// a 32-bit unsigned is used.
        ///
        /// If you need to use the smallest type depends on the `value`, see `pipeSm` and `writeSm`.
        pub fn write(dst: []u8, value: T) usize {
            var stream = std.io.fixedBufferStream(dst);
            return @call(.always_inline, pipe, .{ stream.writer(), value }) catch unreachable;
        }

        /// Count the smallest byte number for storing the `value`.
        pub fn countSm(value: T) usize {
            return @call(.always_inline, pipeSm, .{ std.io.null_writer, value }) catch unreachable;
        }

        /// Write integer into `writer` uses smallest msgpack type.
        pub fn pipeSm(writer: anytype, value: T) !usize {
            if (value >= 0) {
                if (value >= 0 and value <= 0b01111111) {
                    return try Int(u7).pipe(writer, @intCast(value));
                } else if (value <= maxInt(u8)) {
                    return try Int(u8).pipe(writer, @intCast(value));
                } else if (value <= maxInt(u16)) {
                    return try Int(u16).pipe(writer, @intCast(value));
                } else if (value <= maxInt(u32)) {
                    return try Int(u32).pipe(writer, @intCast(value));
                } else if (value <= maxInt(u64)) {
                    return try Int(u64).pipe(writer, @intCast(value));
                }
            } else if (signed) {
                if (value >= -0b00011111) {
                    return try Int(i6).pipe(writer, @intCast(value));
                } else if (value >= minInt(i8)) {
                    return try Int(i8).pipe(writer, @intCast(value));
                } else if (value >= minInt(i16)) {
                    return try Int(i16).pipe(writer, @intCast(value));
                } else if (value >= minInt(i32)) {
                    return try Int(i32).pipe(writer, @intCast(value));
                } else if (value >= minInt(i64)) {
                    return try Int(i64).pipe(writer, @intCast(value));
                }
            }
            unreachable;
        }

        /// Write `value` into the buffer uses smallest msgpack type.
        pub fn writeSm(dst: []u8, value: T) usize {
            var stream = std.io.fixedBufferStream(dst);
            return pipeSm(stream.writer(), value) catch unreachable;
        }
    };
}

test Int {
    const t = std.testing;
    { // Emit i32 as-is
        var dst: std.BoundedArray(u8, 8) = .{};
        Int(i32).pipe(dst.writer(), 15);
        try t.expectEqual(15, std.mem.readInt(dst.buffer[1..5], .big));
    }
    { // Emit i32 as the smallest type
        var dst: std.BoundedArray(u8, 8) = .{};
        Int(i32).pipeSm(dst.writer(), 15);
        try t.expectEqual(1, dst.len);
    }
}

const ComptimeFloat = @import("./ComptimeFloat.zig");

/// Wrapper of float types.
pub fn Float(T: type) type {
    if (T == comptime_float) {
        return ComptimeFloat;
    }

    const nbytes = switch (@bitSizeOf(T)) {
        0...32 => 4,
        33...64 => 8,
        else => @compileError(comptimePrint("unsupported {}", .{@typeName(T)})),
    };

    return struct {
        /// Count the byte number required.
        pub fn count(_: T) usize {
            return 1 + nbytes;
        }

        /// Write the `value` into std.io `writer`.
        pub fn pipe(writer: anytype, value: T) !usize {
            _ = try writer.writeByte(switch (nbytes) {
                4 => 0xca,
                8 => 0xcb,
                else => unreachable,
            });
            var buf = [_]u8{0} ** 8;
            switch (nbytes) {
                4 => writeFloatBig(f32, buf[0..4], @floatCast(value)),
                8 => writeFloatBig(f64, buf[0..8], @floatCast(value)),
                else => unreachable,
            }
            _ = try writer.write(buf[0..nbytes]);
            return 1 + nbytes;
        }

        /// Fill the `dst` with `value`.
        pub fn write(dst: []u8, value: T) usize {
            var stream = std.io.fixedBufferStream(dst);
            return @call(.always_inline, pipe, .{ stream.writer(), value }) catch unreachable;
        }

        /// Count the smallest byte number for storing `value`.
        pub fn countSm(value: T) usize {
            return @call(.always_inline, pipeSm, .{ std.io.null_writer, value }) catch unreachable;
        }

        /// Write the `value` into std.io `writer` with the smallest type.
        pub fn pipeSm(writer: anytype, value: T) !usize {
            const wontLosePrecision = @as(f32, @floatCast(value)) == value;

            if (wontLosePrecision) {
                return try Float(f32).pipe(writer, @floatCast(value));
            } else {
                return try Float(f64).pipe(writer, @floatCast(value));
            }
        }

        /// Fill `dst` with smallest type of `value`.
        pub fn writeSm(dst: []u8, value: T) usize {
            var stream = std.io.fixedBufferStream(dst);
            return @call(.always_inline, pipeSm, .{ stream.writer(), value }) catch unreachable;
        }
    };
}
