// SPDX: Apache-2.0
// This file is part of zigpak.

const std = @import("std");
const compatstd = @import("./compatstd.zig");
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

fn makeFixIntPos(value: u7) u8 {
    return ~ContainerType.MASK_FIXED_INT_POSITIVE & value;
}

fn makeFixIntNeg(value: i6) u8 {
    return @intFromEnum(ContainerType.fixed_int_negative) | ~ContainerType.MASK_FIXED_INT_NEGATIVE & @as(u8, @intCast(@abs(value)));
}

/// Write integer `value` as specific type `T`, signed or unsigned.
///
/// This function uses type information from `T` to recognise the type in msgpack.
/// If the type is `i64`, the `value` is stored as a 64-bit signed integer; if the type is `u24`,
/// a 32-bit unsigned is used.
///
/// If you need to use the smallest type depends on the `value`, see `writeIntSm`.
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
        7...8 => 1,
        9...16 => 2,
        17...32 => 4,
        33...64 => 8,
        else => unreachable,
    } else switch (bits) {
        0...7 => 0,
        8 => 1,
        9...16 => 2,
        17...32 => 4,
        33...64 => 8,
        else => unreachable,
    };
    const tier = switch (roundedBytes) {
        0, 1 => 0,
        2 => 1,
        4 => 2,
        8 => 3,
        else => unreachable,
    };
    const header: u8 = if (signed) switch (roundedBytes) {
        0 => makeFixIntNeg(@intCast(value)),
        1, 2, 4, 8 => 0xd0 + tier,
        else => unreachable,
    } else switch (roundedBytes) {
        0 => makeFixIntPos(@intCast(value)),
        1, 2, 4, 8 => 0xcc + tier,
        else => unreachable,
    };
    dst[0] = header;
    if (roundedBytes == 0) {
        return 1;
    }
    const writtenType = std.meta.Int(if (signed) .signed else .unsigned, roundedBytes * 8);
    writeIntBig(writtenType, dst[1 .. roundedBytes + 1], @as(writtenType, value));
    return 1 + roundedBytes;
}

/// Write the integer `value` with the smallest type.
///
/// The value must can be represented in 64 bits
/// (signed or unsigned), or the behaviour is undefined.
///
/// This function checks in runtime to use smallest messagepack type to
/// store the value.
pub fn writeIntSm(comptime T: type, dst: []u8, value: T) usize {
    if (value >= 0) {
        if (value >= 0 and value <= 0b01111111) {
            return writeInt(u7, dst, @intCast(value));
        } else if (value <= maxInt(u8)) {
            return writeInt(u8, dst, @intCast(value));
        } else if (value <= maxInt(u16)) {
            return writeInt(u16, dst, @intCast(value));
        } else if (value <= maxInt(u32)) {
            return writeInt(u32, dst, @intCast(value));
        } else if (value <= maxInt(u64)) {
            return writeInt(u64, dst, @intCast(value));
        }
    } else {
        if (value >= -0b00011111) {
            return writeInt(i6, dst, @intCast(value));
        } else if (value >= minInt(i8)) {
            return writeInt(i8, dst, @intCast(value));
        } else if (value >= minInt(i16)) {
            return writeInt(i16, dst, @intCast(value));
        } else if (value >= minInt(i32)) {
            return writeInt(i32, dst, @intCast(value));
        } else if (value >= minInt(i64)) {
            return writeInt(i64, dst, @intCast(value));
        }
    }
    unreachable;

    // if (value < 0) {
    //     return switch (value) {
    //         -0b00011111...-1 => writeInt(i6, dst, @intCast(value)),
    //         minInt(i8)...-0b00100000 => writeInt(i8, dst, @intCast(value)),
    //         minInt(i16)...minInt(i8) - 1 => writeInt(i16, dst, @intCast(value)),
    //         minInt(i32)...minInt(i16) - 1 => writeInt(i32, dst, @intCast(value)),
    //         minInt(i64)...minInt(i32) - 1 => writeInt(i64, dst, @intCast(value)),
    //         else => unreachable,
    //     };
    // } else {
    //     return switch (value) {
    //         0...0b01111111 => writeInt(u7, dst, @intCast(value)),
    //         0b10000000...maxInt(u8) => writeInt(u8, dst, @intCast(value)),
    //         maxInt(u8) + 1...maxInt(u16) => writeInt(u16, dst, @intCast(value)),
    //         maxInt(u16) + 1...maxInt(u32) => writeInt(u32, dst, @intCast(value)),
    //         maxInt(u32) + 1...maxInt(u64) => writeInt(u64, dst, @intCast(value)),
    //         else => unreachable,
    //     };
    // }
}

