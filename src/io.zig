// SPDX: Apache-2.0
// This file is part of zigpak.
//! ## `std.io` helpers for zigpak
//!
//! - Unpack data from reader: `UnpackReader`
//! - Write messagepack values into writer:
//!   - `writeStringPrefix`, `writeString`
//!   - `writeBinaryPrefix`, `writeBinary`
//!   - `writeExtPrefix`, `writeExt`
//!   - `writeBool`, `writeNil`
//!   - `writeInt`, `writeIntSm`, `writeFloat`
//!   - `writeArrayPrefix`, `writeMapPrefix`
const fmt = @import("./root.zig");
const std = @import("std");
const log2IntCeil = std.math.log2_int_ceil;
const divCeil = std.math.divCeil;
const comptimePrint = std.fmt.comptimePrint;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

pub fn writeStringPrefix(writer: anytype, length: u32) !usize {
    const header = fmt.prefixString(length);
    return try writer.write(header.constSlice());
}

pub fn writeString(writer: anytype, src: []const u8) !usize {
    const size1 = try writeStringPrefix(writer, @intCast(src.len));
    const size2 = try writer.write(src);
    return size1 + size2;
}

pub fn writeBinaryPrefix(writer: anytype, length: u32) !usize {
    const header = fmt.prefixBinary(length);
    return try writer.write(header.constSlice());
}

pub fn writeBinary(writer: anytype, src: []const u8) !usize {
    const size1 = try writeBinaryPrefix(writer, @intCast(src.len));
    const size2 = try writer.write(src);
    return size1 + size2;
}

pub fn writeExtPrefix(writer: anytype, length: u32, extype: i8) !usize {
    const header = fmt.prefixExt(length, extype);
    return try writer.write(header.constSlice());
}

pub fn writeExt(writer: anytype, extype: i8, payload: []const u8) !usize {
    const size1 = try writeExtPrefix(writer, @intCast(payload.len), extype);
    const size2 = try writer.write(payload);
    return size1 + size2;
}

pub fn writeBool(writer: anytype, value: bool) !usize {
    var buf = [_]u8{0};
    _ = fmt.writeBool(&buf, value);
    return try writer.write(&buf);
}

pub fn writeNil(writer: anytype) !usize {
    var buf = [_]u8{0};
    _ = fmt.writeNil(&buf);
    return try writer.write(&buf);
}

fn BufferForNumber(comptime T: type) type {
    const bsize = switch (@bitSizeOf(T)) {
        1...8 => 1,
        9...16 => 2,
        17...32 => 4,
        33...64 => 8,
        else => @compileError(comptimePrint("unsupported {}", .{@typeName(T)})),
    };
    return [bsize + 1]u8;
}

pub fn writeInt(writer: anytype, value: anytype) !usize {
    const T = @TypeOf(value);
    var buf: BufferForNumber(T) = undefined;
    const bsize = fmt.writeInt(T, &buf, value);
    const wsize = try writer.write(buf[0..bsize]);
    return wsize;
}

pub fn writeIntSm(writer: anytype, value: anytype) !usize {
    var buf: BufferForNumber(@TypeOf(value)) = undefined;
    // std.debug.print("writeIntSm value={} buf.len={}\n", .{ value, buf.len });
    const bsize = fmt.writeIntSm(@TypeOf(value), &buf, value);
    const wsize = try writer.write(buf[0..bsize]);
    return wsize;
}

pub fn writeFloat(writer: anytype, value: anytype) !usize {
    const T = @TypeOf(value);
    var buf: BufferForNumber(@TypeOf(value)) = undefined;
    const bsize = fmt.writeFloat(T, &buf, value);
    const wsize = try writer.write(buf[0..bsize]);
    return wsize;
}

pub fn writeFloatSm(writer: anytype, value: anytype) !usize {
    const T = @TypeOf(value);
    var buf: BufferForNumber(@TypeOf(value)) = undefined;
    const bsize = fmt.writeFloatSm(T, &buf, value);
    const wsize = try writer.write(buf[0..bsize]);
    return wsize;
}

pub fn writeArrayPrefix(writer: anytype, length: u32) !usize {
    const prefix = fmt.prefixArray(length);
    const slice = prefix.constSlice();
    return try writer.write(slice);
}

