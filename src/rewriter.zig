const std = @import("std");
const zigpak = @import("zigpak");

fn replicate(reader: anytype, writer: anytype) !void {
    var buffer: [4096]u8 = undefined;
    var vread = zigpak.io.ValueReader.init(&buffer);
    while (true) {
        const h = try vread.next(reader);
        switch (h.type.family()) {
            .nil => _ = try zigpak.io.writeNil(writer),
            .bool => _ = try zigpak.io.writeBool(writer, try vread.bool(reader, h)),
            .int => _ = try zigpak.io.writeIntSm(writer, try vread.int(reader, i64, h)),
            .uint => _ = try zigpak.io.writeIntSm(writer, try vread.int(reader, u64, h)),
            .float => _ = try zigpak.io.writeFloat(writer, try vread.float(reader, f64, h)),
            else => return error.Unsupported,
        }
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);

    const out = std.io.getStdOut();
    const in = std.io.getStdIn();

    var output = std.ArrayList(u8).init(gpa.allocator());
    defer output.deinit();

    replicate(in.reader(), output.writer()) catch |err| switch (err) {
        error.EndOfStream => {},
        else => return err,
    };

    _ = try out.write(output.items);
}
