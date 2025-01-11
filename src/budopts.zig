/// The lookup table optimization target.
///
/// Use lookup table to workaround some performance issues,
/// like the mispredict problem, in exchange of program size.
///
/// Please be adviced that lookup tables do not always boost
/// performance. While using lookup tables, behaviour may not be
/// completely same to the spec.
pub const LookupTableOptimize = enum {
    /// Don't use lookup table if possible.
    ///
    /// This option is recommended for all modern targets.
    none,
    /// Use small lookup tables (<= 64 bytes for each function, assume usize is 8 bytes).
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
