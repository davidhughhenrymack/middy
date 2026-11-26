enum BuildTension {
    enum Intensity: CaseIterable {
        case gentle, rising, peak

        func padVelocity(bar: Int) -> UInt8 {
            switch self {
            case .gentle: [35, 48, 61, 74][bar]
            case .rising: [42, 56, 71, 87][bar]
            case .peak: [43, 60, 78, 97][bar]
            }
        }

        func drumGain(bar: Int) -> Double {
            switch self {
            case .gentle: [0.66, 0.71, 0.76, 0.81][bar]
            case .rising: [0.78, 0.84, 0.89, 0.94][bar]
            case .peak: [0.86, 0.92, 0.97, 1.0][bar]
            }
        }
    }

    static func apply(to notes: [Note], bar: Int, intensity: Intensity) -> [Note] {
        let drumGain = intensity.drumGain(bar: bar)
        let groove = notes.map { note in
            guard note.voice == .drums else { return note }
            return Note(voice: note.voice, pitch: note.pitch, velocity: UInt8(Double(note.velocity) * drumGain),
                        beat: note.beat, duration: note.duration)
        }
        switch (intensity, bar) {
        case (.rising, 1):
            return groove + snareRoll(beats: [3], velocity: 61, gate: 0.08)
        case (.rising, 2):
            let beats = Array(stride(from: 2.0, to: 4, by: 0.5))
            return groove + snareRoll(beats: beats, velocity: 68, gate: 0.08)
        case (.rising, 3):
            let beats = Array(stride(from: 0.0, to: 2, by: 0.5))
                + Array(stride(from: 2.0, to: 3.5, by: 0.25))
            return preDrop(groove, from: 3.5, pickup: 3.75) + snareRoll(beats: beats, velocity: 75, gate: 0.08)
        case (.peak, 1):
            return groove + snareRoll(beats: [2, 3], velocity: 65, gate: 0.08)
        case (.peak, 2):
            let beats = Array(stride(from: 1.0, to: 4, by: 0.5))
            return groove + snareRoll(beats: beats, velocity: 73, gate: 0.08)
        case (.peak, 3):
            let beats = Array(stride(from: 0.0, to: 2, by: 0.25))
                + Array(stride(from: 2.0, to: 3, by: 0.125))
            return preDrop(groove, from: 3, pickup: 3.5) + snareRoll(beats: beats, velocity: 83, gate: 0.05)
        default:
            return groove
        }
    }

    private static func snareRoll(beats: [Double], velocity: Int, gate: Double) -> [Note] {
        beats.enumerated().map { index, beat in
            let accent = index * 14 / max(1, beats.count - 1)
            return Note(voice: .drums, pitch: DrumPad.snare.rawValue, velocity: UInt8(velocity + accent),
                        beat: beat, duration: gate)
        }
    }

    private static func preDrop(_ notes: [Note], from cutoff: Double, pickup: Double) -> [Note] {
        let arrival = notes.first { $0.voice == .lead && $0.beat == 0 }?.pitch
        return notes.compactMap { note in
            if note.beat >= cutoff {
                guard note.voice == .lead, note.beat == pickup else { return nil }
                return Note(voice: .lead, pitch: arrival ?? note.pitch, velocity: 33,
                            beat: note.beat, duration: 0.12)
            }
            let duration = min(note.duration, cutoff - 0.05 - note.beat)
            return Note(voice: note.voice, pitch: note.pitch, velocity: note.velocity,
                        beat: note.beat, duration: duration)
        }
    }
}