/// Write the float `value` as specific type `T`.
///
/// This function uses `T` to recognise the type for messagepack.
/// For example: If `T` is `f64`, the value is stored as 64-bit float;
/// if `T` is `f16`, the value is stored as 32-bit float.
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

/// Write nil into the `dst`.
pub fn writeNil(dst: []u8) usize {
    dst[0] = 0xc0;
    return 1;
}

test writeNil {
    const t = std.testing;
    var buf: [1]u8 = .{0};
    const size = writeNil(&buf);
    try t.expectEqual(@as(usize, 1), size);
    try t.expectEqual(@as(u8, 0xc0), buf[0]);
}

/// Write bool into the `dst`
pub fn writeBool(dst: []u8, value: bool) usize {
    dst[0] = switch (value) {
        true => 0xc3,
        false => 0xc2,
    };
    return 1;
}

/// The prefix for a value.
///
/// This is the header to be stored before the actual value.
pub const Prefix = std.BoundedArray(u8, 6);

/// Generate a string prefix.
pub inline fn prefixString(len: u32) Prefix {
    var result: Prefix = .{};
    switch (len) {
        0...0b00011111 => {
            result.appendAssumeCapacity(0b10100000 | (0b00011111 & @as(u8, @intCast(len))));
        },
        0b00011111 + 1...maxInt(u8) => {
            result.appendAssumeCapacity(0xd9);
            result.appendAssumeCapacity(@intCast(len));
        },
        maxInt(u8)...maxInt(u16) => {
            result.appendAssumeCapacity(0xda);
            result.writer().writeInt(u16, @intCast(len), .big) catch unreachable;
        },
        maxInt(u16)...maxInt(u32) => {
            result.appendAssumeCapacity(0xdb);
            result.writer().writeInt(u32, len, .big) catch unreachable;
        },
    }
    return result;
}

/// Generate a binary prefix.
pub inline fn prefixBinary(len: u32) Prefix {
    var result: Prefix = .{};
    switch (len) {
        0...maxInt(u8) => {
            result.appendAssumeCapacity(0xc4);
            result.appendSliceAssumeCapacity(&.{ 0xc4, @as(u8, @intCast(len)) });
        },
        maxInt(u8)...maxInt(u16) => {
            result.appendAssumeCapacity(0xc5);
            result.writer().writeInt(u16, @intCast(len), .big) catch unreachable;
        },
        maxInt(u16)...maxInt(u32) => {
            result.appendAssumeCapacity(0xc6);
            result.writer().writeInt(u32, len, .big) catch unreachable;
        },
    }
    return result;
}

/// Generate a array prefix for `len`.
pub inline fn prefixArray(len: u32) Prefix {
    var result: Prefix = .{};
    switch (len) {
        0...0b00001111 => {
            result.appendAssumeCapacity(0b10010000 | (0b00001111 & @as(u8, @intCast(len))));
        },
        (0b00001111 + 1)...maxInt(u16) => {
            result.appendAssumeCapacity(0xdc);
            result.writer().writeInt(u16, @intCast(len), .big) catch unreachable;
        },
        maxInt(u16) + 1...maxInt(u32) => {
            result.appendAssumeCapacity(0xdd);
            result.writer().writeInt(u32, len, .big) catch unreachable;
        },
    }
    return result;
}

