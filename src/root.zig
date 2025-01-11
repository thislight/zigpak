// SPDX: Apache-2.0
// This file is part of zigpak.
//! ## Zigpak - Messagepack for Zig
//!
//! - Unpack data in memory: `Unpack`
//! - Emit messagepack values into memory:
//!   - `writeNil`, `writeBool`
//!   - `writeInt`, `writeIntSm`, `writeFloat`
//!   - `prefixString`, `prefixBinary`, `prefixExt`
//!   - `prefixArray`, `prefixMap`
//! - `std.io` helpers: `io`
//!
//! ### Emit variable-sized messagepack values
//!
//! A messagepack document (contains of zero or one messagepack value) is
//! a linear representation of value(s).
//!
//! For example, you put a string into the document. The value is layout linearly:
//!
//! ```
//! | (str:11) | "Hello World" |
//! ^ ~~~~~ The container type (prefix)
//!             ^ ~~~~~~ The string content
//! ```
//!
//! So to put a string into the document, use the `prefixString` to write the
//! prefix, and write the content.
//!
//! ```zig
//! const content = "Hello World";
//!
//! var buf: [content.len + zigpak.PREFIX_BUFSIZE]u8 = undefined;
//! const prefix = zigpak.prefixString(@intCast(content.len));
//! std.mem.copyForward(u8, &buf, prefix.constSlice());
//! std.mem.copyForward(u8, buf[prefix.len..], content);
//!
//! const result = buf[0..prefix.len + content.len]; // the constructed value
//! ```
//!
//! > You can also directly write the prefix and the content into
//! > an external pipe, see `io`.
//!
//! Writing array or map is similar. The elements of any of them are
//! layout linearly on the element level. Let's say we put into array with a nil,
//! an int 1 and a string.
//!
//! ```
//! | (array:3) | (nil) | (int) | 0x01 | (str:11) | "Hello World" |
//! ^ ~~~ The container type (prefix) for the array
//!              ^ ~~~~~ Elements are layout linearly
//!                                        ^ ~~~~ The string follows the same rule
//! ```
//!
//! So the array can be constructed as:
//!
//! ```zig
//! usingnamespace zigpak;
//!
//! const strContent = "Hello World";
//!
//! var buf: std.BoundedArray(u8, zigpak.PREFIX_BUFSIZE * 4 + 1 + strContent.length) = .{};
//!
//! buf.appendSliceAssumeCapacity(prefixArray(3).constSlice());
//!
//! { // The first element: nil
//!     buf.len += writeNil(buf.unusedCapacitySlice());
//! }
//!
//! { // The second element: int 1
//!     buf.len += writeInt(i8, buf.unusedCapacitySlice(), 1);
//! }
//!
//! { // The third element: a string
//!     buf.appendSliceAssumeCapacity(prefixString(@intCast(strContent.length)).constSlice());
//!     buf.appendSliceAssumeCapacity(strContent);
//! }
//!
//! const result = buf.constSlice(); // the constructed array
//! ```
//!
//! The map's process is almost same to the array's:
//!
//! - The map's size is the number of the key-value pairs, like
//!   the size of `{ .a = 1, .b = "Hello World" }` is 2;
//! - Map's layout is an array of key-value pairs: the first key,
//!   the first value, the second key, and so on.
//!
//! For the `{ .a = 1, .b = "Hello World" }`, the layout is like:
//!
//! ```
//! | (map:2) | (str:1) | "a" | (int) | 0x01 | (str:1) | "b" | (str:11) | "Hello World" |
//! ```
//!

pub const io = @import("./io.zig");
pub const LookupTableOptimize = @import("./budopts.zig").LookupTableOptimize;
pub const Unpack = @import("./Unpack.zig");

/// The look up table optimization level.
/// Use `-Dlookup-table=<target>` in the build system to change this level.
pub const lookupTableMode: LookupTableOptimize = @enumFromInt(@intFromEnum(@import("budopts").lookupTable));

test {
    _ = io;
    _ = Unpack;
}

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
    return @intFromEnum(ContainerType.fixed_int_negative) | (~ContainerType.MASK_FIXED_INT_NEGATIVE & @as(u8, @intCast(@abs(value))));
}

