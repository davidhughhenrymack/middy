/// A reusable 16th-note accent map and four-bar dynamic contour for a phrase.
struct BarStress {
    private let beats: [Int]
    private let subdivisions: [Int]
    private let bars: [Int]

    init<R: RandomNumberGenerator>(using random: inout R) {
        beats = [[9, -3, 5, -1], [7, -4, 1, 8], [9, 2, -4, 6]].randomElement(using: &random)!
        subdivisions = [[0, -7, 3, -3], [0, -5, -2, 6], [0, 2, 5, -6]].randomElement(using: &random)!
        bars = [[1, -4, 3, 7], [4, 0, -5, 6], [1, 4, -3, 8]].randomElement(using: &random)!
    }

    func pulse(at step: Int) -> Int { beats[step / 4] + subdivisions[step % 4] }

    func perform<R: RandomNumberGenerator>(
        _ notes: [Note], bar: Int, using random: inout R
    ) -> [Note] {
        let swell = bars[bar % bars.count]
        return notes.map { note in
            let step = Int((note.beat * 4).rounded())
            let pulse = pulse(at: step)
            let kick = note.voice == .drums && note.pitch == DrumPad.kick.rawValue
            let swing = step.isMultiple(of: 2) ? 0.0 : 0.012
            let accent: Int
            let delay: Double
            switch note.voice {
            case .lead, .bass, .subBass, .plucks, .formants:
                accent = pulse + swell
                delay = swing + Double.random(in: 0...0.010, using: &random)
            case .drums:
                accent = pulse / 3 + swell / 2
                delay = kick ? 0 : swing + Double.random(in: 0...0.020, using: &random)
            case .pad, .drone:
                accent = note.voice == .pad ? swell / 3 : swell
                delay = Double.random(in: 0...0.009, using: &random)
            }
            let variation = note.voice == .pad ? -3...3 : -5...5
            let velocity = Int(note.velocity) + accent + Int.random(in: variation, using: &random)
            let beat = note.beat + delay
            let gate = note.duration + Double.random(in: -0.008...0.008, using: &random)
            let sustainsAcrossBars = note.voice == .drone
                || (note.voice == .pad && note.duration > AcidPattern.beatsPerBar)
            let duration = sustainsAcrossBars ? gate : min(AcidPattern.beatsPerBar - beat - 0.002, gate)
            return Note(voice: note.voice, pitch: note.pitch, velocity: UInt8(max(1, min(127, velocity))),
                        beat: beat, duration: duration)
        }
    }
}
