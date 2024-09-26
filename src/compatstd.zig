const std = @import("std");
const builtin = @import("builtin");

pub const mem = struct {
    pub fn writeIntBig(T: type, dst: *[@divExact(@typeInfo(T).Int.bits, 8)]u8, value: T) void {
        if (@hasDecl(std.mem, "writeIntBig")) {
            return std.mem.writeIntBig(T, dst, value);
        }
        return std.mem.writeInt(T, dst, value, .big);
    }

    pub fn readIntBig(T: type, src: *const [@divExact(@typeInfo(T).Int.bits, 8)]u8) T {
        if (@hasDecl(std.mem, "readIntBig")) {
            return std.mem.readIntBig(T, src);
        }
        return std.mem.readInt(T, src, .big);
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
        if (value < 0) {
            return @intCast(-value);
        }
        return @intCast(value);
    }
};
