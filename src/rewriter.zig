// SPDX: Apache-2.0
// This file is part of zigpak.
const std = @import("std");
const zigpak = @import("zigpak");

fn rewriteValue(
    reader: anytype,
    writer: anytype,
    values: *zigpak.UnpackReader,
    h: zigpak.Header,
) !void {
    switch (h.type.family()) {
        .nil => {
            _ = try values.nil(reader, ?*anyopaque, h);
            _ = try zigpak.Nil.pipe(writer);
        },
        .bool => _ = try zigpak.Bool.pipe(writer, try values.bool(reader, h)),
        .int => _ = try zigpak.SInt.pipeSm(writer, try values.int(reader, i64, h)),
        .uint => _ = try zigpak.UInt.pipeSm(writer, try values.int(reader, u64, h)),
        .float => _ = try zigpak.AnyFloat.pipeSm(writer, try values.float(reader, f64, h)),
        .str => {
            var strReader = try values.rawReader(reader, h);
            var strbuf: [4096]u8 = undefined;
            _ = try zigpak.AnyStr.pipe(writer, h.size);
            while (true) {
                const readsize = try strReader.read(&strbuf);
                if (readsize == 0) {
                    break;
                }
                _ = try writer.write(strbuf[0..readsize]);
            }
        },
        .bin => {
            var strReader = try values.rawReader(reader, h);
            var strbuf: [4096]u8 = undefined;
            _ = try zigpak.AnyBin.pipe(writer, h.size);
            while (true) {
                const readsize = try strReader.read(&strbuf);
                if (readsize == 0) {
                    break;
                }
                _ = try writer.write(strbuf[0..readsize]);
            }
        },
        .array => {
            var array = try values.array(h);
            _ = try zigpak.AnyArray.pipe(writer, array.len);
            while (try array.next(reader)) |elementh| {
                try rewriteValue(reader, writer, values, elementh);
            }
        },
        .map => {
            var map = try values.map(h);
            _ = try zigpak.AnyMap.pipe(writer, map.len);
            while (try map.next(reader)) |keyh| {
                try rewriteValue(reader, writer, map.reader, keyh);
                const valueh = try map.next(reader) orelse return error.InvalidValue;
                try rewriteValue(reader, writer, map.reader, valueh);
            }
        },
        else => return error.Unsupported,
    }
}

fn rewrite(reader: anytype, writer: anytype) !void {
    var buffer: [zigpak.UnpackReader.RECOMMENDED_BUFFER_SIZE]u8 = undefined;
    var vread = zigpak.UnpackReader.init(&buffer);
    while (true) {
        const h = try vread.next(reader);
        try rewriteValue(reader, writer, &vread, h);
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);

    const out = std.io.getStdOut();
    const in = std.io.getStdIn();

    var output = std.ArrayList(u8).init(gpa.allocator());
    defer output.deinit();

    rewrite(in.reader(), output.writer()) catch |err| switch (err) {
        error.EndOfStream => {},
        else => return err,
    };

    _ = try out.write(output.items);
}