/// Write integer `value` as specific type `T`, signed or unsigned.
///
/// This function uses type information from `T` to recognise the type in msgpack.
/// If the type is `i64`, the `value` is stored as a 64-bit signed integer; if the type is `u24`,
/// a 32-bit unsigned is used.
///
/// If you need to use the smallest type depends on the `value`, see `writeIntSm`.
pub fn writeInt(comptime T: type, dst: []u8, value: T) usize {
    const signed = compatstd.meta.signedness(value) == .signed;
    const bits = compatstd.meta.bitsOfNumber(value);
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
    const roundedBytes = switch (compatstd.meta.bitsOfType(T)) {
        0...32 => 4,
        33...64 => 8,
        else => @compileError(comptimePrint("unsupported {}", .{@typeName(T)})),
    };
    dst[0] = switch (roundedBytes) {
        4 => 0xca,
        8 => 0xcb,
        else => unreachable,
    };
    switch (roundedBytes) {
        4 => writeFloatBig(f32, dst[1..5], @floatCast(value)),
        8 => writeFloatBig(f64, dst[1..9], @floatCast(value)),
        else => unreachable,
    }
    return 1 + roundedBytes;
}

/// Write the float as the smallest float type,
/// as long as the precision won't lost.
///
/// This may introduce runtime check for certain input types.
pub inline fn writeFloatSm(comptime T: type, dst: []u8, value: T) usize {
    const wontLosePrecision = @as(f32, @floatCast(value)) == value;

    if (wontLosePrecision) {
        return writeFloat(f32, dst, @floatCast(value));
    } else {
        return writeFloat(f64, dst, @floatCast(value));
    }
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

/// Use this constant to decide the `Prefix` buffer size in comptime.
///
/// The prefixs are not always filled up all the buffer.
///
/// ```zig
/// var buf: [zigpak.PREFIX_BUFSIZE]u8 = undefined;
///
/// const prefix = prefixString(12);
/// std.mem.copyForward(u8, &buf, prefix.constSlice());
///
/// const header = buf[0..prefix.len]; // the actual header
/// ```
pub const PREFIX_BUFSIZE = 6;

/// The prefix for a value.
/// This is the header to be stored before the actual content.
pub const Prefix = std.BoundedArray(u8, PREFIX_BUFSIZE);
// TODO: further optimize appendAssumeCapacity - optimizer does not inline the call

/// Generate a string prefix.
pub inline fn prefixString(len: u32) Prefix {
    var result: Prefix = .{};
    switch (len) {
        0...0b00011111 => {
            result.appendAssumeCapacity(0b10100000 | (0b00011111 & @as(u8, @intCast(len))));
        },
        0b00011111 + 1...maxInt(u8) => {
            result.appendAssumeCapacity(0xd9);
            result.appendAssumeCapacity(@truncate(len));
        },
        maxInt(u8) + 1...maxInt(u16) => {
            result.appendAssumeCapacity(0xda);
            result.writer().writeInt(u16, @truncate(len), .big) catch unreachable;
        },
        maxInt(u16) + 1...maxInt(u32) => {
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
            result.appendSliceAssumeCapacity(&.{
                @intFromEnum(ContainerType.bin8),
                @as(u8, @truncate(len)),
            });
        },
        maxInt(u8) + 1...maxInt(u16) => {
            result.appendAssumeCapacity(@intFromEnum(ContainerType.bin16));
            result.writer().writeInt(u16, @truncate(len), .big) catch unreachable;
        },
        maxInt(u16) + 1...maxInt(u32) => {
            result.appendAssumeCapacity(@intFromEnum(ContainerType.bin32));
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
            result.appendAssumeCapacity(0b10010000 | (0b00001111 & @as(u8, @truncate(len))));
        },
        (0b00001111 + 1)...maxInt(u16) => {
            result.appendAssumeCapacity(0xdc);
            result.writer().writeInt(u16, @truncate(len), .big) catch unreachable;
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
            result.appendAssumeCapacity(0b10000000 | (0b00001111 & @as(u8, @truncate(len))));
        },
        (0b00001111 + 1)...maxInt(u16) => {
            result.appendAssumeCapacity(0xde);
            result.writer().writeInt(u16, @truncate(len), .big) catch unreachable;
        },
        maxInt(u16) + 1...maxInt(u32) => {
            result.appendAssumeCapacity(0xdf);
            result.writer().writeInt(u32, len, .big) catch unreachable;
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
            result.appendSliceAssumeCapacity(&.{ 0xc7, @truncate(len) });
            writer.writeInt(i8, extype, .big) catch unreachable;
        },
        maxInt(u8) + 1...maxInt(u16) => {
            result.appendAssumeCapacity(0xc8);
            writer.writeInt(u16, @truncate(len), .big);
            writer.writeInt(i8, extype, .big);
        },
        maxInt(u16) + 1...maxInt(u32) => {
            result.appendAssumeCapacity(0xc9);
            writer.writeInt(u32, @truncate(len), .big);
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

    /// The smallest not-fixed type.
    const MIN = ContainerType.nil;

    /// The biggest not-fixed type.
    const MAX = ContainerType.map32;
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

    fn tableLen(comptime includeFixed: bool) usize {
        const TMAX = @intFromEnum(ContainerType.MAX);
        const TMIN = @intFromEnum(ContainerType.MIN);
        return if (includeFixed) maxInt(u8) + 1 else (TMAX - TMIN + 1);
    }

    /// Make the lookup table.
    ///
    /// If fixeds are not included, the type number offset is `@intFromEnum(Container.MIN)`.
    /// If fixed are included, the offset is `0`.
    fn makeTable(comptime includeFixed: bool) [tableLen(includeFixed)]?HeaderType {
        const TMAX = @intFromEnum(ContainerType.MAX);
        const TMIN = @intFromEnum(ContainerType.MIN);
        const bufferSize = if (includeFixed) maxInt(u8) + 1 else (TMAX - TMIN + 1);
        comptime var buffer = [_]?HeaderType{null} ** bufferSize;

        if (includeFixed) {
            for (0..maxInt(u8) + 1) |i| {
                buffer[i] = HeaderType.parse(i);
            }
        } else {
            for (TMIN..TMAX + 1) |i| {
                buffer[i - TMIN] = HeaderType.parse(i);
            }
        }
        return buffer;
    }

    const MAX_FIXED_INT_NEG = ~ContainerType.MASK_FIXED_INT_NEGATIVE | @intFromEnum(ContainerType.fixed_int_negative);
    const MAX_FIXED_INT_POS = ~ContainerType.MASK_FIXED_INT_POSITIVE | @intFromEnum(ContainerType.fixed_int_positive);
    const MAX_FIXED_STR = ~ContainerType.MASK_FIXED_STR | @intFromEnum(ContainerType.fixed_str);
    const MAX_FIXED_ARRAY = ~ContainerType.MASK_FIXED_ARRAY | @intFromEnum(ContainerType.fixed_array);
    const MAX_FIXED_MAP = ~ContainerType.MASK_FIXED_MAP | @intFromEnum(ContainerType.fixed_map);

    inline fn parse(value: u8) ?HeaderType {
        return switch (value) {
            @intFromEnum(ContainerType.fixed_int_positive)...MAX_FIXED_INT_POS => .{
                .fixint = @intCast(value & ~ContainerType.MASK_FIXED_INT_POSITIVE),
            },
            @intFromEnum(ContainerType.fixed_int_negative)...MAX_FIXED_INT_NEG => .{
                .fixint = -@as(i8, @intCast(value & ~ContainerType.MASK_FIXED_INT_NEGATIVE)),
            },
            @intFromEnum(ContainerType.fixed_str)...MAX_FIXED_STR => .{
                .fixstr = value & ~ContainerType.MASK_FIXED_STR,
            },
            @intFromEnum(ContainerType.fixed_array)...MAX_FIXED_ARRAY => .{
                .fixarray = value & ~ContainerType.MASK_FIXED_ARRAY,
            },
            @intFromEnum(ContainerType.fixed_map)...MAX_FIXED_MAP => .{
                .fixmap = value & ~ContainerType.MASK_FIXED_MAP,
            },
            @intFromEnum(ContainerType.nil) => .nil,
            @intFromEnum(ContainerType.bool_false), @intFromEnum(ContainerType.bool_true) => .{
                .bool = value == @intFromEnum(ContainerType.bool_true),
            },
            @intFromEnum(ContainerType.bin8)...@intFromEnum(ContainerType.bin32) => .{
                .bin = @truncate(value - @intFromEnum(ContainerType.bin8)),
            },
            @intFromEnum(ContainerType.str8)...@intFromEnum(ContainerType.str32) => .{
                .str = @truncate(value - @intFromEnum(ContainerType.str8)),
            },
            @intFromEnum(ContainerType.uint8)...@intFromEnum(ContainerType.uint64) => .{
                .uint = @truncate(value - @intFromEnum(ContainerType.uint8)),
            },
            @intFromEnum(ContainerType.int8)...@intFromEnum(ContainerType.int64) => .{
                .int = @truncate(value - @intFromEnum(ContainerType.int8)),
            },
            @intFromEnum(ContainerType.float32)...@intFromEnum(ContainerType.float64) => .{
                .float = @truncate(value - @intFromEnum(ContainerType.float32)),
            },
            @intFromEnum(ContainerType.array16)...@intFromEnum(ContainerType.array32) => .{
                .array = @truncate(value - @intFromEnum(ContainerType.array16)),
            },
            @intFromEnum(ContainerType.map16)...@intFromEnum(ContainerType.map32) => .{
                .map = @truncate(value - @intFromEnum(ContainerType.map16)),
            },
            @intFromEnum(ContainerType.ext_fixed1)...@intFromEnum(ContainerType.ext_fixed16) => .{
                .fixext = @truncate(value - @intFromEnum(ContainerType.ext_fixed1)),
            },
            @intFromEnum(ContainerType.ext8)...@intFromEnum(ContainerType.ext32) => .{
                .ext = @truncate(value - @intFromEnum(ContainerType.ext8)),
            },
            else => null,
        };
    }

    /// small lookup table. 32 items (~64 bytes).
    const TAB_SMALL = makeTable(false);

    inline fn lookupSmall(value: u8) ?HeaderType {
        @setRuntimeSafety(false);

        return switch (value) {
            @intFromEnum(ContainerType.fixed_int_positive)...MAX_FIXED_INT_POS => .{
                .fixint = @intCast(value & ~ContainerType.MASK_FIXED_INT_POSITIVE),
            },
            @intFromEnum(ContainerType.fixed_int_negative)...MAX_FIXED_INT_NEG => .{
                .fixint = -@as(i8, @intCast(value & ~ContainerType.MASK_FIXED_INT_NEGATIVE)),
            },
            @intFromEnum(ContainerType.fixed_str)...MAX_FIXED_STR => .{
                .fixstr = value & ~ContainerType.MASK_FIXED_STR,
            },
            @intFromEnum(ContainerType.fixed_array)...MAX_FIXED_ARRAY => .{
                .fixarray = value & ~ContainerType.MASK_FIXED_ARRAY,
            },
            @intFromEnum(ContainerType.fixed_map)...MAX_FIXED_MAP => .{
                .fixmap = value & ~ContainerType.MASK_FIXED_MAP,
            },
            @intFromEnum(ContainerType.MIN)...@intFromEnum(ContainerType.MAX) => TAB_SMALL[value - @intFromEnum(ContainerType.MIN)],
        };
    }

    /// big lookup table. 256 items (~512 bytes).
    const TAB_ALL = makeTable(true);

    inline fn lookupAll(value: u8) ?HeaderType {
        @setRuntimeSafety(false); // the table already has all possibilities
        return TAB_ALL[value];
    }

    /// Convert a value to `HeaderType`.
    pub fn from(value: u8) ?HeaderType {
        switch (lookupTableMode) {
            .all => {
                return lookupAll(value);
            },
            .small => {
                return lookupSmall(value);
            },
            .none => {
                return parse(value);
            },
        }
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

    /// Return the header data size.
    ///
    /// ```
    /// | HeaderType | header data | payload |
    /// ```
    pub fn countData(self: HeaderType) u8 {
        return switch (self) {
            .nil,
            .bool,
            .fixint,
            .fixstr,
            .fixarray,
            .fixmap,
            .uint,
            .int,
            .float,
            => 0,
            .bin, .str => |n| switch (n) {
                0 => 1,
                1 => 2,
                2 => 4,
                else => unreachable,
            },
            .fixext => 1,
            .ext => |n| switch (n) {
                0 => 1 + 1,
                1 => 1 + 2,
                2 => 1 + 4,
                else => unreachable,
            },
            .array, .map => |n| switch (n) {
                0 => 2,
                1 => 4,
            },
        };
    }

    /// Return the whole header size.
    pub fn count(self: HeaderType) u8 {
        return self.countData() + 1;
    }

    pub const PayloadSizeInfo = struct {
        known: u8,
        is_variable: bool,

        fn init(size: u8, varsized: bool) PayloadSizeInfo {
            return .{ .known = size, .is_variable = varsized };
        }

        fn chooseReadSize(self: PayloadSizeInfo, varDefault: usize) usize {
            if (self.known > 0) {
                return self.known;
            } else if (self.is_variable) {
                return varDefault;
            } else {
                return 0;
            }
        }
    };

    pub fn payloadSize(self: HeaderType) PayloadSizeInfo {
        return switch (self) {
            .nil, .bool, .fixint => PayloadSizeInfo.init(0, false),
            .fixstr => |n| PayloadSizeInfo.init(n, false),
            .uint, .int => |n| PayloadSizeInfo.init(switch (n) {
                0 => 1,
                1 => 2,
                2 => 4,
                3 => 8,
            }, false),
            .float => |n| PayloadSizeInfo.init(switch (n) {
                0 => 4,
                1 => 8,
            }, false),
            .bin, .str, .ext => PayloadSizeInfo.init(0, true),
            .fixext => |n| PayloadSizeInfo.init(n, false),
            .fixarray, .fixmap, .array, .map => PayloadSizeInfo.init(0, true),
        };
    }
};

pub const Header = struct {
    /// The type of the header.
    ///
    /// > Keep in mind: the `HeaderType` has separated fixed-number types.
    /// > Like `HeaderType.map` and `HeaderType.fixmap` are
    /// > exists together. Don't forget to include them in
    /// > your type test! Or use the `HeaderType.family` to
    /// > get the type family.
    type: HeaderType,
    /// The extension type.
    ///
    /// `<0` are defined by the messagepack spec.
    /// `>=0` are application defined.
    ext: i8 = 0,
    /// Body size. For primitives, it's the byte size of the value body.
    /// For array and map, it's the item number of the array or the map.
    size: u32 = 0,

    pub fn from(typ: HeaderType, rest: []const u8) Header {
        return switch (typ) {
            .nil, .bool, .fixint => .{ .type = typ },
            .bin, .str => readBin: {
                const lensize = typ.countData();
                const len = switch (lensize) {
                    1 => readIntBig(u8, rest[0..1]),
                    2 => readIntBig(u16, rest[0..2]),
                    4 => readIntBig(u32, rest[0..4]),
                    else => unreachable,
                };
                break :readBin .{ .type = typ, .size = len };
            },
            .fixstr, .fixarray, .fixmap => |nitems| .{ .type = typ, .size = nitems },
            .fixext => |size| readFixExt: {
                const ext = readIntBig(i8, rest[0..1]);

                break :readFixExt .{ .type = typ, .size = @intCast(size), .ext = ext };
            },
            .ext => readExt: {
                const lensize = typ.countData() - 1;
                const ext = readIntBig(i8, rest[lensize..][0..1]);
                const length = switch (lensize) {
                    1 => readIntBig(u8, rest[1..2]),
                    2 => readIntBig(u16, rest[1..3]),
                    4 => readIntBig(u32, rest[1..5]),
                    else => unreachable,
                };
                break :readExt .{ .type = typ, .size = length, .ext = ext };
            },
            .uint, .int => |k| .{ .type = typ, .size = switch (k) {
                0 => 1,
                1 => 2,
                2 => 4,
                3 => 8,
            } },
            .float => |k| .{ .type = typ, .size = switch (k) {
                0 => 4,
                1 => 8,
            } },
            .array, .map => |lensize| readArray: {
                const size = switch (lensize) {
                    0 => readIntBig(u16, rest[0..2]),
                    1 => readIntBig(u32, rest[0..4]),
                };
                break :readArray .{ .type = typ, .size = size };
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
