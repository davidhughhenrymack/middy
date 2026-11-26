public enum Section: String, CaseIterable, Sendable {
    case intro = "Intro"
    case build = "Build"
    case verse = "Verse"
    case breakdown = "Breakdown"
    case outro = "Outro"

    static let textureBars = 8
}

public enum PhraseName: String, CaseIterable, Sendable {
    case a = "A"
    case b = "B"
    case c = "C"
    case d = "D"
    case e = "E"
}

public struct ArrangementPosition: Equatable, Sendable {
    public let song: Int
    public let key: Root
    public let section: Section
    public let phrase: PhraseName?
    public let bar: Int
    public let sectionBars: Int
}

public struct ArrangedBar: Sendable {
    public let position: ArrangementPosition
    public let notes: [Note]
}

/// The sequencer owns a single conductor and advances it once per Link-aligned bar.
public final class Conductor {
    private static let phraseLength = 4
    private static let verseBars = 24
    private static let padDuration = 3.85
    private static let breakdownPhrases: [PhraseName] = [.c, .d, .c, .e, .d, .e, .c, .e]

    private struct Phrase {
        let motif: [Int]
        let anchors: [Int]
        let answerShift: Int
        let leadRhythm: [AcidPattern.LeadAttack]
        let bass: [Note]
        let bassPickup: (beat: Double, interval: Int)?
        let chords: [Int]
        let padVoicing: [Int]
        let stress: BarStress
    }

    private enum GrooveAccent: CaseIterable {
        case kick, offbeat

        var step: Int { self == .kick ? 0 : 2 }

        func subNote(following bass: Note, root: UInt8) -> Note {
            let stepInBeat = Int((bass.beat * 4).rounded()) % 4
            let distance = abs(stepInBeat - step)
            let stress = [1.0, 0.34, 0.0][min(distance, 4 - distance)]
            let velocity = 52 + Int(bass.velocity) / 6 + Int(stress * 40)
            return Note(voice: .subBass, pitch: root, velocity: UInt8(velocity),
                        beat: bass.beat, duration: bass.duration * (0.43 + stress * 0.55))
        }
    }

    private struct DroneChord {
        let degrees: [Int]
        let velocity: UInt8
        var remaining: Int

        init(_ degrees: [Int], bars: Int, velocity: UInt8) {
            self.degrees = degrees
            self.velocity = velocity
            self.remaining = bars
        }
    }

    private struct BuildTexture {
        let pad: Bool
        let intensity: BuildTension.Intensity
    }

    private enum VersePads: CaseIterable {
        case opening, reprise, both

        func includes(isReprise: Bool) -> Bool {
            switch self {
            case .opening: !isReprise
            case .reprise: isReprise
            case .both: true
            }
        }
    }

    private struct SectionPlan {
        let section: Section
        let phrase: PhraseName?
        let bars: Int
        var isReprise = false
    }

    private static let sections = [
        SectionPlan(section: .intro, phrase: nil, bars: 4),
        SectionPlan(section: .build, phrase: .a, bars: 4),
        SectionPlan(section: .verse, phrase: .b, bars: verseBars),
        SectionPlan(section: .breakdown, phrase: nil, bars: breakdownPhrases.count * Section.textureBars),
        SectionPlan(section: .build, phrase: .a, bars: 4, isReprise: true),
        SectionPlan(section: .verse, phrase: .b, bars: verseBars, isReprise: true),
        SectionPlan(section: .outro, phrase: nil, bars: 4)
    ]

    private var phrases: [PhraseName: Phrase] = [:]
    private var harmony: SongHarmony?
    private var grooveAccent: GrooveAccent = .kick
    private var pluckRole: PluckRole = .downbeat
    private var openingBuild = BuildTexture(pad: false, intensity: .gentle)
    private var returnBuild = BuildTexture(pad: false, intensity: .gentle)
    private var versePads: VersePads = .both
    private var versePadLengths: [Double] = []
    private var breakdownPad = true
    private var repriseDrone = false
    private var formantCue: (isReprise: Bool, bars: [Int])?
    private var sectionIndex = 0
    private var barIndex = 0
    private var song = 0
    private var key: Root = .c
    private var drone: DroneChord?

    public init() {}

