enum PluckRole: CaseIterable {
    case syncopation, downbeat, upbeat

    private func favors(step: Int) -> Bool {
        let subdivision = step % 4
        switch self {
        case .syncopation: return subdivision == 1 || subdivision == 3
        case .downbeat: return subdivision == 0
        case .upbeat: return subdivision == 2
        }
    }

    private func windows(for phraseBar: Int) -> [Range<Int>] {
        // Each role has an opening accent, a bar of rest, and a late phrase ending.
        switch (self, phraseBar) {
        case (.downbeat, 0): [0..<1, 8..<16]
        case (.downbeat, 2): [0..<8, 8..<16]
        case (.downbeat, 3): [8..<16]
        case (.upbeat, 0): [0..<4, 8..<16]
        case (.upbeat, 1): [12..<16]
        case (.upbeat, 3): [8..<16]
        case (.syncopation, 0): [2..<4, 8..<12]
        case (.syncopation, 2): [2..<6, 10..<14]
        case (.syncopation, 3): [12..<16]
        default: []
        }
    }

    func accents(for melody: [Note], phraseBar: Int, sparse: Bool, stress: BarStress) -> [Note] {
        let candidates = melody.map { (note: $0, step: Int(($0.beat * 4).rounded())) }
            .filter { favors(step: $0.step) }
        let windows = windows(for: phraseBar)
        return windows.prefix(sparse ? 1 : windows.count).enumerated().compactMap { index, window in
            let best = candidates.filter { window.contains($0.step) }.max { first, second in
                if phraseBar == 3 && first.note.pitch != second.note.pitch {
                    return first.note.pitch < second.note.pitch
                }
                let firstScore = Int(first.note.pitch) * 3 + stress.pulse(at: first.step)
                let secondScore = Int(second.note.pitch) * 3 + stress.pulse(at: second.step)
                if firstScore == secondScore { return first.step > second.step }
                return firstScore < secondScore
            }
            guard let lead = best?.note else { return nil }
            let strength = [78, 65, 74, 70][phraseBar] - index * 10
            return Note(voice: .plucks, pitch: lead.pitch + 12, velocity: UInt8(Int(lead.velocity) * strength / 100),
                        beat: lead.beat, duration: lead.duration * 0.68)
        }
    }
}
