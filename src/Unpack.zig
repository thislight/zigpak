//! Unpacking state.
//!
//! This structure manages user-supplied data and converts messagepack
//! representations to the host representations.
//!
//! To start unpacking, you supply the data with `Unpack.init`.
//!
//! - `Unpack.peek` begins the unpack process for a value.
//!   - The function returns a `HeaderType`.
//!   - Use `HeaderType.countData` to get the required data size
//!     for the header.
//! - Ensured the `Unpack.rest` have enough data, use `Unpack.next` move to
//!  the next value and extract the header.
//!   - The result is a `Header`, it can be inspected to decide what to do with
//!     the current value.
//! - You can consume the value with any of `Unpack.nil`,
//!   `Unpack.@"bool"`, `Unpack.int`, `Unpack.float`, `Unpack.array`,
//!   `Unpack.map`, `Unpack.raw`.
//!
//! You must consume the current value for the next value. To skip the
//! current value, use `Unpack.raw`. `Unpack.raw` can consume any value
//! as a []const u8, excepts arrays and maps.
//! Because they don't have determined byte size in header, see `Header.size`.
//!
//! If the buffer is appended with more data, use `Unpack.setAppend` to set the
//! updated buffer.
//!
//! This structure does not have additional internal state. You can
//! save the state and return to the point as you wish.
//!
//! - Concurrency-safe: No
//! - See `io.UnpackReader`
//!
//! ```
//! const unpack: Unpack = Unpack.init(data);
//!
//! if (unpack.peek()) |peek| {
//!     const requiredSize = peek.count();
//!     if (requiredSize > unpack.rest.len) {
//!         const ndata = readMore(data);
//!         unpack.setAppend(data.len, ndata);
//!         data = ndata;
//!     }
//!
//!     const header = unpack.next(peek);
//!     if ((header.type.family() != .array
//!         or header.type.family() != .map) // streaming map or array elements
//!         and unpack.rest.len < header.size) {
//!         const ndata = readMore(data);
//!         unpack.setAppend(data.len, ndata);
//!         data = ndata;
//!     }
//! } else {
//!     doSomething(); // No enough data to peek
//! }
//! ```
const std = @import("std");
const compatstd = @import("./compatstd.zig");
const readIntBig = compatstd.mem.readIntBig;
const root = @import("./root.zig");
const HeaderType = root.HeaderType;
const Header = root.Header;

rest: []const u8,

const Unpack = @This();

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
/// read. Use `HeaderType.count` to get the expected size for
/// the value header.
pub fn next(self: *Unpack, headerType: HeaderType) Header {
    const header = Header.from(headerType, self.rest[1..]);
    self.rest = self.rest[headerType.count()..];
    return header;
}

pub const ConvertError = error{InvalidValue};

/// Consumes the current value as the null.
///
/// The `T` must be an optional type.
pub fn nil(_: *Unpack, T: type, header: Header) ConvertError!T {
    if (header.type == .nil) {
        return null;
    }
    return ConvertError.InvalidValue;
}

/// Consumes the current value as a bool.
///
/// This function does not need additional data from the buffer.
pub fn @"bool"(_: *Unpack, header: Header) ConvertError!bool {
    return switch (header.type) {
        .bool => |v| v,
        else => ConvertError.InvalidValue,
    };
}

inline fn rawUInt(self: *Unpack, header: Header) ConvertError!u64 {
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
    defer self.rest = self.rest[header.size..];
    return switch (header.size) {
        1 => readIntBig(i8, self.rest[0..1]),
        2 => readIntBig(i16, self.rest[0..2]),
        4 => readIntBig(i32, self.rest[0..4]),
        8 => readIntBig(i64, self.rest[0..8]),
        else => unreachable,
    };
}

/// Consume the current value and casts to your requested integer type.
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
pub fn raw(self: *Unpack, header: Header) ConvertError![]const u8 {
    switch (header.type) {
        .array, .fixarray, .map, .fixmap => return ConvertError.InvalidValue,
        else => {
            const result = self.rest[0..header.size];
            self.rest = self.rest[header.size..];
            return result;
        },
    }
}

inline fn rawFloat(self: *Unpack, header: Header) ConvertError!f64 {
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

/// Consume the current value and casts to requested float type.
pub fn float(self: *Unpack, Float: type, header: Header) ConvertError!Float {
    return switch (header.type) {
        .float => @floatCast(try self.rawFloat(header)),
        .fixint => |n| checkedFloatFromInt(Float, n),
        .int => checkedFloatFromInt(Float, try self.rawInt(header)),
        .uint => checkedFloatFromInt(Float, try self.rawUInt(header)),
        else => ConvertError.InvalidValue,
    };
}

pub fn array(self: *Unpack, header: Header) ConvertError!Array {
    return switch (header.type) {
        .fixarray, .array => Array{
            .unpack = self,
            .len = header.size,
        },
        else => return ConvertError.InvalidValue,
    };
}

pub fn map(self: *Unpack, header: Header) ConvertError!Map {
    return switch (header.type) {
        .fixmap, .map => Map{
            .unpack = self,
            .len = header.size,
        },
        else => return ConvertError.InvalidValue,
    };
}

pub const Array = struct {
    unpack: *Unpack,
    current: u32 = 0,
    len: u32,

    /// Peek the next header type.
    ///
    /// Return `null` if the array is ended, `PeekError.BufferEmpty`
    /// if the buffered data does not enough for peeking.
    pub fn peek(self: Array) PeekError!?HeaderType {
        if (self.current >= self.len) {
            return null;
        }

        return try self.unpack.peek();
    }

    pub fn next(self: *Array, headerType: HeaderType) Header {
        const value = self.unpack.next(headerType);
        self.current += 1;
        return value;
    }
};

pub const Map = struct {
    unpack: *Unpack,
    current: u32 = 0,
    len: u32,
    is_value: bool = false,

    pub fn peek(self: Map) PeekError!?HeaderType {
        if (self.current >= self.len) {
            return null;
        }

        return try self.unpack.peek();
    }

    pub fn next(self: *Map, headerType: HeaderType) Header {
        const value = self.unpack.next(headerType);
        if (self.is_value) {
            self.current += 1;
        }
        self.is_value = !self.is_value;
        return value;
    }
};
