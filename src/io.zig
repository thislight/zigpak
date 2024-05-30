// SPDX: Apache-2.0
// This file is part of zigpak.
const fmt = @import("./fmt.zig");
const std = @import("std");
const log2IntCeil = std.math.log2_int_ceil;
const divCeil = std.math.divCeil;
const comptimePrint = std.fmt.comptimePrint;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

pub fn writeString(writer: anytype, src: []const u8) !usize {
    const header = try fmt.prefixString(src.len);
    const size1 = try writer.write(header.toSlice());
    const size2 = try writer.write(src);
    return size1 + size2;
}

pub fn writeBinary(writer: anytype, src: []const u8) !usize {
    const header = try fmt.prefixBinary(src.len);
    const size1 = try writer.write(header.toSlice());
    const size2 = try writer.write(src);
    return size1 + size2;
}

pub fn writeExt(writer: anytype, extype: i8, payload: []const u8) !usize {
    const header = try fmt.prefixExt(payload.len, extype);
    const size1 = try writer.write(header.toSlice());
    const size2 = try writer.write(payload);
    return size1 + size2;
}

fn BufferForNumber(comptime T: type) type {
    const inf = @typeInfo(T);
    const bsize = divCeil(switch (inf) {
        .Int => |i| i.bits,
        .Float => |f| f.bits,
        else => @compileError(comptimePrint("unsupported {}", .{@typeName(T)})),
    }, 8);
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

/// Value reader for [Reader].
///
/// This reader uses dynamic-sized buffer.
/// You can try [std.heap.FixedBufferAllocator] for limiting memory usage.
///
/// This reader does not buffering the input, so multiple reader can be used on one [std.io.Reader].
pub fn ValueReader(comptime Reader: type) type {
    return struct {
        reader: Reader,
        alloc: Allocator,
        currentValue: ?fmt.Value = null,

        const Self = @This();

        pub fn init(reader: Reader, alloc: Allocator) Self {
            return .{
                .reader = reader,
                .alloc = alloc,
            };
        }

        /// Read the next value.
        ///
        /// The returned value is owned by this struct and
        /// will be free'd in the next call of [next] or [deinit].
        pub fn next(self: *Self) !fmt.Value {
            self.freeLastValueAndSet();
            var buffer = try ArrayList(u8).initCapacity(self.alloc, 1);
            defer buffer.deinit();
            var fstBuf = try buffer.addManyAsArray(1);
            _ = try self.reader.read(fstBuf);
            while (true) {
                switch (try fmt.readValue(buffer.items)) {
                    .Incomplete => |bsize| {
                        var s = try buffer.addManyAsSlice(bsize);
                        _ = try self.reader.read(s);
                    },
                    .Value => |result| {
                        const copy = self.dupeValue(result.value);
                        self.currentValue = copy;
                        return copy;
                    },
                }
            }
        }

        fn dupeValue(self: *const Self, value: fmt.Value) !fmt.Value {
            switch (value) {
                // If it's a reference, copy to new memory
                .String, .Binary => |bin| {
                    var copy = try self.alloc.dupe(u8, bin);
                    return @unionInit(fmt.Value, @tagName(value), copy);
                },
                .Ext => |ext| {
                    var copy = try self.alloc.dupe(u8, ext.data);
                    return @unionInit(fmt.Value, "Ext", .{
                        .data = copy,
                        .extype = ext.extype,
                    });
                },
                else => {
                    return value; // it's already a value
                },
            }
        }

        fn freeLastValue(self: *const Self) void {
            if (self.currentValue) |cv| {
                switch (cv) {
                    .String, .Binary => |b| self.alloc.free(b),
                    .Ext => |ext| self.alloc.free(ext.data),
                    else => {},
                }
            }
        }

        fn freeLastValueAndSet(self: *Self) void {
            self.freeLastValue();
            self.currentValue = null;
        }

        pub fn deinit(self: *const Self) void {
            self.freeLastValue();
        }
    };
}
