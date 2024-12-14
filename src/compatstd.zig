const std = @import("std");
const builtin = @import("builtin");
const bytesAsValue = std.mem.bytesAsValue;
const asBytes = std.mem.asBytes;
const nativeEndian = @import("builtin").cpu.arch.endian();

pub const mem = struct {
    pub fn writeIntBig(T: type, dst: *[@divExact(@typeInfo(T).Int.bits, 8)]u8, value: T) void {
        return std.mem.writeInt(T, dst, value, .big);
    }

    pub fn readIntBig(T: type, src: *const [@divExact(@typeInfo(T).Int.bits, 8)]u8) T {
        return std.mem.readInt(T, src, .big);
    }

    pub fn readFloatBig(comptime T: type, src: *const [@divExact(@typeInfo(T).Float.bits, 8)]u8) T {
        const inf = @typeInfo(T).Float;
        if (inf.bits > 64) {
            @compileError("readFloatBig does not support float types have more than 64 bits.");
        }

        if (nativeEndian == .little) {
            var swapped: @typeInfo(@TypeOf(src)).Pointer.child = undefined;
            for (0..@divExact(src.len, 2)) |i| {
                const j = src.len - i - 1;
                swapped[i] = src[j];
                swapped[j] = src[i];
            }
            return bytesAsValue(T, &swapped).*;
        }

        return bytesAsValue(T, src).*;
    }

    pub fn writeFloatBig(comptime T: type, dest: *[@divExact(@typeInfo(T).Float.bits, 8)]u8, val: T) void {
        const inf = @typeInfo(T).Float;
        if (inf.bits > 64) {
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
