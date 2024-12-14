const std = @import("std");
const builtin = @import("builtin");
const bytesAsValue = std.mem.bytesAsValue;
const asBytes = std.mem.asBytes;
const nativeEndian = @import("builtin").cpu.arch.endian();

const isZig0d14AndLater = !builtin.zig_version.order(.{ .major = 0, .minor = 14, .patch = 0 }).compare(.lt);

pub const mem = struct {
    pub fn writeIntBig(T: type, dst: *[@divExact(@typeInfo(T).Int.bits, 8)]u8, value: T) void {
        return std.mem.writeInt(T, dst, value, .big);
    }

    pub fn readIntBig(T: type, src: *const [@divExact(@typeInfo(T).Int.bits, 8)]u8) T {
        return std.mem.readInt(T, src, .big);
    }

    fn bitsOfFloat(T: type) comptime_int {
        if (isZig0d14AndLater) {
            return @typeInfo(T).float.bits;
        }
        return @typeInfo(T).Float.bits;
    }

    pub fn readFloatBig(comptime T: type, src: *const [@divExact(bitsOfFloat(T), 8)]u8) T {
        if (bitsOfFloat(T) > 64) {
            @compileError("readFloatBig does not support float types have more than 64 bits.");
        }

        if (nativeEndian == .little) {
            var swapped: [@divExact(bitsOfFloat(T), 8)]u8 = undefined;
            for (0..@divExact(src.len, 2)) |i| {
                const j = src.len - i - 1;
                swapped[i] = src[j];
                swapped[j] = src[i];
            }
            return bytesAsValue(T, &swapped).*;
        }

        return bytesAsValue(T, src).*;
    }

    pub fn writeFloatBig(comptime T: type, dest: *[@divExact(bitsOfFloat(T), 8)]u8, val: T) void {
        if (bitsOfFloat(T) > 64) {
            @compileError("writeFloatBig does not support float types have more than 64 bits.");
        }
        std.mem.copyForwards(u8, dest, asBytes(&val));
        if (nativeEndian == .little) {
            for (0..@divExact(dest.len, 2)) |i| {
                std.mem.swap(u8, &dest[i], &dest[dest.len - i - 1]);
            }
        }
    }
};

pub const math = struct {
    pub fn absCast(value: anytype) @TypeOf(@abs(value)) {
        return @abs(value);
    }
};
