const std = @import("std");

const Nil = @This();

pub fn count() usize {
    return 1;
}

pub fn pipe(writer: anytype) !usize {
    _ = try writer.writeByte(0xc0);
    return 1;
}

pub fn write(dst: []u8) usize {
    dst[0] = 0xc0;
    return 1;
}

test write {
    const t = std.testing;
    var buf: [1]u8 = .{0};
    const size = Nil.write(&buf);
    try t.expectEqual(@as(usize, 1), size);
    try t.expectEqual(@as(u8, 0xc0), buf[0]);
}