/// Generate a map prefix.
///
/// The `len` here is the number of the k-v pairs.
/// The elements of the map must be placed as
/// KEY VALUE KEY VALUE ... so on.
pub inline fn prefixMap(len: u32) Prefix {
    var result: Prefix = .{};
    switch (len) {
        0...0b00001111 => {
            result.appendAssumeCapacity(0b10000000 | (0b00001111 & @as(u8, @intCast(len))));
        },
        (0b00001111 + 1)...maxInt(u16) => {
            result.appendAssumeCapacity(0xde);
            result.writer().writeInt(u16, @intCast(len), .big) catch unreachable;
        },
        maxInt(u16) + 1...maxInt(u32) => {
            result.appendAssumeCapacity(0xdf);
            result.writer().writeInt(u32, len, .big);
        },
    }
    return result;
}

/// Generate a ext prefix.
pub inline fn prefixExt(len: u32, extype: i8) Prefix {
    var result: Prefix = .{};
    const writer = result.writer();
    switch (len) {
        1, 2, 4, 8, 16 => |b| {
            result.appendAssumeCapacity(0xd4 + log2(b));
            writer.writeInt(i8, extype, .big) catch unreachable;
        },
        0...maxInt(u8) => {
            result.appendSliceAssumeCapacity(&.{ 0xc7, @intCast(len) });
            writer.writeInt(i8, extype, .big) catch unreachable;
        },
        maxInt(u8) + 1...maxInt(u16) => {
            result.appendAssumeCapacity(0xc8);
            writer.writeInt(u16, @intCast(len), .big);
            writer.writeInt(i8, extype, .big);
        },
        maxInt(u16) + 1...maxInt(u32) => {
            result.appendAssumeCapacity(0xc9);
            writer.writeInt(u32, @intCast(len), .big);
            writer.writeInt(i8, extype, .big);
        },
    }
    return result;
}

/// The value container type.
///
/// Every represented value is stored in a container.
/// The first byte of every container indicates the value type
/// and the header type.
///
/// See `MappedContainerType` for parsing the type.
///
/// ### Fixed-header containers
/// The fields are named with `fixed_` prefix.
///
/// Those container's header or even the value is fixed into the type.
/// Use the MASK_* to separate the type and the length (value).
/// ```
/// const length = containerType & ~ContainerType.MASK_FIXED_STR;
/// ```
pub const ContainerType = enum(u8) {
    pub const MASK_FIXED_INT_POSITIVE: u8 = 0b10000000;
    pub const MASK_FIXED_INT_NEGATIVE: u8 = 0b11100000;
    pub const MASK_FIXED_STR: u8 = 0b11100000;
    pub const MASK_FIXED_ARRAY: u8 = 0b11110000;
    pub const MASK_FIXED_MAP: u8 = 0b11110000;

    fixed_int_positive = 0,
    fixed_int_negative = 0b11100000,
    fixed_str = 0b10100000,
    fixed_array = 0b10010000,
    fixed_map = 0b10000000,

    nil = 0xc0,
    bool_false = 0xc2,
    bool_true = 0xc3,

    // Serieses
    bin8 = 0xc4,
    bin16 = 0xc5,
    bin32 = 0xc6,
    str8 = 0xd9,
    str16 = 0xda,
    str32 = 0xdb,
    array16 = 0xdc,
    array32 = 0xdd,
    map16 = 0xde,
    map32 = 0xdf,
    // Extended Serieses
    ext8 = 0xc7,
    ext16 = 0xc8,
    ext32 = 0xc9,

    // Primitives
    float32 = 0xca,
    float64 = 0xcb,
    uint8 = 0xcc,
    uint16 = 0xcd,
    uint32 = 0xce,
    uint64 = 0xcf,
    int8 = 0xd0,
    int16 = 0xd1,
    int32 = 0xd2,
    int64 = 0xd3,
    // Extended Primitives
    // They are different from fixed_ types,
    // so the "fixed" is moved to the suffix.
    ext_fixed1 = 0xd4,
    ext_fixed2 = 0xd5,
    ext_fixed4 = 0xd6,
    ext_fixed8 = 0xd7,
    ext_fixed16 = 0xd8,
};

