// SPDX: Apache-2.0
// This file is part of zigpak.
const std = @import("std");
const builtin = @import("builtin");
const bytesAsValue = std.mem.bytesAsValue;
const asBytes = std.mem.asBytes;
const nativeEndian = @import("builtin").cpu.arch.endian();

const isZig0d14AndLater = builtin.zig_version.order(.{ .major = 0, .minor = 13, .patch = 0 }).compare(.gt);

pub const mem = struct {
    pub fn writeIntBig(T: type, dst: *[@divExact(meta.bitsOfType(T), 8)]u8, value: T) void {
        return std.mem.writeInt(T, dst, value, .big);
    }

    pub fn readIntBig(T: type, src: *const [@divExact(meta.bitsOfType(T), 8)]u8) T {
        return std.mem.readInt(T, src, .big);
    }

    pub fn readFloatBig(comptime T: type, src: *const [@divExact(meta.bitsOfType(T), 8)]u8) T {
        if (meta.bitsOfType(T) > 64) {
            @compileError("readFloatBig does not support float types have more than 64 bits.");
        }

        if (nativeEndian == .little) {
            var swapped: [@divExact(meta.bitsOfType(T), 8)]u8 = undefined;
            for (0..@divExact(src.len, 2)) |i| {
                const j = src.len - i - 1;
                swapped[i] = src[j];
                swapped[j] = src[i];
            }
            return bytesAsValue(T, &swapped).*;
        }

        return bytesAsValue(T, src).*;
    }

    pub fn writeFloatBig(comptime T: type, dest: *[@divExact(meta.bitsOfType(T), 8)]u8, val: T) void {
        if (meta.bitsOfType(T) > 64) {
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

pub const meta = struct {
    pub inline fn bitsOfType(T: type) u16 {
        if (isZig0d14AndLater) {
            return switch (@typeInfo(T)) {
                .int => |i| i.bits,
                .float => |f| f.bits,
                else => @compileError("T must be integer type or float type"),
            };
        } else {
            return switch (@typeInfo(T)) {
                .Int => |i| i.bits,
                .Float => |f| f.bits,
                else => @compileError("T must be integer type or float type"),
            };
        }
    }

    pub inline fn signedness(value: anytype) std.builtin.Signedness {
        if (isZig0d14AndLater) {
            return switch (@typeInfo(@TypeOf(value))) {
                .int => |i| i.signedness,
                .comptime_int => value < 0,
                else => @compileError("value must be int or comptime_int"),
            };
        } else {
            return switch (@typeInfo(@TypeOf(value))) {
                .Int => |i| i.signedness,
                .ComptimeInt => value < 0,
                else => @compileError("value must be int or comptime_int"),
            };
        }
    }

    pub inline fn bitsOfNumber(value: anytype) u16 {
        if (isZig0d14AndLater) {
            return switch (@typeInfo(@TypeOf(value))) {
                .int => |i| i.bits,
                .float => |f| f.bits,
                .comptime_int => std.math.log2IntCeil(comptime_int, value) + (if (value < 0) 2 else 1),
                else => @compileError("value must be int, float or comptime_int"),
            };
        } else {
            return switch (@typeInfo(@TypeOf(value))) {
                .Int => |i| i.bits,
                .Float => |f| f.bits,
                .ComptimeInt => std.math.log2IntCeil(comptime_int, value) + (if (value < 0) 2 else 1),
                else => @compileError("value must be int, float or comptime_int"),
            };
        }
    }
};