    public func reset<R: RandomNumberGenerator>(root: Root = .c, using random: inout R) {
        key = root
        drone = nil
        makePhrases(using: &random)
        song += 1
        sectionIndex = 0
        barIndex = 0
    }

    public func nextBar<R: RandomNumberGenerator>(
        settings: PatternSettings, resumeDrone: Bool = false, using random: inout R
    ) -> ArrangedBar {
        if phrases.isEmpty { reset(root: settings.root, using: &random) }
        let plan = Self.sections[sectionIndex]
        let phraseName = plan.section == .breakdown ? Self.breakdownPhrases[barIndex / Section.textureBars] : plan.phrase
        let position = ArrangementPosition(song: song, key: key, section: plan.section, phrase: phraseName,
                                           bar: barIndex + 1, sectionBars: plan.bars)
        let phraseBar = barIndex % Self.phraseLength
        let phrase = phrases[phraseName ?? .a]!
        let bassRoot = 36 + key.rawValue + AcidPattern.octaveShift(settings.bassOctave)
        var notes = DrumPattern.notes(section: plan.section, bar: barIndex, sectionBars: plan.bars)

        if phraseName == nil {
            notes += preview(using: phrase, bar: phraseBar, settings: settings)
        } else {
            switch settings.algorithm {
            case .acid:
                let leadsIntoVerse = plan.section == .build && barIndex >= plan.bars - 2
                let leadPhrase = leadsIntoVerse ? (phrases[.b] ?? phrase) : phrase
                notes += lead(for: leadPhrase, bar: leadsIntoVerse ? 0 : barIndex, octave: settings.leadOctave)
                if plan.section == .verse {
                    let pickup = phraseBar.isMultiple(of: 2) ? nil : phrase.bassPickup
                    notes += phrase.bass.map { note in
                        let interval = pickup.flatMap { $0.beat == note.beat ? $0.interval : nil } ?? 0
                        return Note(voice: .bass, pitch: UInt8(bassRoot + interval), velocity: note.velocity,
                                    beat: note.beat, duration: note.duration)
                    }
                }
            }
            if settings.padEnabled, let velocity = padVelocity(for: plan, phraseBar: phraseBar) {
                let duration = plan.section == .verse
                    ? versePadLengths[barIndex / Self.phraseLength] : Self.padDuration
                notes += chord(at: phrase.chords[barIndex % phrase.chords.count], voicing: phrase.padVoicing,
                               beat: 0, duration: duration, velocity: velocity, settings: settings)
            }
        }
        notes += droneNotes(for: plan, resume: resumeDrone)
        let build = plan.isReprise ? returnBuild : openingBuild
        if plan.section == .build {
            notes = BuildTension.apply(to: notes, bar: barIndex, intensity: build.intensity)
        }
        let performed = phrase.stress.perform(notes, bar: phraseBar, using: &random)
        let subBass = performed.filter { $0.voice == .bass }
            .map { grooveAccent.subNote(following: $0, root: UInt8(bassRoot - 12)) }
        let plucks = plan.section == .verse
            ? pluckRole.accents(for: performed.filter { $0.voice == .lead }, phraseBar: phraseBar,
                                sparse: barIndex >= 2 * Section.textureBars, stress: phrase.stress) : []
        let formants = formantReply(for: plan, following: performed)

        barIndex += 1
        if barIndex == plan.bars {
            barIndex = 0
            sectionIndex += 1
            if sectionIndex == Self.sections.count {
                // The outro has already played the new song's intro.
                song += 1
                sectionIndex = 1
            } else if Self.sections[sectionIndex].section == .outro {
                key = key.relatedMinor(using: &random)
                makePhrases(using: &random)
            }
        }
        return ArrangedBar(position: position, notes: performed + subBass + plucks + formants)
    }

