enum DrumPattern {
    static let barsPerLoop = 4

    static func notes(section: Section, bar: Int, sectionBars: Int) -> [Note] {
        let loopBar = bar % barsPerLoop
        switch section {
        case .intro, .outro:
            return transition(at: loopBar)
        case .build:
            return dance(at: bar, verse: false)
        case .verse:
            return dance(at: bar, verse: true)
        case .breakdown:
            let block = bar / Section.textureBars
            guard block != 0 && block != 2 && block != 4 else { return [] }
            return returnFromBreak(at: bar, sectionBars: sectionBars)
        }
    }

    private static func transition(at bar: Int) -> [Note] {
        let hats: [[Double]] = [[0.5, 2.5], [0.5, 2.5, 3.5], [0.5, 1.5, 2.5, 3.5],
                                [0.5, 1.5, 2.5, 3.75]]
        var notes = kick(velocity: 92) + closedHats(at: hats[bar], velocity: 61)
        if bar == 1 { notes.append(hit(.cymbal, at: 0, velocity: 46)) }
        if bar == 3 { notes.append(hit(.cymbal, at: 3.5, velocity: 55)) }
        return notes
    }

    private static func dance(at bar: Int, verse: Bool) -> [Note] {
        let loopBar = bar % barsPerLoop
        var notes = kick(velocity: 112) + closedHats(at: [0.5, 1.5, 2.5, 3.5], velocity: 77)
        notes += [1.0, 3.0].map { hit(.clap, at: $0, velocity: 93) }
        if verse {
            let ghostHats: [[Double]] = [[1.75, 3.75], [0.75, 2.75], [1.75, 2.75], [0.75, 1.75, 2.75, 3.75]]
            let block = bar / Section.textureBars
            let hats = block == 1 ? ghostHats[loopBar] : Array(ghostHats[loopBar].prefix(1))
            notes += closedHats(at: hats, velocity: block == 1 ? 60 : 55)
            notes.append(hit(.snare, at: 3, velocity: 81))
        } else {
            let ghostHats: [[Double]] = [[], [3.75], [1.75], [1.75, 3.75]]
            notes += closedHats(at: ghostHats[loopBar], velocity: 56)
        }
        if loopBar == 0 { notes.append(hit(.cymbal, at: 0, velocity: verse ? 99 : 75)) }
        if verse && loopBar == 2 { notes.append(hit(.cymbal, at: 2, velocity: 71)) }
        if loopBar == 3 {
            notes += [hit(.snare, at: 3.5, velocity: 71), hit(.snare, at: 3.75, velocity: 87)]
            notes.append(hit(.cymbal, at: 3.5, velocity: verse ? 67 : 70))
        }
        if !verse && loopBar == 2 {
            notes += [0.75, 2.75].map { hit(.shaker, at: $0, velocity: 54) }
        } else if verse && bar < 2 * Section.textureBars && bar % Section.textureBars >= barsPerLoop {
            switch loopBar {
            case 1, 2:
                notes += [0.25, 1.25, 2.25, 3.25].map { hit(.shaker, at: $0, velocity: 58) }
            case 3:
                notes += [1.0, 3.0].map { hit(.tambourine, at: $0, velocity: 69) }
            default:
                break
            }
        }
        return notes
    }

    private static func returnFromBreak(at bar: Int, sectionBars: Int) -> [Note] {
        let lastPhrase = bar >= sectionBars - barsPerLoop
        let hits = lastPhrase ? [0.5, 1.5, 2.5, 3.5] : [0.5, 2.5]
        var notes = closedHats(at: hits, velocity: lastPhrase ? 66 : 60)
        if bar == Section.textureBars { notes.append(hit(.cymbal, at: 0, velocity: 45)) }
        if bar == sectionBars - 1 {
            notes += [3.25, 3.5, 3.75].map { hit(.snare, at: $0, velocity: 73) }
            notes.append(hit(.cymbal, at: 3.5, velocity: 58))
        }
        return notes
    }

    private static func kick(velocity: UInt8) -> [Note] {
        (0..<4).map { hit(.kick, at: Double($0), velocity: velocity) }
    }

    private static func closedHats(at beats: [Double], velocity: UInt8) -> [Note] {
        beats.map { hit(.closedHat, at: $0, velocity: velocity) }
    }

    private static func hit(_ pad: DrumPad, at beat: Double, velocity: UInt8) -> Note {
        let duration: Double
        switch pad {
        case .kick: duration = 0.16
        case .cymbal: duration = 0.43
        default: duration = 0.09
        }
        return Note(voice: .drums, pitch: pad.rawValue, velocity: velocity, beat: beat, duration: duration)
    }
}
