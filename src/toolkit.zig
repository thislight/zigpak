const ContainerType = @import("./root.zig").ContainerType;

pub fn makeFixIntPos(value: u7) u8 {
    return ~ContainerType.MASK_FIXED_INT_POSITIVE & value;
}

pub fn makeFixIntNeg(value: i6) u8 {
    return @intFromEnum(ContainerType.fixed_int_negative) | (~ContainerType.MASK_FIXED_INT_NEGATIVE & @as(u8, @intCast(@abs(value))));
}

pub fn countIntByteRounded(signed: bool, bits: u16) u8 {
    return if (signed) switch (bits) {
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
}