pub const HeaderType = union(enum) {
    nil,
    bool: bool,
    bin: u2,
    fixstr: u8,
    str: u2,
    fixext: u3,
    ext: u3,
    fixint: i8,
    uint: u2,
    int: u2,
    float: u1,
    fixarray: u8,
    array: u1,
    fixmap: u8,
    map: u1,

    pub fn from(value: u8) ?HeaderType {
        if (value & ContainerType.MASK_FIXED_INT_POSITIVE == @intFromEnum(ContainerType.fixed_int_positive)) {
            return .{ .fixint = @intCast(value & ~ContainerType.MASK_FIXED_INT_POSITIVE) };
        }
        if (value & ContainerType.MASK_FIXED_INT_NEGATIVE == @intFromEnum(ContainerType.fixed_int_negative)) {
            return .{ .fixint = -@as(i8, @intCast(value & ~ContainerType.MASK_FIXED_INT_NEGATIVE)) };
        }
        if (value & ContainerType.MASK_FIXED_STR == @intFromEnum(ContainerType.fixed_str)) {
            return .{ .fixstr = value & ~ContainerType.MASK_FIXED_STR };
        }
        if (value & ContainerType.MASK_FIXED_ARRAY == @intFromEnum(ContainerType.fixed_array)) {
            return .{ .fixarray = value & ~ContainerType.MASK_FIXED_ARRAY };
        }
        if (value & ContainerType.MASK_FIXED_MAP == @intFromEnum(ContainerType.fixed_map)) {
            return .{ .fixmap = value & ~ContainerType.MASK_FIXED_MAP };
        }

        return switch (value) {
            @intFromEnum(ContainerType.nil) => .nil,
            @intFromEnum(ContainerType.bool_false), @intFromEnum(ContainerType.bool_true) => .{
                .bool = (value - @intFromEnum(ContainerType.bool_false)) == 1,
            },
            @intFromEnum(ContainerType.bin8)...@intFromEnum(ContainerType.bin32) => .{
                .bin = @intCast(value - @intFromEnum(ContainerType.bin8)),
            },
            @intFromEnum(ContainerType.str8)...@intFromEnum(ContainerType.str32) => .{
                .str = @intCast(value - @intFromEnum(ContainerType.str8)),
            },
            @intFromEnum(ContainerType.uint8)...@intFromEnum(ContainerType.uint64) => .{
                .uint = @intCast(value - @intFromEnum(ContainerType.uint8)),
            },
            @intFromEnum(ContainerType.int8)...@intFromEnum(ContainerType.int64) => .{
                .int = @intCast(value - @intFromEnum(ContainerType.int8)),
            },
            @intFromEnum(ContainerType.float32)...@intFromEnum(ContainerType.float64) => .{
                .float = @intCast(value - @intFromEnum(ContainerType.float32)),
            },
            @intFromEnum(ContainerType.array16)...@intFromEnum(ContainerType.array32) => .{
                .array = @intCast(value - @intFromEnum(ContainerType.array16)),
            },
            @intFromEnum(ContainerType.map16)...@intFromEnum(ContainerType.map32) => .{
                .map = @intCast(value - @intFromEnum(ContainerType.map16)),
            },
            @intFromEnum(ContainerType.ext_fixed1)...@intFromEnum(ContainerType.ext_fixed16) => .{
                .fixext = @intCast(value - @intFromEnum(ContainerType.ext_fixed1)),
            },
            @intFromEnum(ContainerType.ext8)...@intFromEnum(ContainerType.ext32) => .{
                .ext = @intCast(value - @intFromEnum(ContainerType.ext8)),
            },
            else => null,
        };
    }

    pub fn nextComponentSize(self: @This()) usize {
        return switch (self) {
            .nil, .bool, .fixint, .fixarray, .fixmap => 0,
            .bin, .str => |n| switch (n) {
                0 => 1,
                1 => 2,
                2 => 4,
                else => unreachable,
            },
            .fixstr => |n| n,
            .fixext => |n| 1 + n,
            .ext => |n| (switch (n) {
                0 => 1 + 1,
                1 => 1 + 2,
                2 => 1 + 4,
                else => unreachable,
            }),
            .int, .uint => |n| switch (n) {
                0 => 1,
                1 => 2,
                2 => 4,
                3 => 8,
            },
            .float => |n| switch (n) {
                0 => 4,
                1 => 8,
            },
            .array, .map => |n| switch (n) {
                0 => 2,
                1 => 4,
            },
        };
    }

    pub fn family(self: HeaderType) ValueTypeFamily {
        return switch (self) {
            .nil => .nil,
            .bool => .bool,
            .fixint, .int => .int,
            .uint => .uint,
            .fixstr, .str => .str,
            .bin => .bin,
            .float => .float,
            .ext, .fixext => .ext,
            .array, .fixarray => .array,
            .map, .fixmap => .map,
        };
    }
};

