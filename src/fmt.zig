// SPDX: Apache-2.0
// This file is part of zigpak.
const std = @import("std");
const assert = std.debug.assert;
const absCast = std.math.absCast;
const writeIntBig = std.mem.writeIntBig;
const readIntBig = std.mem.readIntBig;
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
const memcpy = std.mem.copyForwards;
const nativeEndian = @import("builtin").cpu.arch.endian();

fn readFloatBig(comptime T: type, src: *const [@divExact(@typeInfo(T).Float.bits, 8)]u8) T {
    const inf = @typeInfo(T).Float;
    if (inf.bits > 64) {
        @compileError("readFloatBig does not support float types have more than 64 bits.");
    }

    if (nativeEndian == .Little) {
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

fn writeFloatBig(comptime T: type, dest: *[@divExact(@typeInfo(T).Float.bits, 8)]u8, val: T) void {
    const inf = @typeInfo(T).Float;
    if (inf.bits > 64) {
        @compileError("writeFloatBig does not support float types have more than 64 bits.");
    }
    memcpy(u8, dest, asBytes(&val));
    if (nativeEndian == .Little) {
        for (0..@divExact(dest.len, 2)) |i| {
            std.mem.swap(u8, &dest[i], &dest[dest.len - i - 1]);
        }
    }
}

/// Write integer [value] as specific type [T], signed or unsigned.
///
/// This function uses type information from [T] to regconise the type in msgpack.
/// If the type is [i64], the [value] is stored as a 64-bit signed integer; if the type is [u24],
/// a 32-bit unsigned is used.
///
/// If you need to use the smallest type depends on the [value], see [writeIntSm].
pub fn writeInt(comptime T: type, dst: []u8, value: T) usize {
    const inf = @typeInfo(T);
    const signed = switch (inf) {
        .Int => |i| i.signedness == .signed,
        .ComptimeInt => value < 0,
        else => @compileError("T must int or comptime_int"),
    };
    const bits = switch (inf) {
        .Int => |i| i.bits,
        .ComptimeInt => log2IntCeil(comptime_int, value) + (if (value < 0) 2 else 1),
        else => unreachable,
    };
    if (bits > 64) {
        @compileError("the max integer size is 64 bits");
    }
    // TODO: reduce the generated size by move common logic to another function.
    const roundedBytes = if (signed) switch (bits) {
        0...6 => 0,
        6...8 => 1,
        8...16 => 2,
        16...32 => 4,
        32...64 => 8,
    } else switch (bits) {
        0...7 => 0,
        7...8 => 1,
        8...16 => 2,
        16...32 => 4,
        32...64 => 8,
    };
    const header = if (signed and value < 0) switch (roundedBytes) {
        0 => 0b11100000 | (0b00011111 & absCast(value)),
        1, 2, 4, 8 => 0xd0 + (roundedBytes - 1),
        else => unreachable,
    } else switch (roundedBytes) {
        0 => 0b01111111 & value,
        1, 2, 4, 8 => 0xcc + (roundedBytes - 1),
        else => unreachable,
    };
    dst[0] = header;
    if (roundedBytes == 0) {
        return 1;
    }
    const writtenType = @Type(.{ .Int = .{
        .signedness = if (signed) .signed else .unsigned,
        .bits = roundedBytes * 8,
    } });
    writeIntBig(writtenType, dst[1..roundedBytes], @as(writtenType, value));
    return 1 + roundedBytes;
}

/// Write the integer [value] use the smallest type.
pub fn writeIntSm(comptime T: type, dst: []u8, value: T) usize {
    if (value < 0) {
        return switch (value) {
            -0b00011111...-1 => writeInt(i6, dst, value),
            minInt(i8)...-0b00100000 => writeInt(i8, dst, value),
            minInt(i16)...minInt(i8) - 1 => writeInt(i16, dst, value),
            minInt(i32)...minInt(i16) - 1 => writeInt(i32, dst, value),
            minInt(i64)...minInt(i32) - 1 => writeInt(i64, dst, value),
            else => unreachable,
        };
    } else {
        return switch (value) {
            0...0b01111111 => writeInt(u7, dst, value),
            0b10000000...maxInt(u8) => writeInt(u8, dst, value),
            maxInt(u8) + 1...maxInt(u16) => writeInt(u16, dst, value),
            maxInt(u16) + 1...maxInt(u32) => writeInt(u32, dst, value),
            maxInt(u32) + 1...maxInt(u64) => writeInt(u64, dst, value),
            else => unreachable,
        };
    }
}

pub fn writeFloat(comptime T: type, dst: []u8, value: T) usize {
    const inf = @typeInfo(T);
    const roundedBytes = switch (inf) {
        .Float => |flt| switch (flt.bits) {
            0...32 => 4,
            33...64 => 8,
            else => @compileError(comptimePrint("unsupported {}", .{@typeName(T)})),
        },
        else => @compileError(comptimePrint("unsuuported {}", .{@typeName(T)})),
    };
    dst[0] = switch (roundedBytes) {
        4 => 0xca,
        8 => 0xcb,
        else => unreachable,
    };
    switch (roundedBytes) {
        4 => writeFloatBig(f32, dst[1..5], value),
        8 => writeFloatBig(f64, dst[1..9], value),
        else => unreachable,
    }
    return 1 + roundedBytes;
}

pub fn writeNil(dst: []u8) usize {
    dst[0] = 0xc0;
    return 1;
}

test "writeNil" {
    const t = std.testing;
    var buf: [1]u8 = .{0};
    const size = writeNil(&buf);
    try t.expectEqual(@as(usize, 1), size);
    try t.expectEqual(@as(u8, 0xc0), buf[0]);
}

pub fn writeBool(dst: []u8, value: bool) usize {
    dst[0] = switch (value) {
        true => 0xc3,
        false => 0xc2,
    };
    return 1;
}

pub const Prefix = struct {
    data: [6]u8,
    len: usize,

    pub fn toSlice(self: *const Prefix) []const u8 {
        return self.data[0..self.len];
    }
};

pub fn prefixString(len: u32) Prefix {
    switch (len) {
        0...0b00011111 => {
            const prefix = [5]u8{ 0b10100000 | (0b00011111 & @as(u8, @intCast(len))), 0, 0, 0, 0 };
            return .{ .data = prefix, .len = 1 };
        },
        0b00011111 + 1...maxInt(u8) => {
            const prefix = [5]u8{ 0xd9, @as(u8, @intCast(len)), 0, 0, 0 };
            return .{ .data = prefix, .len = 2 };
        },
        maxInt(u8)...maxInt(u16) => {
            var prefix = [5]u8{ 0xda, 0, 0, 0, 0 };
            writeIntBig(u16, prefix[1..3], @intCast(len));
            return .{ .data = prefix, .len = 3 };
        },
        maxInt(u16)...maxInt(u32) => {
            var prefix = [5]u8{ 0xdb, 0, 0, 0, 0 };
            writeIntBig(u32, prefix[1..5], @intCast(len));
            return .{ .data = prefix, .len = 5 };
        },
    }
}

pub fn prefixBinary(len: u32) Prefix {
    switch (len) {
        0...maxInt(u8) => {
            const prefix = [5]u8{ 0xc4, @as(u8, @intCast(len)), 0, 0, 0 };
            return .{ .data = prefix, .len = 2 };
        },
        maxInt(u8)...maxInt(u16) => {
            var prefix = [5]u8{ 0xc5, 0, 0, 0, 0 };
            writeIntBig(u16, prefix[1..3], @intCast(len));
            return .{ .data = prefix, .len = 3 };
        },
        maxInt(u16)...maxInt(u32) => {
            var prefix = [5]u8{ 0xc6, 0, 0, 0, 0 };
            writeIntBig(u32, prefix[1..5], @intCast(len));
            return .{ .data = prefix, .len = 5 };
        },
    }
}

/// Generate a array prefix for `len`.
pub fn prefixArray(len: u32) Prefix {
    switch (len) {
        0...0b00001111 => {
            const prefix = [_]u8{ 0b10010000 | (0b00001111 & @as(u8, @intCast(len))), 0, 0, 0, 0, 0 };
            return .{ .data = prefix, .len = 1 };
        },
        (0b00001111 + 1)...maxInt(u16) => {
            const prefix = [_]u8{ 0xdc, @as(u16, @intCast(len)), 0, 0, 0, 0 };
            return .{ .data = prefix, .len = 3 };
        },
        maxInt(u16) + 1...maxInt(u32) => {
            var prefix = [_]u8{ 0xdd, 0, 0, 0, 0, 0 };
            writeIntBig(u32, prefix[1..5], @intCast(len));
            return .{ .data = prefix, .len = 5 };
        },
    }
}

pub fn prefixMap(len: u32) Prefix {
    switch (len) {
        0...0b00001111 => {
            const prefix = [_]u8{ 0b10000000 | (0b00001111 & @as(u8, @intCast(len))), 0, 0, 0, 0, 0 };
            return .{ .data = prefix, .len = 1 };
        },
        (0b00001111 + 1)...maxInt(u16) => {
            const prefix = [_]u8{ 0xde, @as(u16, @intCast(len)), 0, 0, 0, 0 };
            return .{ .data = prefix, .len = 3 };
        },
        maxInt(u16) + 1...maxInt(u32) => {
            var prefix = [_]u8{ 0xdf, 0, 0, 0, 0, 0 };
            writeIntBig(u32, prefix[1..5], @intCast(len));
            return .{ .data = prefix, .len = 5 };
        },
    }
}

pub fn prefixExt(len: u32, extype: i8) Prefix {
    switch (len) {
        1, 2, 4, 8, 16 => |b| {
            const prefix = [6]u8{ 0xd4 + log2(b), asBytes(&extype)[0], 0, 0, 0, 0 };
            return .{ .data = prefix, .len = 2 };
        },
        0...maxInt(u8) => {
            const prefix = [_]u8{ 0xc7, @intCast(len), asBytes(&extype)[0], 0, 0, 0 };
            return .{ .data = prefix, .len = 3 };
        },
        maxInt(u8) + 1...maxInt(u16) => {
            var prefix = [_]u8{ 0xc8, 0, 0, asBytes(&extype)[0], 0, 0, 0 };
            writeIntBig(u16, prefix[1..3], @intCast(len));
            return .{ .data = prefix, .len = 4 };
        },
        maxInt(u16) + 1...maxInt(u32) => {
            var prefix = [_]u8{ 0xc9, 0, 0, 0, 0, asBytes(&extype)[0] };
            writeIntBig(u16, prefix[1..5], @intCast(len));
            return .{ .data = prefix, .len = 6 };
        },
    }
}

pub fn ReadNextResult(comptime T: type) type {
    return struct {
        bsize: usize,
        value: T,
    };
}

pub const ReadError = error{
    BadType,
};

const ReadNextError = ReadError || Allocator.Error;

/// Read the next value as type [T] from [src].
///
/// This function assume the start of [src] has a complete value to be read,
/// and the length of [src] is not verified before reading.
///
/// Errors
/// - [ReadNextError.BadType]: the type of the value could not be regconised as T.
/// - [ReadNextError.OutOfMemory]: the specific type could not store the value.
fn readNext(comptime T: type, src: []const u8) ReadNextError!ReadNextResult(T) {
    const vType = src[0];
    const inf = @typeInfo(T);
    switch (inf) {
        .Int => |i| {
            if (vType & 0b10000000 == 0) {
                // positive fixed int
                const v = vType & 0b01111111;
                return .{
                    .bsize = 1,
                    .value = v,
                };
            }
            if (vType & 0b11100000 == 0b11100000) {
                // negative fixed int
                if (i.signedness == .unsigned) {
                    return ReadError.BadType;
                }
                const v: T = @intCast(vType & 0b00011111);
                return .{
                    .bsize = 1,
                    .value = -v,
                };
            }
            switch (vType) {
                0xcc, 0xcd, 0xce, 0xcf => { // unsigned int
                    const bsize = pow(usize, 2, vType - 0xcc);
                    if (i.bits < (bsize * 8) or (i.signedness == .signed and i.bits == (bsize * 8))) {
                        // to store the unsigned int, the signed int must have 1 more bit
                        return ReadNextError.OutOfMemory;
                    }
                    const value: u64 = switch (bsize) {
                        1 => src[1],
                        2 => readIntBig(u16, src[1..3]),
                        4 => readIntBig(u32, src[1..5]),
                        8 => readIntBig(u64, src[1..9]),
                        else => unreachable,
                    };
                    return .{
                        .bsize = bsize + 1,
                        .value = @intCast(value),
                    };
                },
                0xd0, 0xd1, 0xd2, 0xd3 => { // signed int
                    const bsize = pow(usize, 2, vType - 0xd0);
                    if (i.bits < (bsize * 8)) {
                        return ReadNextError.OutOfMemory;
                    }
                    const value = switch (bsize) {
                        1 => readIntBig(i8, src[1..2]),
                        2 => readIntBig(i16, src[1..3]),
                        4 => readIntBig(i32, src[1..5]),
                        8 => readIntBig(i64, src[1..9]),
                        else => unreachable,
                    };
                    if (i.signedness == .unsigned and value < 0) {
                        return ReadError.BadType;
                    }
                    return .{
                        .bsize = bsize + 1,
                        .value = @intCast(value),
                    };
                },
                else => return ReadError.BadType,
            }
        },
        .Optional => |option| {
            if (vType == 0xc0) {
                return .{
                    .bsize = 1,
                    .value = null,
                };
            }
            return readNext(option.child, src);
        },
        .Bool => {
            const value = switch (vType) {
                0xc2 => false,
                0xc3 => true,
                else => return ReadError.BadType,
            };
            return .{
                .bsize = 1,
                .value = value,
            };
        },
        .Float => |float| {
            const requiredBytes: usize = switch (vType) {
                0xca => 4,
                0xcb => 8,
                else => return ReadError.BadType,
            };
            if (requiredBytes > @divTrunc(float.bits, 8)) {
                return ReadNextError.OutOfMemory;
            }
            const value = switch (vType) {
                0xca => readFloatBig(f32, src[1..5]),
                0xcb => readFloatBig(f64, src[1..9]),
                else => unreachable,
            };
            return .{
                .bsize = 1 + requiredBytes,
                .value = @as(T, value),
            };
        },
        .Struct => switch (T) {
            Value.LazyArray => {
                const csize = if (vType & 0b11110000 == 0b10010000) vType & 0b00001111 else switch (vType) {
                    0xdc => readIntBig(u16, src[1 .. 1 + 2]),
                    0xdd => readIntBig(u32, src[1 .. 1 + 4]),
                    else => return ReadError.BadType,
                };
                const iter: Value.LazyArray = .{
                    .itemNumber = csize,
                };
                return .{
                    .bsize = switch (vType) {
                        0xdc => 1 + 2,
                        0xdd => 1 + 4,
                        else => 1,
                    },
                    .value = iter,
                };
            },
            Value.LazyMap => {
                const csize = if (vType & 0b11110000 == 0b10000000) vType & 0b00001111 else switch (vType) {
                    0xde => readIntBig(u16, src[1 .. 1 + 2]),
                    0xdf => readIntBig(u32, src[1 .. 1 + 4]),
                    else => return ReadError.BadType,
                };
                const iter: Value.LazyMap = .{
                    .itemNumber = csize,
                };
                return .{
                    .bsize = switch (vType) {
                        0xdc => 1 + 2,
                        0xdd => 1 + 4,
                        else => 1,
                    },
                    .value = iter,
                };
            },
            Value.Ext => {
                switch (vType) {
                    0xd4, 0xd5, 0xd6, 0xd7, 0xd8 => {
                        // fixed length: 1 - 16
                        const bsize = pow(usize, 2, vType - 0xd4);
                        const extype = readIntBig(i8, src[1..2]);
                        const data = src[2 .. 2 + bsize];
                        return .{ .bsize = 2 + bsize, .value = .{
                            .extype = extype,
                            .data = data,
                        } };
                    },
                    0xc7, 0xc8, 0xc9 => {
                        // variable length: 8 bits - 32 bits length
                        const bsizeLen = pow(usize, 2, vType - 0xc7);
                        const bsizeData = src[1 .. 1 + bsizeLen];
                        const bsize: usize = @intCast(switch (bsizeLen) {
                            1 => readIntBig(u8, bsizeData[0..1]),
                            2 => readIntBig(u16, bsizeData[0..2]),
                            4 => readIntBig(u32, bsizeData[0..4]),
                            else => unreachable,
                        });
                        const extype = readIntBig(i8, src[1 + bsizeLen ..][0..1]);
                        const data = src[2 + bsizeLen .. 2 + bsizeLen + bsize];
                        return .{ .bsize = 2 + bsizeLen + bsize, .value = .{
                            .extype = extype,
                            .data = data,
                        } };
                    },
                    else => unreachable,
                }
            },
            Value => switch (try readValue(src)) {
                .Incomplete => unreachable,
                .Value => |ret| .{
                    .value = ret.value,
                    .bsize = ret.bsize,
                },
            },
            else => @compileError(comptimePrint("unsupported {}", .{@typeName(T)})),
        },
        .Pointer => |pointer| if (pointer.size == .Slice and pointer.is_const and pointer.child == u8) {
            // raw binary or string
            const bsizeBytes: usize = if (vType & 0b11100000 == 0b10100000) 0 else switch (vType) {
                0xc4, 0xd9 => 1,
                0xc5, 0xda => 2,
                0xc6, 0xdb => 4,
                else => unreachable,
            };
            const rest = src[1..];
            const bsize: usize = @intCast(if (bsizeBytes > 0) switch (bsizeBytes) {
                1 => readIntBig(u8, rest[0..1]),
                2 => readIntBig(u16, rest[0..2]),
                4 => readIntBig(u32, rest[0..4]),
                else => unreachable,
            } else vType & 0b00011111);
            const value = rest[bsizeBytes .. bsizeBytes + bsize];
            return .{
                .bsize = 1 + bsizeBytes + bsize,
                .value = value,
            };
        } else @compileError(comptimePrint("unsupported {}", .{@typeName(T)})),
        else => @compileError(comptimePrint("unsupported {}", .{@typeName(T)})),
    }
}

pub const ValueType = enum {
    Int,
    UInt,
    Nil,
    Bool,
    Float,
    String,
    Binary,
    Array,
    Map,
    Ext,
};

/// A msgpack value, dynamic typed.
///
/// This type costs the larger one of `2 x usize` or 64 bits.
/// It might be 128 bits on a 64-bit platform or 64 bits on a 32-bit.
///
/// Msgpack supports 64-bit signed or unsigned integer, so the integers is separated to
/// `Int` and `UInt` for signed and unsigned. Please keep in mind when handling integers.
pub const Value = union(ValueType) {
    Int: i64,
    UInt: u64,
    Nil: void,
    Bool: bool,
    Float: f64,
    String: []const u8,
    Binary: []const u8,
    Array: LazyArray,
    Map: LazyMap,
    Ext: Ext,

    /// The iterator for the array. Use [next] or [nextOf] function to read next value.
    ///
    /// Example
    ///
    /// ````zig
    /// var array: LazyArray;
    /// var src: []const u8;
    ///
    /// while (array.nextOf(u32, src)) |item| {
    ///     doSomething(item);
    ///     src = src[item.bsize..];
    /// }
    /// ````
    pub const LazyArray = struct {
        itemNumber: u32,
        nowIdx: u32 = 0,

        pub fn Next(comptime T: type) type {
            return union(enum) { Incomplete: usize, Value: struct { bsize: usize, value: T, idx: u32 } };
        }

        /// Get the next value as the specific type.
        pub fn nextOf(self: *LazyArray, comptime T: type, src: []const u8) ReadError!?Next(T) {
            if (!self.hasNext()) return null;
            // FIXME: check bounds
            const result = try readNext(T, src);
            const oidx = self.nowIdx;
            self.nowIdx += 1;
            return .{ .Value = .{
                .bsize = result.bsize,
                .value = result.value,
                .idx = oidx,
            } };
        }

        pub fn next(self: *LazyArray, src: []const u8) ReadError!?Next(Value) {
            if (!self.hasNext()) return null;
            const result = try readValue(src);
            switch (result) {
                .Incomplete => |bsize| return .{ .Incomplete = bsize },
                .Value => |v| {
                    const oidx = self.nowIdx;
                    self.nowIdx += 1;
                    return .{ .Value = .{
                        .bsize = v.bsize,
                        .value = v.value,
                        .idx = oidx,
                    } };
                },
            }
        }

        pub fn reset(self: *LazyArray) void {
            self.nowIdx = 0;
        }

        pub fn hasNext(self: *const LazyArray) bool {
            return self.itemNumber > self.nowIdx;
        }
    };

    pub const LazyMap = struct {
        itemNumber: u32,
        nowIdx: u32 = 0,

        pub fn Next(comptime K: type, comptime V: type) type {
            return union(enum) { Incomplete: usize, Value: struct {
                bsize: usize,
                key: K,
                value: V,
                idx: u32,
            } };
        }

        pub fn nextOf(self: *LazyMap, comptime K: type, comptime V: type, src: []const u8) !?Next(K, V) {
            if (!self.hasNext()) return null;
            const kNeedBytes = try boundCheck(src);
            if (kNeedBytes > 0) {
                return .{ .Incomplete = kNeedBytes };
            }
            const key = try readNext(K, src);
            const rest = src[key.bsize..];
            const vNeedBytes = boundCheck(rest);
            if (vNeedBytes > 0) {
                return .{ .Incomplete = vNeedBytes };
            }
            const value = try readNext(V, rest);
            const oidx = self.nowIdx;
            self.nowIdx += 1;
            return .{ .Value = .{
                .bsize = key.bsize + value.bsize,
                .key = key.value,
                .value = value.value,
                .idx = oidx,
            } };
        }

        pub fn next(self: *LazyMap, src: []const u8) !?Next(Value, Value) {
            if (!self.hasNext()) return null;
            const key = switch (try readValue(src)) {
                .Incomplete => |bsize| return .{ .Incomplete = bsize },
                .Value => |ret| ret,
            };
            const value = switch (try readValue(src[key.bsize..])) {
                .Incomplete => |bsize| return .{ .Incomplete = bsize },
                .Value => |ret| ret,
            };
            const oidx = self.nowIdx;
            self.nowIdx += 1;
            return .{ .Value = .{
                .bsize = key.bsize + value.bsize,
                .key = key.value,
                .value = value.value,
                .idx = oidx,
            } };
        }

        pub fn hasNext(self: *const LazyMap) bool {
            return self.itemNumber > self.nowIdx;
        }
    };

    pub const Ext = struct {
        extype: i8,
        data: []const u8,
    };
};

pub const MsgPakType = enum {
    Nil,
    BoolFalse,
    BoolTrue,
    FixedIntNegative,
    FixedIntPositive,
    Int8,
    Int16,
    Int32,
    Int64,
    UInt8,
    UInt16,
    UInt32,
    UInt64,
    Float32,
    Float64,
    FixedStr,
    Str8,
    Str16,
    Str32,
    Bin8,
    Bin16,
    Bin32,
    FixedArray,
    Array16,
    Array32,
    FixedMap,
    Map16,
    Map32,
    FixedExt1,
    FixedExt2,
    FixedExt4,
    FixedExt8,
    FixedExt16,
    Ext8,
    Ext16,
    Ext32,

    const Self = @This();

    pub fn isBool(self: Self) bool {
        return switch (self) {
            .BoolFalse, .BoolTrue => true,
            else => false,
        };
    }

    pub fn isInt(self: Self) bool {
        return switch (self) {
            .FixedIntPositive, .FixedIntNegative, .Int8, .Int16, .Int32, .Int64 => true,
            else => false,
        };
    }

    pub fn isUInt(self: Self) bool {
        return switch (self) {
            .FixedIntPositive, .UInt8, .UInt16, .UInt32, .UInt64 => true,
            else => false,
        };
    }

    pub fn isAnyInt(self: Self) bool {
        return self.isInt() or self.isUInt();
    }

    pub fn isFloat(self: Self) bool {
        return switch (self) {
            .Float32, .Float64 => true,
            else => false,
        };
    }

    pub fn isStr(self: Self) bool {
        return switch (self) {
            .FixedStr, .Str8, .Str16, .Str32 => true,
            else => false,
        };
    }

    pub fn isBin(self: Self) bool {
        return switch (self) {
            .Bin8, .Bin16, .Bin32 => true,
            else => false,
        };
    }

    pub fn isArray(self: Self) bool {
        return switch (self) {
            .FixedArray, .Array16, .Array32 => true,
            else => false,
        };
    }

    pub fn isMap(self: Self) bool {
        return switch (self) {
            .FixedMap, .Map16, .Map32 => true,
            else => false,
        };
    }

    pub fn isExt(self: Self) bool {
        return switch (self) {
            .FixedExt1, .FixedExt2, .FixedExt4, .FixedExt8, .FixedExt16, .Ext8, .Ext16, .Ext32 => true,
            else => false,
        };
    }

    /// Convert to [ValueType].
    ///
    /// Fixed integers is signed as in type, but we decide to use best-matched type for the value.
    /// Positive fixed int is regconised as unsgined int and the negative is regconised as signed.
    pub fn toValueType(self: Self) ValueType {
        return switch (self) {
            .Nil => .Nil,
            .BoolFalse, .BoolTrue => .Bool,
            .FixedIntNegative, .Int8, .Int16, .Int32, .Int64 => .Int,
            .FixedIntPositive, .UInt8, .UInt16, .UInt32, .UInt64 => .UInt,
            .Float32, .Float64 => .Float,
            .FixedStr, .Str8, .Str16, .Str32 => .String,
            .Bin8, .Bin16, .Bin32 => .Binary,
            .FixedArray, .Array16, .Array32 => .Array,
            .FixedMap, .Map16, .Map32 => .Map,
            .FixedExt1, .FixedExt2, .FixedExt4, .FixedExt8, .FixedExt16, .Ext8, .Ext16, .Ext32 => .Ext,
        };
    }
};

pub fn peek(i: u8) ?MsgPakType {
    // Check fixed size types first
    if (i & 0b10000000 == 0) {
        return .FixedIntPositive;
    }
    if (i & 0b11100000 == 0b11100000) {
        return .FixedIntNegative;
    }
    if (i & 0b11100000 == 0b10100000) {
        return .FixedStr;
    }
    if (i & 0b11110000 == 0b10010000) {
        return .FixedArray;
    }
    if (i & 0b11110000 == 0b10000000) {
        return .FixedMap;
    }
    return switch (i) {
        0xc0 => .Nil,
        0xc2 => .BoolFalse,
        0xc3 => .BoolTrue,
        0xc4 => .Bin8,
        0xc5 => .Bin16,
        0xc6 => .Bin32,
        0xc7 => .Ext8,
        0xc8 => .Ext16,
        0xc9 => .Ext32,
        0xca => .Float32,
        0xcb => .Float64,
        0xcc => .UInt8,
        0xcd => .UInt16,
        0xce => .UInt32,
        0xcf => .UInt64,
        0xd0 => .Int8,
        0xd1 => .Int16,
        0xd2 => .Int32,
        0xd3 => .Int64,
        0xd4 => .FixedExt1,
        0xd5 => .FixedExt2,
        0xd6 => .FixedExt4,
        0xd7 => .FixedExt8,
        0xd8 => .FixedExt16,
        0xd9 => .Str8,
        0xda => .Str16,
        0xdb => .Str32,
        0xdc => .Array16,
        0xdd => .Array32,
        0xde => .Map16,
        0xdf => .Map32,
        else => null,
    };
}

pub const ReadValueResult = union(enum) {
    Incomplete: usize,
    Value: ReadValue,

    pub const ReadValue = struct {
        value: Value,
        bsize: usize,
    };
};

fn readNextValue(comptime T: type, comptime vType: ValueType, src: []const u8) ReadValueResult {
    const item = readNext(T, src) catch unreachable;
    const value = @unionInit(Value, @tagName(vType), item.value);
    return .{ .Value = .{
        .value = value,
        .bsize = item.bsize,
    } };
}

/// Do bound checking on a possible msgpack value in [src].
///
/// If the type could not recongonised, [ReadError.BadType] will be returned.
fn boundCheck(src: []const u8) ReadError!usize {
    if (src.len == 0) {
        return 1;
    }
    const vtypepeek = peek(src[0]) orelse return ReadError.BadType;
    const vtype = vtypepeek.toValueType();
    switch (vtype) {
        .String, .Binary, .Ext => {
            const olsize: usize = switch (vtypepeek) {
                .FixedStr, .FixedExt1, .FixedExt2, .FixedExt4, .FixedExt8, .FixedExt16 => 0,
                .Bin8, .Str8, .Ext8 => 1,
                .Bin16, .Str16, .Ext16 => 2,
                .Bin32, .Str32, .Ext32 => 4,
                else => unreachable,
            };
            const lsize = 1 + olsize;
            if (src.len < lsize) {
                return lsize - src.len;
            }
            const extTypeSize: usize = if (vtype == .Ext) 1 else 0;
            const cBytes: usize = switch (vtypepeek) {
                .FixedExt1 => 1,
                .FixedExt2 => 2,
                .FixedExt4 => 4,
                .FixedExt8 => 8,
                .FixedExt16 => 16,
                .FixedStr => 0b00011111 & src[0],
                .Ext8, .Bin8, .Str8 => src[1],
                .Ext16, .Bin16, .Str16 => readIntBig(u16, src[1..3]),
                .Ext32, .Bin32, .Str32 => readIntBig(u32, src[1..5]),
                else => unreachable,
            } + lsize + extTypeSize;
            if (src.len < cBytes) {
                return cBytes - src.len;
            }
        },
        .Int, .UInt, .Float => {
            const orBytes: usize = switch (vtypepeek) {
                .FixedIntNegative, .FixedIntPositive => 0,
                .Int8, .UInt8 => 1,
                .Int16, .UInt16 => 2,
                .Int32, .UInt32, .Float32 => 4,
                .Int64, .UInt64, .Float64 => 8,
                else => unreachable,
            };
            const rBytes = orBytes + 1;
            if (src.len < rBytes) {
                return rBytes - src.len;
            }
        },
        .Array, .Map => {
            // only check for length for array and map, since they are evaluated lazily.
            const orBytes: usize = switch (vtypepeek) {
                .FixedArray, .FixedMap => 0,
                .Array16, .Map16 => 2,
                .Array32, .Map32 => 4,
                else => unreachable,
            };
            const rBytes = orBytes + 1;
            if (src.len < rBytes) {
                return rBytes - src.len;
            }
        },
        else => {},
    }
    return 0;
}

pub fn readValue(src: []const u8) ReadError!ReadValueResult {
    const bytesNeeded = try boundCheck(src);
    if (bytesNeeded > 0) {
        return .{ .Incomplete = bytesNeeded };
    }
    const vtype = (peek(src[0]) orelse unreachable).toValueType();
    return switch (vtype) {
        .Nil => .{ .Value = .{ .value = .Nil, .bsize = 1 } },
        .Bool => readNextValue(bool, .Bool, src),
        .Int => readNextValue(i64, .Int, src),
        .UInt => readNextValue(u64, .UInt, src),
        .Float => readNextValue(f64, .Float, src),
        .String => readNextValue([]const u8, .String, src),
        .Binary => readNextValue([]const u8, .Binary, src),
        .Array => readNextValue(Value.LazyArray, .Array, src),
        .Map => readNextValue(Value.LazyMap, .Map, src),
        .Ext => readNextValue(Value.Ext, .Ext, src),
    };
}

test "readValue nil" {
    const t = std.testing;
    const data = [_]u8{0xc0};
    const result = try readValue(&data);
    try t.expect(result == .Value);
    const v = result.Value;
    try t.expect(v.value == .Nil);
    try t.expect(v.bsize == 1);
}

test "readValue bool" {
    const t = std.testing;
    const values = [_]u8{ 0xc2, 0xc3 };
    const result = try readValue(&values);
    try t.expect(result == .Value);
    const vF = result.Value;
    try t.expect(vF.value == .Bool);
    try t.expect(vF.value.Bool == false);

    const result1 = try readValue(values[vF.bsize..]);
    try t.expect(result1 == .Value);
    const vT = result1.Value;
    try t.expect(vT.value == .Bool);
    try t.expect(vT.value.Bool == true);
}

test "readValue array length fixed" {
    const t = std.testing;
    const values = [_]u8{ 0b10010000 | (0b00001111 & 2), 0xc0, 0xc0 };
    const result = try readValue(&values);
    try t.expect(result == .Value);
    const v = result.Value;
    try t.expect(v.bsize == 1); // length is fixed into the type
    try t.expect(v.value == .Array);
    var iter = v.value.Array;

    var i: usize = 0;
    var offset = v.bsize;
    while (try iter.next(values[offset..])) |item| {
        i += 1;
        try t.expect(item == .Value);
        const itemValue = item.Value.value;
        try t.expect(itemValue == .Nil);
        offset += item.Value.bsize;
    }
    try t.expectEqual(@as(usize, 2), i);
}

test "readValue array variable length 16 bits" {
    const t = std.testing;
    const part0 = [_]u8{ 0xdc, 0 };
    var values = [_]u8{ 0xdc, 0, 0, 0xc0, 0xc0 };
    writeIntBig(u16, values[1..3], 2);
    {
        const result = try readValue(&part0);
        try t.expect(result == .Incomplete);
        try t.expectEqual(@as(usize, 1), result.Incomplete);
    }
    {
        const result = try readValue(&values);
        try t.expect(result == .Value);
        const read = result.Value;
        try t.expectEqual(@as(usize, 3), read.bsize);
        try t.expect(read.value == .Array);
        var iter = read.value.Array;
        var i: usize = 0;
        var offset = read.bsize;
        while (try iter.next(values[offset..])) |item| {
            i += 1;
            try t.expect(item == .Value);
            const value = item.Value.value;
            try t.expect(value == .Nil);
            offset += item.Value.bsize;
        }
        try t.expectEqual(@as(usize, 2), i);
    }
}

test "readValue array variable length 32 bits" {
    const t = std.testing;
    const part0 = [_]u8{ 0xdd, 0, 0, 0 };
    var values = [_]u8{ 0xdd, 0, 0, 0, 0, 0xc0, 0xc0 };
    writeIntBig(u32, values[1..5], 2);
    {
        const result = try readValue(&part0);
        try t.expect(result == .Incomplete);
        try t.expectEqual(@as(usize, 1), result.Incomplete);
    }
    {
        const result = try readValue(&values);
        try t.expect(result == .Value);
        const read = result.Value;
        try t.expectEqual(@as(usize, 5), read.bsize);
        try t.expect(read.value == .Array);
        var iter = read.value.Array;
        var i: usize = 0;
        var offset = read.bsize;
        while (try iter.next(values[offset..])) |item| {
            i += 1;
            try t.expect(item == .Value);
            const value = item.Value.value;
            try t.expect(value == .Nil);
            offset += item.Value.bsize;
        }
        try t.expectEqual(@as(usize, 2), i);
    }
}
