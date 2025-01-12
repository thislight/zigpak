//! Optimized prefix.
//!
//! This is implemented as the BoundedArray, but is not copied-and-pasted.
//! The functions here are unchecked by default.
const std = @import("std");

buffer: [6]u8 = undefined,
len: u3 = 0,

const Prefix = @This();

pub fn constSlice(self: Prefix) []const u8 {
    return self.buffer[0..self.len];
}

pub fn slice(self: *Prefix) []u8 {
    return self.buffer[0..self.len];
}

pub fn unusedCapacitySlice(self: *Prefix) []u8 {
    return self.buffer[self.len..];
}

pub fn checkedAppend(self: *Prefix, item: u8) error{BufOverflow}!void {
    if (self.len > std.math.maxInt(u3) - 1) {
        return error.BufOverflow;
    }
    self.unusedCapacitySlice()[0] = item;
    self.len += 1;
}

pub fn append(self: *Prefix, item: u8) void {
    return self.checkedAppend(item) catch unreachable;
}

pub fn checkedAppendSlice(self: *Prefix, items: []const u8) error{BufOverflow}!void {
    if (std.math.maxInt(u3) - self.len < items.len) {
        return error.BufOverflow;
    }
    std.mem.copyForwards(u8, self.unusedCapacitySlice(), items);
    self.len += @truncate(items.len);
}

pub fn appendSlice(self: *Prefix, items: []const u8) void {
    return self.checkedAppendSlice(items) catch unreachable;
}

pub fn checkedWriteInt(self: *Prefix, T: type, value: T, endian: std.builtin.Endian) error{BufOverflow}!void {
    const intsz = @divExact(@bitSizeOf(T), 8);
    if (std.math.maxInt(u3) - self.len < intsz) {
        return error.BufOverflow;
    }
    std.mem.writeInt(T, self.unusedCapacitySlice()[0..intsz], value, endian);
    self.len += intsz;
}

pub fn writeInt(self: *Prefix, T: type, value: T, endian: std.builtin.Endian) void {
    return self.checkedWriteInt(T, value, endian) catch unreachable;
}

pub fn fromSlice(value: []const u8) Prefix {
    var result: Prefix = .{
        .len = @intCast(value.len),
    };
    std.mem.copyForwards(u8, &result.buffer, value);
    return result;
}

pub const WriteError = error{BufOverflow};

fn write(self: *Prefix, items: []const u8) WriteError!usize {
    const dest = self.unusedCapacitySlice();
    if (items.len > slice.len) {
        return WriteError.BufferOverflow;
    }
    @memcpy(dest, items);
    self.len += @truncate(items.len);
    return items.len;
}

pub const Writer = std.io.GenericWriter(*Prefix, WriteError, write);

pub fn writer(self: *Prefix) Writer {
    return Writer{ .context = self };
}
