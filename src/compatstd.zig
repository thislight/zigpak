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
    pub fn AbsCast(T: type) type {
        const inf = @typeInfo(T);
        if (builtin.zig_version.order(.{ .major = 0, .minor = 14, .patch = 0 }).compare(.lt)) {
            return switch (inf) {
                .Int => |oint| @Type(.{
                    .Int = .{
                        .signedness = .unsigned,
                        .bits = if (oint.signedness == .signed) oint.bits - 1 else oint.bits,
                    },
                }),
                .Float => |oflt| @Type(.{ .float = .{
                    .signedness = .unsigned,
                    .bits = oflt.bits,
                } }),
                .ComptimeInt, .ComptimeFloat => T,
                else => @compileError("not a integer type"),
            };
        }
        // New naming convention in 0.14
        return switch (inf) {
            .int => |oint| @Type(.{
                .int = .{
                    .signedness = .unsigned,
                    .bits = if (oint.signedness == .signed) oint.bits - 1 else oint.bits,
                },
            }),
            .float => |oflt| @Type(.{ .float = .{
                .signedness = .unsigned,
                .bits = oflt.bits,
            } }),
            .comptime_int, .comptime_float => T,
            else => @compileError("not a integer type"),
        };
    }

    pub fn absCast(value: anytype) AbsCast(@TypeOf(value)) {
        return @abs(value);
    }
};