pub fn writeMapPrefix(writer: anytype, length: u32) !usize {
    const prefix = fmt.prefixMap(length);
    const slice = prefix.constSlice();
    return try writer.write(slice);
}

/// Wrapper to read value from a `std.io.GenericReader`.
///
/// The usage is almost same to the `fmt.Unpack`, but you
/// could not peek on this reader. Calling `UnpackReader.next`
/// will read the supplied reader and return the header.
///
/// The `fmt.Unpack.raw` is replaced by `UnpackReader.rawReader` and
/// `UnpackReader.rawDupe` in this structure.
///
/// The data from the supplied reader will be buffered in this reader.
/// The buffer is at least 8 bytes. Bigger buffer increases the reading effieiency.
/// The supplied reader may be read at any time.
///
/// - Concurrency-safe: No
/// - See "src/rewriter.zig" in the code repository for a complete example.
pub const UnpackReader = struct {
    unpack: fmt.Unpack,
    buffer: []u8,
    readsize: usize = 0,

    pub fn init(buffer: []u8) UnpackReader {
        std.debug.assert(buffer.len >= 8);
        return .{
            .unpack = fmt.Unpack.init(&.{}),
            .buffer = buffer,
        };
    }

    /// Peek the next value's type
    fn peek(self: *UnpackReader, reader: anytype) !fmt.HeaderType {
        while (true) {
            return self.unpack.peek() catch |err| switch (err) {
                error.BufferEmpty => {
                    try self.readMore(reader);
                    continue;
                },
                else => err,
            };
        }
    }

    fn resetUnreadToStart(self: *UnpackReader) usize {
        std.mem.copyForwards(u8, self.buffer, self.unpack.rest);
        self.unpack.rest = self.buffer[0..self.unpack.rest.len];
        self.readsize = self.unpack.rest.len;
        return self.readsize;
    }

    /// Get the header of the next value. You can use the header to
    /// identify the value type.
    ///
    /// Return `error.EndOfStream` if the stream is ended.
    pub fn next(self: *UnpackReader, reader: anytype) !fmt.Header {
        const htyp = try self.peek(reader);
        if (htyp.nextComponentSize() > self.unpack.rest.len) {
            try self.readMore(reader);
        }
        return self.unpack.next(htyp);
    }

    fn readMore(self: *UnpackReader, reader: anytype) !void {
        const emptyOfs = self.resetUnreadToStart();
        const restBuffer = self.buffer[emptyOfs..];
        const readsize = try reader.read(restBuffer);
        if (readsize == 0) {
            return error.EndOfStream;
        }
        const nreadsize = self.readsize + readsize;
        const data = self.buffer[0..nreadsize];
        self.unpack.setAppend(self.readsize, data);
        self.readsize = nreadsize;
    }

    pub const ConvertError = fmt.Unpack.ConvertError;

    pub fn nil(self: *UnpackReader, _: anytype, T: type, header: fmt.Header) !T {
        return self.unpack.nil(T, header);
    }

    pub fn @"bool"(self: *UnpackReader, _: anytype, header: fmt.Header) !bool {
        return self.unpack.bool(header);
    }

    pub fn int(self: *UnpackReader, reader: anytype, Int: type, header: fmt.Header) !Int {
        while (header.size > self.unpack.rest.len) {
            try self.readMore(reader);
        }
        return self.unpack.int(Int, header);
    }

    /// Create a reader for the value's raw data.
    ///
    /// This function can be used on any value that have determined
    /// byte size in the header. The arrays and the maps could not be
    /// read with this function.
    /// To skip arrays and maps, see `skip`.
    ///
    /// Errors:
    /// - `ConvertError.InvalidValue` - the value could not be
    ///     converted to this host type
    ///
    /// ```zig
    /// var unpacker: *UnpackReader;
    /// const reader: std.io.AnyReader;
    /// var buf: std.ArrayList(u8);
    ///
    /// const head = try unpacker.next(reader);
    /// var rawReader = try unpacker.rawReader(reader, head);
    ///
    /// try rawReader.reader().readAllArrayList(&buf, 4096);
    /// ```
    pub fn rawReader(self: *UnpackReader, reader: anytype, header: fmt.Header) !RawReader(@TypeOf(reader)) {
        switch (header.type) {
            .map, .array, .fixmap, .fixarray => return ConvertError.InvalidValue,
            else => {},
        }

        const prefixSize = @min(self.unpack.rest.len, header.size);
        const prefix = self.unpack.rest[0..prefixSize];
        self.unpack.rest = self.unpack.rest[prefixSize..];

        return RawReader(@TypeOf(reader)).init(prefix, reader, header.size);
    }

    /// Read the raw and dupe into a slice.
    /// The caller owns the slice.
    ///
    /// Errors:
    /// - `error.StreamTooLong`
    /// - `ConvertError.InvalidValue` - the value could not be
    ///     converted to this host type
    /// - from `Allocator.Error`
    /// - from the reader's error
    pub fn rawDupe(
        self: *UnpackReader,
        reader: anytype,
        allocator: Allocator,
        header: fmt.Header,
        maxSize: usize,
    ) ![]const u8 {
        var list = std.ArrayList(u8).init(allocator);
        errdefer list.deinit();

        var r = try self.rawReader(reader, header);
        try r.reader().readAllArrayList(&list, maxSize);

        return list.toOwnedSlice();
    }

    pub fn float(self: *UnpackReader, reader: anytype, Float: type, header: fmt.Header) !Float {
        while (header.size > self.unpack.rest.len) {
            try self.readMore(reader);
        }

        return self.unpack.float(Float, header);
    }

    pub fn array(self: *UnpackReader, header: fmt.Header) !ArrayReader {
        if (header.type == .array or header.type == .fixarray)
            return ArrayReader.init(self, header.size);
        return ConvertError.InvalidValue;
    }

    pub fn map(self: *UnpackReader, header: fmt.Header) !MapReader {
        if (header.type == .map or header.type == .fixmap)
            return MapReader.init(self, header.size);
        return ConvertError.InvalidValue;
    }

    /// Skip the current value.
    ///
    /// Errors:
    /// - `error.EndOfStream` - the stream is ended
    /// - from the reader's error
    pub fn skip(self: *UnpackReader, reader: anytype, header: fmt.Header) !void {
        switch (header.type) {
            .array, .fixarray => {
                var r = try self.array(header);

                while (r.next(reader) catch |err| switch (err) {
                    error.EndOfStream => null,
                    else => return err,
                }) |head| {
                    try self.skip(reader, head);
                }
            },
            .map, .fixmap => {
                var r = try self.map(header);

                while (r.next(reader) catch |err| switch (err) {
                    error.EndOfStream => null,
                    else => return err,
                }) |head| {
                    try self.skip(reader, head);
                }
            },
            else => {
                var r = self.rawReader(reader, header) catch unreachable;
                try r.reader().skipBytes(header.size, .{});
            },
        }
    }

    test skip {
        const t = std.testing;

        var content: std.BoundedArray(u8, fmt.PREFIX_BUFSIZE * 1 + "Hello".len) = .{};
        _ = try writeString(content.writer(), "Hello");
        var stream = std.io.fixedBufferStream(content.constSlice());

        var buf: [256]u8 = undefined;
        var unpacker = UnpackReader.init(&buf);
        const head = try unpacker.next(stream.reader());
        const value = try unpacker.rawDupe(stream.reader(), t.allocator, head, 256);
        defer t.allocator.free(value);
        try t.expectEqualStrings("Hello", value);
    }

    test "skip returns error.EndOfStream if the stream is ended early" {
        const t = std.testing;

        var content: std.BoundedArray(u8, fmt.PREFIX_BUFSIZE * 1 + "Hello".len) = .{};
        _ = try writeString(content.writer(), "Hello");
        var stream = std.io.fixedBufferStream(content.constSlice()[0 .. content.len - 1]);

        var buf: [256]u8 = undefined;
        var unpacker = UnpackReader.init(&buf);
        const head = try unpacker.next(stream.reader());
        try t.expectError(
            error.EndOfStream,
            unpacker.skip(stream.reader(), head),
        );
    }
};

