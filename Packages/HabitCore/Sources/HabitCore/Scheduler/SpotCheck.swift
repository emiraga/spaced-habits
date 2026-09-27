import Foundation

/// Spot checks (DESIGN.md §4.2 rule 5): decided once per (habit, day) from a stable hash, so every
/// planner run on every device agrees and the effective rate stays at `Settings.spotCheckRate`.
public enum SpotCheck {
    /// Spot checks only apply once the ask interval is longer than this.
    public static let minAskIntervalDays = 7

    /// Uniform-looking value in `0..<1` for `(habitID, day)`. Stable across processes, launches and
    /// platforms: SplitMix64 finalizers over the UUID bytes (big-endian) and the day number, not `Hasher`.
    public static func draw(habitID: UUID, day: DayKey) -> Double {
        let bytes = habitID.uuid
        let high = [bytes.0, bytes.1, bytes.2, bytes.3, bytes.4, bytes.5, bytes.6, bytes.7]
            .reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        let low = [bytes.8, bytes.9, bytes.10, bytes.11, bytes.12, bytes.13, bytes.14, bytes.15]
            .reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        let dayBits = UInt64(bitPattern: Int64(day.dayNumber))
        let hash = mix(high ^ mix(low ^ mix(dayBits)))
        return Double(hash >> 11) * 0x1p-53
    }

    public static func isSpotCheck(habitID: UUID, day: DayKey, rate: Double) -> Bool {
        draw(habitID: habitID, day: day) < rate
    }

    private static func mix(_ value: UInt64) -> UInt64 {
        var mixed = value &+ 0x9E37_79B9_7F4A_7C15
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}