pub const Header = struct {
    type: HeaderType,
    ext: i8 = 0,
    /// Body size. For primitives, it's the byte size of the value body.
    /// For array and map, it's the item number of array or map.
    size: u32 = 0,

    pub fn from(typ: HeaderType, rest: []const u8) struct { Header, usize } {
        return switch (typ) {
            .nil, .bool, .fixint => .{
                .{ .type = typ },
                0,
            },
            .bin, .str => readBin: {
                const lensize = typ.nextComponentSize();
                const len = switch (lensize) {
                    1 => readIntBig(u8, rest[0..1]),
                    2 => readIntBig(u16, rest[0..2]),
                    4 => readIntBig(u32, rest[0..4]),
                    else => unreachable,
                };
                break :readBin .{
                    .{ .type = typ, .size = len },
                    lensize,
                };
            },
            .fixstr, .fixarray, .fixmap => |nitems| .{
                .{ .type = typ, .size = nitems },
                0,
            },
            .fixext => readFixExt: {
                const size = typ.nextComponentSize() - 1;
                const ext = readIntBig(i8, rest[0..1]);

                break :readFixExt .{
                    .{ .type = typ, .size = @intCast(size), .ext = ext },
                    1,
                };
            },
            .ext => readExt: {
                const lensize = typ.nextComponentSize() - 1;
                const ext = readIntBig(i8, rest[lensize..][0..1]);
                const length = switch (lensize) {
                    1 => readIntBig(u8, rest[1..2]),
                    2 => readIntBig(u16, rest[1..3]),
                    4 => readIntBig(u32, rest[1..5]),
                    else => unreachable,
                };
                break :readExt .{ .{ .type = typ, .size = length, .ext = ext }, lensize + 1 };
            },
            .uint, .int, .float => .{
                .{ .type = typ, .size = @intCast(typ.nextComponentSize()) },
                0,
            },
            .array, .map => |lensize| readArray: {
                const size = switch (lensize) {
                    0 => readIntBig(u16, rest[0..2]),
                    1 => readIntBig(u32, rest[0..4]),
                };
                const hbytes: usize = switch (lensize) {
                    0 => 2,
                    1 => 4,
                };
                break :readArray .{
                    .{ .type = typ, .size = size },
                    hbytes,
                };
            },
        };
    }
};

pub const ValueTypeFamily = enum {
    nil,
    bool,
    int,
    uint,
    bin,
    str,
    float,
    ext,
    array,
    map,
};

