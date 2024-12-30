/// The lookup table optimization target.
///
/// Use lookup table to workaround some performance issues,
/// like the mispredict problem, in exchange of program size.
///
/// Please be adviced that lookup tables do not always boost
/// performance.
pub const LookupTableOptimize = enum {
    /// Don't use lookup table if possible.
    ///
    /// This option emits smallest object.
    none,
    /// Use small lookup tables (<= 64 bytes each).
    ///
    /// This may boost performance for certain
    /// platforms.
    small,
    /// Emit all lookup tables.
    ///
    /// This option emits all implemented lookup tables.
    /// This may boost performance for certain
    /// platforms.
    all,
};
