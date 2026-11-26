/// The single random stream for a performance, implemented with SplitMix64.
public struct ArrangementRandom: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        let first = (state ^ (state >> 30)) &* 0xBF58476D1CE4E5B9
        let second = (first ^ (first >> 27)) &* 0x94D049BB133111EB
        return second ^ (second >> 31)
    }
}
