/// Injected randomness (DESIGN.md §3.1). Engine code draws through a `RandomSource` passed `inout`,
/// never through the global `.random()` helpers, so simulations are reproducible.
public protocol RandomSource: RandomNumberGenerator, Sendable {}

public extension RandomSource {
    /// Uniform in `0..<1`.
    mutating func nextUnit() -> Double {
        Double.random(in: 0 ..< 1, using: &self)
    }

    /// True with probability `probability` (clamped to 0...1).
    mutating func bernoulli(_ probability: Double) -> Bool {
        nextUnit() < probability
    }
}

/// Production randomness backed by the system CSPRNG.
public struct SystemRandomSource: RandomSource {
    private var generator = SystemRandomNumberGenerator()

    public init() {}

    public mutating func next() -> UInt64 {
        generator.next()
    }
}

/// SplitMix64: tiny, fast, fully deterministic for a given seed. For tests and simulations.
public struct SeededRandomSource: RandomSource {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}
