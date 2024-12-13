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

test writeNil {
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
    pub const MASK_FIXED_INT_POSITIVE = 0b10000000;
    pub const MASK_FIXED_INT_NEATIVE = 0b11100000;
    pub const MASK_FIXED_STR = 0b11100000;
    pub const MASK_FIXED_ARRAY = 0b11110000;
    pub const MASK_FIXED_MAP = 0b11110000;

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
    fixint: i7,
    uint: u2,
    int: u2,
    float: u1,
    fixarray: u8,
    array: u1,
    fixmap: u8,
    map: u1,

    pub fn from(value: u8) ?HeaderType {
        if (value & ContainerType.MASK_FIXED_INT_POSITIVE == @intFromEnum(ContainerType.fixed_int_positive)) {
            return .{ .fixint = value & ~ContainerType.MASK_FIXED_INT_POSITIVE };
        }
        if (value & ContainerType.MASK_FIXED_INT_NEGATIVE == @intFromEnum(ContainerType.fixed_int_negative)) {
            return .{ .fixint = -(value & ~ContainerType.MASK_FIXED_INT_NEGATIVE) };
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
                .bin = (value - @intFromEnum(ContainerType.bin8) - 1),
            },
            @intFromEnum(ContainerType.str8)...@intFromEnum(ContainerType.str32) => .{
                .str = (value - @intFromEnum(ContainerType.str8) - 1),
            },
            @intFromEnum(ContainerType.uint8)...@intFromEnum(ContainerType.uint64) => .{
                .uint = value - @intFromEnum(ContainerType.uint8) - 1,
            },
            @intFromEnum(ContainerType.int8)...@intFromEnum(ContainerType.int64) => .{
                .int = value - @intFromEnum(ContainerType.int8) - 1,
            },
            @intFromEnum(ContainerType.float32)...@intFromEnum(ContainerType.float64) => .{
                .float = value - @intFromEnum(ContainerType.float32) - 1,
            },
            @intFromEnum(ContainerType.array16)...@intFromEnum(ContainerType.array32) => .{
                .array = value - @intFromEnum(ContainerType.array16) - 1,
            },
            @intFromEnum(ContainerType.map16)...@intFromEnum(ContainerType.map32) => .{
                .map = value - @intFromEnum(ContainerType.map16) - 1,
            },
            @intFromEnum(ContainerType.ext_fixed1)...@intFromEnum(ContainerType.ext_fixed16) => .{
                .fixext = value - @intFromEnum(ContainerType.ext_fixed1) - 1,
            },
            @intFromEnum(ContainerType.ext8)...@intFromEnum(ContainerType.ext32) => .{
                .ext = value - @intFromEnum(ContainerType.ext8) - 1,
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
            .ext => |n| 1 + (switch (n) {
                0 => 1,
                1 => 2,
                2 => 4,
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
            .array => .array,
            .map => .map,
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
                    2 => readIntBig(u8, rest[0..2]),
                    4 => readIntBig(u8, rest[0..4]),
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
                    .{ .type = typ, .size = size, .ext = ext },
                    1,
                };
            },
            .ext => readExt: {
                const lensize = typ.nextComponentSize() - 1;
                const ext = readIntBig(i8, rest[0..1]);
                const length = switch (lensize) {
                    1 => readIntBig(u8, rest[1..2]),
                    2 => readIntBig(u16, rest[1..5]),
                    4 => readIntBig(u32, rest[1..7]),
                    else => unreachable,
                };
                break :readExt .{ .{ .type = typ, .size = length, .ext = ext }, lensize + 1 };
            },
            .uint, .int, .float => .{
                .{ .type = typ, .size = typ.nextComponentSize() },
                0,
            },
            .array, .map => |lensize| readArray: {
                const size = switch (lensize) {
                    0 => readIntBig(u16, rest[0..2]),
                    1 => readIntBig(u32, rest[0..4]),
                };
                const hbytes = switch (lensize) {
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

    pub fn setAppend(self: *Unpack, olen: usize, new: []const u8) void {
        const ofs = olen - self.rest.len;
        self.rest = new[ofs..];
    }

    pub const PeekError = error{
        BufferEmpty,
        UnregconizedType,
    };

    pub fn peek(self: *const Unpack) PeekError!HeaderType {
        if (self.rest.len == 0) {
            return PeekError.BufferEmpty;
        }

        return HeaderType.from(self.rest[0]) orelse PeekError.UnregconizedType;
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
        self.rest = self.rest[1 + consumes];
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
        switch (header.size) {
            1 => readIntBig(u8, self.rest[0..1]),
            2 => readIntBig(u16, self.rest[0..2]),
            4 => readIntBig(u32, self.rest[0..4]),
            8 => readIntBig(u64, self.rest[0..8]),
            else => unreachable,
        }
        self.rest = self.rest[8..];
    }

    inline fn rawInt(self: *Unpack, header: Header) ConvertError!i64 {
        switch (header.size) {
            1 => readIntBig(i8, self.rest[0..1]),
            2 => readIntBig(i16, self.rest[0..2]),
            4 => readIntBig(i32, self.rest[0..4]),
            8 => readIntBig(i64, self.rest[0..8]),
            else => unreachable,
        }
        self.rest = self.rest[8..];
    }

    /// Consume the current value as (signed or unsigned) integer,
    /// and casts to your requested type.
    ///
    /// Use `i67` to make sure enough space for any unsigned integer.
    pub fn int(self: *Unpack, Int: type, header: Header) ConvertError!Int {
        return switch (header.type) {
            .fixint => |n| std.math.cast(Int, n) orelse ConvertError.InvalidValue,
            .int => std.math.cast(Int, try self.rawInt(header)) orelse ConvertError.InvalidValue,
            .uint => std.math.cast(Int, try self.rawUInt(header)) orelse ConvertError.InvalidValue,
            .float => std.math.cast(Int, try self.rawFloat(header)) orelse ConvertError.InvalidValue,
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

    /// Consume the current value as float.
    pub fn float(self: *Unpack, Float: type, header: Header) ConvertError!Float {
        return switch (header.type) {
            .float => std.math.cast(Float, try self.rawFloat(header)) orelse ConvertError.InvalidValue,
            .fixint => |n| std.math.cast(Float, n) orelse ConvertError.InvalidValue,
            .int => std.math.cast(Float, self.rawInt(header)) orelse ConvertError.InvalidValue,
            .uint => std.math.cast(Float, self.rawUInt(header)) orelse ConvertError.InvalidValue,
            else => ConvertError.InvalidValue,
        };
    }

    pub fn array(self: *Unpack, header: Header) ConvertError!UnpackArray {
        if (header.type != .array) {
            return ConvertError.InvalidValue;
        }

        return UnpackArray{
            .unpack = self,
            .len = header.size,
        };
    }

    pub fn map(self: *Unpack, header: Header) ConvertError!UnpackMap {
        if (header.type != .map) {
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