/// The reader reads a raw value.
/// This type enables streaming the raw value from a reader.
pub fn RawReader(Reader: type) type {
    const LitmitedReader = std.io.LimitedReader(Reader);
    const BufferReader = std.io.FixedBufferStream([]const u8);

    return struct {
        streamReader: LitmitedReader,
        bufReader: BufferReader,

        pub fn init(prefix: []const u8, streamReader: Reader, nbytes: u64) @This() {
            return .{
                .streamReader = std.io.limitedReader(streamReader, nbytes - prefix.len),
                .bufReader = std.io.fixedBufferStream(prefix),
            };
        }

        pub fn read(self: *@This(), dest: []u8) !usize {
            const readsize0 = try self.bufReader.read(dest);
            const dest1 = dest[readsize0..];
            if (dest1.len > 0) {
                const readsize1 = try self.streamReader.read(dest1);
                return readsize0 + readsize1;
            }
            return readsize0;
        }

        pub const ReaderPtr = std.io.GenericReader(*@This(), LitmitedReader.Error || BufferReader.ReadError, read);

        pub fn reader(self: *@This()) ReaderPtr {
            return ReaderPtr{ .context = self };
        }
    };
}

/// The reader reads an array.
///
/// Use `ArrayReader.next` to grab the header and
/// use the `ArrayReader.reader` to read the value.
///
/// Example:
///
/// Code below adds the raw values into an array list.
///
/// ```zig
/// var ar = try valueReader.array(header);
///
/// var list = std.ArrayList([]const u8).init(allocator);
///
/// while (try ar.next()) |head| {
///     const str = try ar.reader.rawDupe(reader, allocator, head, 16384);
///     errdefer allocator.free(str);
///     try list.append(str);
/// }
/// ```
pub const ArrayReader = struct {
    reader: *UnpackReader,
    current: u32 = 0,
    len: u32,

    pub fn init(reader: *UnpackReader, len: u32) ArrayReader {
        return .{
            .reader = reader,
            .len = len,
        };
    }

    /// Get the next element header of this array.
    ///
    /// Return `null` if the array is ended, `error.EndOfStream` if
    /// the reader can no longer read.
    ///
    /// Errors:
    /// - from `UnpackReader.next`
    pub fn next(self: *ArrayReader, reader: anytype) !?fmt.Header {
        if (self.current >= self.len) {
            return null;
        }

        const value = try self.reader.next(reader);
        self.current += 1;
        return value;
    }

    pub fn skipAll(self: *ArrayReader, reader: anytype) !u32 {
        const c0 = self.current;

        while (self.next(reader) catch |err| switch (err) {
            error.EndOfStream => null,
            else => return err,
        }) |head| {
            try self.reader.skip(reader, head);
        }

        return self.current - c0;
    }
};