    private func makePhrases<R: RandomNumberGenerator>(using random: inout R) {
        let previousHarmony = harmony
        let plan = SongHarmony.plans.filter { $0 != previousHarmony }.randomElement(using: &random)!
        harmony = plan
        let outgoing = [phrases[.a]?.motif, phrases[.b]?.motif].compactMap { $0 }
        let first = AcidPattern.motif(excluding: outgoing, using: &random)
        let second = AcidPattern.motif(excluding: outgoing + [first], using: &random)
        grooveAccent = GrooveAccent.allCases.randomElement(using: &random)!
        phrases = [
            .a: makePhrase(motif: first, anchor: 0, answer: 0,
                           chords: plan.build, padVoicing: plan.padVoicing, using: &random),
            .b: makePhrase(motif: second, anchor: plan.verse[0] + 2, answer: plan.answerShift,
                           chords: plan.verse, padVoicing: plan.padVoicing, using: &random),
            .c: makePhrase(motif: first, anchor: plan.breakdown[0], answer: -plan.answerShift,
                           chords: plan.breakdown, padVoicing: plan.padVoicing, using: &random)
        ]
        openingBuild = BuildTexture(pad: Bool.random(using: &random),
                                    intensity: BuildTension.Intensity.allCases.randomElement(using: &random)!)
        let returnIntensities = BuildTension.Intensity.allCases.filter { $0 != openingBuild.intensity }
        returnBuild = BuildTexture(pad: Int.random(in: 0..<3, using: &random) != 0,
                                   intensity: returnIntensities.randomElement(using: &random)!)
        versePads = VersePads.allCases.randomElement(using: &random)!
        breakdownPad = Int.random(in: 0..<3, using: &random) != 0
        formantCue = nil
        if Int.random(in: 0..<3, using: &random) != 0 {
            let isReprise: Bool
            switch versePads {
            case .opening: isReprise = true
            case .reprise: isReprise = false
            case .both: isReprise = Bool.random(using: &random)
            }
            formantCue = (isReprise, Bool.random(using: &random) ? [7, 23] : [15])
        }
        repriseDrone = Int.random(in: 0..<3, using: &random) == 0

        let chords = plan.breakdown
        phrases[.d] = makePhrase(motif: second, anchor: chords[2] - 2, answer: plan.answerShift,
                                 chords: Array(chords.dropFirst(2) + chords.prefix(2)),
                                 padVoicing: plan.padVoicing, using: &random)
        phrases[.e] = makePhrase(motif: first, anchor: chords[0] - 3, answer: -plan.answerShift,
                                 chords: Array(chords.dropFirst(4) + chords.prefix(4)),
                                 padVoicing: plan.padVoicing, using: &random)
        pluckRole = PluckRole.allCases.randomElement(using: &random)!
        let padLengthOptions = [1.0, 1.0, 1.0, 1.0, 1.0, 0.5, 0.5, 0.25]
        versePadLengths = (0..<(Self.verseBars / Self.phraseLength)).map { _ in
            Self.padDuration * padLengthOptions.randomElement(using: &random)!
        }
    }

    private func makePhrase<R: RandomNumberGenerator>(
        motif: [Int], anchor: Int, answer: Int, chords: [Int], padVoicing: [Int], using random: inout R
    ) -> Phrase {
        let stress = BarStress(using: &random)
        let anchors = AcidPattern.progression(for: motif, startingAt: anchor, using: &random)
        let bass = AcidPattern.bassRhythm(stress: stress, reserveOffbeat: grooveAccent == .offbeat, using: &random)
        let pickups = bass.filter { $0.beat >= 2 && $0.beat.rounded(.down) != $0.beat }
        let pickup: (beat: Double, interval: Int)?
        if Int.random(in: 0..<3, using: &random) != 0, let note = pickups.randomElement(using: &random) {
            pickup = (note.beat, [-2, 7].randomElement(using: &random)!)
        } else {
            pickup = nil
        }
        let leadRhythm = AcidPattern.leadRhythm(accentStep: grooveAccent.step, using: &random)
        return Phrase(motif: motif, anchors: anchors, answerShift: answer, leadRhythm: leadRhythm,
                      bass: bass, bassPickup: pickup,
                      chords: chords, padVoicing: padVoicing, stress: stress)
    }

    private func lead(for phrase: Phrase, bar: Int, octave: Int) -> [Note] {
        let shift = bar % Section.textureBars < Self.phraseLength ? 0 : phrase.answerShift
        return AcidPattern.lead(motif: phrase.motif, anchors: phrase.anchors.map { $0 + shift }, rhythm: phrase.leadRhythm,
                                root: key, octave: octave)
    }