/// Unpacking state.
///
/// ```zig
/// const unpack: Unpack = .{.rest = data};
///
/// if (unpack.peek()) |peek| {
///     const requiredSize = peek.nextComponentSize();
///     if (requiredSize > unpack.rest.len) {
///         const ndata = readMore(data);
///         unpack.setAppend(data.len, ndata);
///         data = ndata;
///     }
///
///     const header = unpack.next(peek);
///     if ((header.type.family() != .array
///         or header.type.family() != .map) // streaming map or array elements
///         and unpack.rest.len < header.size) {
///         const ndata = readMore(data);
///         unpack.setAppend(data.len, ndata);
///         data = ndata;
///     }
/// } else {
///     doSomething(); // No enough data to peek
/// }
/// ```
///
/// - Concurrency-safe: No
pub const Unpack = struct {
    rest: []const u8,

    pub fn init(data: []const u8) Unpack {
        return .{ .rest = data };
    }

    pub fn setAppend(self: *Unpack, olen: usize, new: []const u8) void {
        const ofs = olen - self.rest.len;
        self.rest = new[ofs..];
    }

    pub const PeekError = error{
        BufferEmpty,
        UnrecognizedType,
    };

    pub fn peek(self: *const Unpack) PeekError!HeaderType {
        if (self.rest.len == 0) {
            return PeekError.BufferEmpty;
        }

        return HeaderType.from(self.rest[0]) orelse PeekError.UnrecognizedType;
    }

    /// Consumes the current value header.
    ///
    /// You can use the result `Header.size` to confirm the
    /// buffer can have further read.
    /// Note: for array or map, the size is the number of items.
    /// You can ignore it for streaming or still use it to prepare data,
    /// this is also the number of bytes of container types.
    ///
    /// Calling this function, you must confirm the buffer has enough data to
    /// read. Use `HeaderType.nextComponentSize()` to get the expected size for
    /// the value header.
    pub fn next(self: *Unpack, headerType: HeaderType) Header {
        const header, const consumes = Header.from(headerType, self.rest[1..]);
        self.rest = self.rest[1 + consumes ..];
        // std.debug.print("Unpack.next headerType = {}, comsumes = {}, header = {}\n", .{
        //     headerType,
        //     consumes,
        //     header,
        // });
        return header;
    }

    pub const ConvertError = error{InvalidValue};

    /// Consumes the current value as the null.
    ///
    /// Note that the result must be peer resolved to a type
    /// with valid representation, like `?*opaque {}`.
    pub fn nil(_: *Unpack, header: Header) ConvertError!@TypeOf(null) {
        if (header.type == .nil) {
            return null;
        }
        return ConvertError.InvalidValue;
    }

    pub fn @"bool"(_: *Unpack, header: Header) ConvertError!bool {
        return switch (header.type) {
            .bool => |v| v,
            else => ConvertError.InvalidValue,
        };
    }

    inline fn rawUInt(self: *Unpack, header: Header) ConvertError!u64 {
        if (header.type != .uint) {
            return ConvertError.InvalidValue;
        }

        defer self.rest = self.rest[header.size..];
        return switch (header.size) {
            1 => readIntBig(u8, self.rest[0..1]),
            2 => readIntBig(u16, self.rest[0..2]),
            4 => readIntBig(u32, self.rest[0..4]),
            8 => readIntBig(u64, self.rest[0..8]),
            else => unreachable,
        };
    }

    inline fn rawInt(self: *Unpack, header: Header) ConvertError!i64 {
        if (header.type != .int) {
            return ConvertError.InvalidValue;
        }

        defer self.rest = self.rest[header.size..];
        return switch (header.size) {
            1 => readIntBig(i8, self.rest[0..1]),
            2 => readIntBig(i16, self.rest[0..2]),
            4 => readIntBig(i32, self.rest[0..4]),
            8 => readIntBig(i64, self.rest[0..8]),
            else => unreachable,
        };
    }

    /// Consume the current value as (signed or unsigned) integer,
    /// and casts to your requested type.
    ///
    /// Use `i65` to make sure enough space for any unsigned integer.
    pub fn int(self: *Unpack, Int: type, header: Header) ConvertError!Int {
        return switch (header.type) {
            .fixint => |n| std.math.cast(Int, n) orelse ConvertError.InvalidValue,
            .int => std.math.cast(Int, try self.rawInt(header)) orelse ConvertError.InvalidValue,
            .uint => std.math.cast(Int, try self.rawUInt(header)) orelse ConvertError.InvalidValue,
            .float => @intFromFloat(try self.rawFloat(header)),
            else => ConvertError.InvalidValue,
        };
    }

    /// Consume the current value as the raw, as long as they
    /// have the size.
    pub fn raw(self: *Unpack, header: Header) []const u8 {
        const result = self.rest[0..header.size];
        self.rest = self.rest[header.size..];
        return result;
    }

    inline fn rawFloat(self: *Unpack, header: Header) ConvertError!f64 {
        if (header.type != .float) {
            return ConvertError.InvalidValue;
        }
        const value: f64 = switch (header.size) {
            4 => compatstd.mem.readFloatBig(f32, self.rest[0..4]),
            8 => compatstd.mem.readFloatBig(f64, self.rest[0..8]),
            else => unreachable,
        };
        self.rest = self.rest[header.size..];
        return value;
    }

    fn checkedFloatFromInt(Float: type, i: anytype) ConvertError!Float {
        const max = (2 << (std.math.floatMantissaBits(Float) + 1)) + 1;
        const min = -max;

        if (i > max or i < min) {
            return ConvertError.InvalidValue;
        }

        return @floatFromInt(i);
    }

    /// Consume the current value as float.
    pub fn float(self: *Unpack, Float: type, header: Header) ConvertError!Float {
        return switch (header.type) {
            .float => @floatCast(try self.rawFloat(header)),
            .fixint => |n| checkedFloatFromInt(Float, n),
            .int => checkedFloatFromInt(Float, try self.rawInt(header)),
            .uint => checkedFloatFromInt(Float, try self.rawUInt(header)),
            else => ConvertError.InvalidValue,
        };
    }

    pub fn array(self: *Unpack, header: Header) ConvertError!UnpackArray {
        if (header.type != .array or header.type != .fixarray) {
            return ConvertError.InvalidValue;
        }

        return UnpackArray{
            .unpack = self,
            .len = header.size,
        };
    }

    pub fn map(self: *Unpack, header: Header) ConvertError!UnpackMap {
        if (header.type != .map or header.type != .fixmap) {
            return ConvertError.InvalidValue;
        }

        return UnpackMap{
            .unpack = self,
            .len = header.size,
        };
    }
};