/// The reader reads a map.
///
/// This type works almost like the `ArrayReader`. You can use
/// `MapReader.is_value` to check the current value is either
/// key or value. Note: the result is undefined before the first
/// call of the `MapReader.next`.
///
///
/// Example:
///
/// Code below adds the raw key-value pairs into a hash map.
///
/// ```zig
/// var mr = try valueReader.map(header);
/// var hmap = std.StringHashMap([]const u8).init(allocator);
///
/// while (try mr.next(reader)) |head| {
///     const key = try mr.reader.rawDupe(reader, allocator, head, 16384);
///     const valueHeader = (try mr.next(reader)) orelse unreachable;
///     const value = try mr.reader.rawDupe(reader, allocator, valueHeader, 16384);
///     try hmap.put(key, value);
/// }
/// ```
pub const MapReader = struct {
    reader: *UnpackReader,
    current: u32 = 0,
    len: u32,
    /// If the current value is key or value.
    ///
    /// The value is undefined before the first call of the `next`.
    is_value: bool = false,

    pub fn init(reader: *UnpackReader, len: u32) MapReader {
        return .{
            .reader = reader,
            .len = len,
        };
    }

    /// Get the next element header of this array.
    ///
    /// Return `null` if the array is ended, `error.EndOfStream` if
    /// the reader can no longer read.
    pub fn next(self: *MapReader, reader: anytype) !?fmt.Header {
        if (self.current >= self.len) {
            return null;
        }

        const value = try self.reader.next(reader);
        if (self.is_value)
            self.current += 1;
        self.is_value = !self.is_value;
        return value;
    }

    pub fn skipAll(self: *MapReader, reader: anytype) !u32 {
        const c0 = self.current;

        while (self.next(reader) catch |err| switch (err) {
            error.EndOfStream => null,
            else => return err,
        }) |head| {
            try self.reader.skip(reader, head);
        }

        return self.current - c0;
    }
};

test {
    _ = UnpackReader;
}
