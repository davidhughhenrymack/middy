public enum Root: Int, CaseIterable, Sendable {
    case c, cSharp, d, dSharp, e, f, fSharp, g, gSharp, a, aSharp, b

    public var name: String {
        ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"][rawValue]
    }

    public func relatedMinor<R: RandomNumberGenerator>(using random: inout R) -> Root {
        // Adjacent minor keys on the circle of fifths share six pitch classes.
        let fifth = Bool.random(using: &random) ? 7 : 5
        return Root(rawValue: (rawValue + fifth) % 12)!
    }
}

enum MinorScale {
    static func semitones(at degree: Int) -> Int {
        let scale = [0, 2, 3, 5, 7, 8, 10]
        let index = (degree % 7 + 7) % 7
        return (degree - index) / 7 * 12 + scale[index]
    }
}

public enum Algorithm: String, CaseIterable, Sendable {
    case acid = "Acid"
}

public struct PatternSettings: Equatable, Sendable {
    public var algorithm: Algorithm = .acid
    public var root: Root = .c

    public var leadOctave = 0
    public var bassOctave = 0
    public var padOctave = 0
    public var padEnabled = true

    public init() {}
}

public enum Voice: UInt8, CaseIterable, Sendable {
    case lead = 1
    case bass = 2
    case drums = 3
    case pad = 4
    case subBass = 5
    case drone = 6
    case plucks = 7
    case formants = 8
}

public enum DrumPad: UInt8, CaseIterable, Sendable {
    case kick = 36
    case snare = 38
    case clap = 39
    case closedHat = 42
    case cymbal = 49
    case tambourine = 54
    case shaker = 82
}

public struct Note: Equatable, Sendable {
    public let voice: Voice
    public let pitch: UInt8
    public let velocity: UInt8
    public let beat: Double
    public let duration: Double
}

public enum AcidPattern {
    public static let beatsPerBar = 4.0
    private static let step = 0.25

    struct LeadAttack {
        let step: Int
        let duration: Double
        let velocity: UInt8
    }

    static func motif<R: RandomNumberGenerator>(
        excluding previous: [[Int]], using random: inout R
    ) -> [Int] {
        let used = Set(previous.map { $0.map { $0 == 0 ? 0 : 1 } })
        let contours = (1..<8).map { mask in
            [0, mask & 1, (mask >> 1) & 1, (mask >> 2) & 1]
        }
        let contour = contours.filter { !used.contains($0) }.randomElement(using: &random)!
        let direction = Bool.random(using: &random) ? 1 : -1
        let interval = Int.random(in: 0..<3, using: &random) == 0 ? 2 : 1
        return contour.map { $0 * direction * interval }
    }

    static func progression<R: RandomNumberGenerator>(
        for motif: [Int], startingAt start: Int, using random: inout R
    ) -> [Int] {
        var anchors = [start]
        for _ in 0..<3 {
            let anchor = anchors.last!
            let last = anchor + motif.last!
            let candidates = [-4, -3, -2, 2, 3, 4].map { anchor + $0 }.filter { candidate in
                (-3...7).contains(candidate)
                    && abs(MinorScale.semitones(at: candidate) - MinorScale.semitones(at: last)) <= 7
            }
            anchors.append(candidates.randomElement(using: &random)!)
        }
        return anchors
    }

    static func leadRhythm<R: RandomNumberGenerator>(accentStep: Int, using random: inout R) -> [LeadAttack] {
        let sparseBeat = Int.random(in: 1...2, using: &random)
        let passingSteps = [[1], [3], [1, 3]].randomElement(using: &random)!
        let steps = (0..<16).filter { index in
            let beat = index / 4
            let subdivision = index % 4
            return beat == 0 || beat == 3 || subdivision == accentStep
                || (beat != sparseBeat && passingSteps.contains(subdivision))
        }
        return zip(steps, steps.dropFirst() + [16]).map { index, next in
            let accented = index % 4 == accentStep
            let gap = Double(next - index) * step
            let lengths = accented ? [0.35, 0.48, 0.63] : [0.08, 0.13, 0.18]
            let gate = min(gap - 0.045, lengths.randomElement(using: &random)!)
            return LeadAttack(step: index, duration: gate, velocity: accented ? 104 : 65)
        }
    }

    static func lead(motif: [Int], anchors: [Int], rhythm: [LeadAttack], root: Root, octave: Int) -> [Note] {
        rhythm.map { attack in
            let degree = anchors[attack.step / 4] + motif[attack.step % 4]
            let pitch = 60 + root.rawValue + MinorScale.semitones(at: degree) + octaveShift(octave)
            return Note(voice: .lead, pitch: UInt8(pitch), velocity: attack.velocity,
                        beat: Double(attack.step) * step, duration: attack.duration)
        }
    }

    static func octaveShift(_ offset: Int) -> Int { min(2, max(-2, offset)) * 12 }

    static func bassRhythm<R: RandomNumberGenerator>(
        stress: BarStress, reserveOffbeat: Bool, using random: inout R
    ) -> [Note] {
        let offbeat = reserveOffbeat ? [2, 6, 10, 14].randomElement(using: &random) : nil
        var notes: [Note] = []
        var index = 0
        while index < 16 {
            let accent = stress.pulse(at: index)
            let restChance = min(72, max(20, 43 - accent * 3))
            if index > 0 && index != offbeat && Int.random(in: 0..<100, using: &random) < restChance {
                index += 1
                continue
            }
            let lengths = accent >= 5 ? [1, 2, 2, 3] : [1, 1, 2, 3]
            let boundary = offbeat.flatMap { $0 > index ? $0 : nil } ?? 16
            let length = min(lengths.randomElement(using: &random)!, boundary - index)
            let velocity: UInt8 = accent >= 5 ? 97 : 84
            notes.append(Note(voice: .bass, pitch: 36, velocity: velocity,
                              beat: Double(index) * step, duration: Double(length) * step - 0.035))
            index += length
        }
        return notes
    }
}