pub const UnpackArray = struct {
    unpack: *Unpack,
    current: u32 = 0,
    len: u32,

    pub const PeekError = Unpack.PeekError;

    /// Peek the next header type.
    ///
    /// Return `null` if the array is ended, `PeekError.BufferEmpty`
    /// if the buffered data does not enough for peeking.
    pub fn peek(self: UnpackArray) PeekError!?HeaderType {
        if (self.current >= self.len) {
            return null;
        }

        return self.unpack.peek() orelse PeekError.BufferEmpty;
    }

    pub fn next(self: *UnpackArray, headerType: HeaderType) Header {
        const value = self.unpack.next(headerType);
        self.current += 1;
        return value;
    }
};

pub const UnpackMap = struct {
    unpack: *UnpackMap,
    current: u32 = 0,
    len: u32,
    is_value: bool = false,

    pub const PeekError = Unpack.PeekError;

    pub fn peek(self: UnpackMap) PeekError!?HeaderType {
        if (self.current >= self.len) {
            return null;
        }

        return self.unpack.peek() orelse PeekError.BufferEmpty;
    }

    pub fn next(self: *UnpackMap, headerType: HeaderType) Header {
        const value = self.unpack.next(headerType);
        if (self.is_value) {
            self.current += 1;
        }
        self.is_value = !self.is_value;
        return value;
    }
};