    private func preview(using phrase: Phrase, bar: Int, settings: PatternSettings) -> [Note] {
        let snippets = [8..<11, 0..<0, 0..<4, 12..<16]
        let lead = lead(for: phrase, bar: 0, octave: settings.leadOctave)
        var notes = lead.filter { snippets[bar].contains(Int(($0.beat * 4).rounded())) }.map { note in
            return Note(voice: .lead, pitch: note.pitch, velocity: 37,
                        beat: note.beat, duration: note.duration)
        }
        if settings.padEnabled, bar.isMultiple(of: 2), let verse = phrases[.b] {
            notes += chord(at: verse.chords[bar], voicing: verse.padVoicing,
                           beat: 0.5, duration: 2.6, velocity: 45, settings: settings)
        }
        return notes
    }

    private func padVelocity(for plan: SectionPlan, phraseBar: Int) -> UInt8? {
        switch plan.section {
        case .build:
            let texture = plan.isReprise ? returnBuild : openingBuild
            guard texture.pad else { return nil }
            return texture.intensity.padVelocity(bar: phraseBar) + (plan.isReprise ? 4 : 0)
        case .verse:
            guard versePads.includes(isReprise: plan.isReprise) else { return nil }
            let block = barIndex / Section.textureBars
            if plan.isReprise {
                guard block > 0 else { return nil }
                let level = barIndex < Section.textureBars + 2 ? -11 : (block == 1 ? -4 : 3)
                return UInt8([85, 73, 80, 88][phraseBar] + level)
            }
            guard block < 2 else { return nil }
            let level = barIndex >= 2 * Section.textureBars - 2 ? -10 : (block == 0 ? 0 : -3)
            return UInt8([72, 62, 68, 75][phraseBar] + level)
        case .breakdown:
            guard breakdownPad else { return nil }
            let block = barIndex / Section.textureBars
            guard block != 2 && block != 5 else { return nil }
            return [44, 39, 42, 49][phraseBar] + (block == 0 ? 0 : 5)
        default:
            return nil
        }
    }

    private func formantReply(for plan: SectionPlan, following performed: [Note]) -> [Note] {
        guard plan.section == .verse, let formantCue, plan.isReprise == formantCue.isReprise,
              formantCue.bars.contains(barIndex) else { return [] }

        return performed.compactMap { note in
            guard note.voice == .lead else { return nil }
            let step = Int((note.beat * 4).rounded())
            guard step == 13 || step == 15 else { return nil }
            let velocity = Int(note.velocity) * 3 / 4 + (step == 15 ? 5 : 0)
            return Note(voice: .formants, pitch: 60 + note.pitch % 12, velocity: UInt8(velocity),
                        beat: note.beat, duration: note.duration * 0.78)
        }
    }

    private func droneNotes(for plan: SectionPlan, resume: Bool) -> [Note] {
        let needsChord = drone == nil || drone?.remaining == 0
        if needsChord {
            drone = nil
            guard barIndex == 0, let harmony else { return [] }
            switch plan.section {
            case .intro, .outro:
                drone = DroneChord(harmony.droneVoicing, bars: 4, velocity: 43)
            case .verse where plan.isReprise && repriseDrone:
                drone = DroneChord(harmony.droneVoicing, bars: 8, velocity: 48)
            case .breakdown:
                drone = DroneChord(harmony.droneVoicing.map { $0 + harmony.breakdown[0] }, bars: 8, velocity: 58)
            default:
                return []
            }
        }
        guard var chord = drone else { return [] }
        let duration = Double(chord.remaining) * AcidPattern.beatsPerBar - 0.15
        chord.remaining -= 1
        drone = chord
        guard needsChord || resume else { return [] }
        return chord.degrees.enumerated().map { index, degree in
            let pitch = 48 + key.rawValue + MinorScale.semitones(at: degree)
            let delay = Double(index) * 0.026
            return Note(voice: .drone, pitch: UInt8(pitch), velocity: chord.velocity,
                        beat: delay, duration: duration - delay)
        }
    }

    private func chord(
        at degree: Int, voicing: [Int], beat: Double, duration: Double, velocity: UInt8,
        settings: PatternSettings
    ) -> [Note] {
        let root = 48 + key.rawValue + AcidPattern.octaveShift(settings.padOctave)
        return voicing.enumerated().map { voice, interval in
            let pitch = root + MinorScale.semitones(at: degree + interval)
            let roll = Double(voice) * 0.016
            return Note(voice: .pad, pitch: UInt8(pitch), velocity: velocity - UInt8(voice * 3),
                        beat: beat + roll, duration: duration - roll)
        }
    }
}
