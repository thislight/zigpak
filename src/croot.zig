// SPDX: Apache-2.0
// This file is part of zigpak.
const std = @import("std");
const zigpak = @import("zigpak");

const zigpak_unpack = extern struct {
    buffer: [*]const u8,
    len: usize,

    fn toSlice(self: @This()) []const u8 {
        return self.buffer[0..self.len];
    }

    fn fromSlice(slice: []const u8) zigpak_unpack {
        return zigpak_unpack{
            .buffer = slice.ptr,
            .len = slice.len,
        };
    }

    fn toUnpack(self: @This()) zigpak.fmt.Unpack {
        return zigpak.fmt.Unpack{ .rest = self.toSlice() };
    }
};

export fn zigpak_unpack_init(buffer: ?[*]const u8, len: usize) zigpak_unpack {
    return zigpak_unpack{
        .buffer = buffer.?,
        .len = len,
    };
}

export fn zigpak_unpack_set_append(self: *zigpak_unpack, olen: usize, buffer: [*]const u8, len: usize) void {
    var nunpack = self.toUnpack();
    nunpack.setAppend(
        olen,
        buffer[0..len],
    );

    self.buffer = nunpack.rest.ptr;
    self.len = nunpack.rest.len;
}
