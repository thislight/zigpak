pub fn count(_: bool) usize {
    return 1;
}

inline fn convert(value: bool) u8 {
    return switch (value) {
        true => 0xc3,
        false => 0xc2,
    };
}

pub fn pipe(writer: anytype, value: bool) !usize {
    _ = try writer.writeByte(convert(value));
    return 1;
}

pub fn write(dst: []u8, value: bool) usize {
    dst[0] = convert(value);
    return 1;
}
