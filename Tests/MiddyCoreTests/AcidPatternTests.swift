@testable import MiddyCore
import Testing

struct ConductorTests {
    @Test func sectionsKeepTheirLengthsAndShareTheTransition() {
        let conductor = Conductor()
        var random = RepeatableRandom(state: 23)
        let bars = (0..<236).map { _ in conductor.nextBar(settings: PatternSettings(), using: &random) }
        let firstHandoff = bars.prefix(133)
        #expect(firstHandoff.filter { $0.position.bar == 1 }.map(\.position.section)
                == [.intro, .build, .verse, .breakdown, .build, .verse, .outro, .build, .verse])
        #expect(firstHandoff.filter { $0.position.bar == 1 }.map(\.position.sectionBars)
                == [4, 4, 24, 64, 4, 24, 4, 4, 24])
        #expect(bars[127].position.song == 1)
        #expect(bars[128].position.song == 2)
        #expect(Set(bars[8..<32].flatMap(\.notes).filter { $0.voice == .drums }.map(\.pitch)) == Set(DrumPad.allCases.map(\.rawValue)))
        #expect(Set(bars[32].notes.map(\.voice)).subtracting([.pad]) == [.lead, .drone])
        #expect(Set(bars[40].notes.map(\.voice)).subtracting([.pad]) == [.lead, .drums])

        let firstVerse = bars[8].notes.contains { $0.voice == .pad } ? 8 : 108
        let secondVerse = bars[132].notes.contains { $0.voice == .pad } ? 132 : 232
        expectPreview(bars[0..<4], build: bars[4], verse: bars[firstVerse..<firstVerse + 4])
        expectPreview(bars[124..<128], build: bars[128], verse: bars[secondVerse..<secondVerse + 4])

        conductor.reset(using: &random)
        let reset = conductor.nextBar(settings: PatternSettings(), using: &random)
        #expect(reset.position.song == 3 && reset.position.section == .intro && reset.position.bar == 1)
    }

    private func expectPreview(_ preview: ArraySlice<ArrangedBar>, build: ArrangedBar, verse: ArraySlice<ArrangedBar>) {
        let mainLead = build.notes.filter { $0.voice == .lead }
        for (index, bar) in preview.enumerated() {
            let hint = bar.notes.filter { $0.voice == .lead }
            #expect(hint.count < mainLead.count)
            for note in hint {
                let match = mainLead.first { gridStep($0) == gridStep(note) }
                #expect(note.pitch == match?.pitch)
                #expect(match.map { Int(note.velocity) + 15 < Int($0.velocity) } == true)
            }
            let pad = bar.notes.filter { $0.voice == .pad }
            if index.isMultiple(of: 2) {
                let chord = verse[verse.startIndex + index].notes.filter { $0.voice == .pad }
                #expect(pad.count == 3)
                #expect(pad.map(\.pitch) == chord.map(\.pitch))
                #expect(pad.map(\.velocity).max()! < chord.map(\.velocity).min()!)
                #expect(pad.allSatisfy { $0.duration < 3 })
            } else {
                #expect(pad.isEmpty)
            }
        }
        #expect(preview.first?.notes.contains { $0.voice == .lead } == true)
    }

    @Test func phrasesKeepTwoMotifsAndRepeatTheirPitchAndGridPatterns() {
        for root in Root.allCases {
            for seed in UInt64(1)...10 {
                let conductor = Conductor()
                var random = RepeatableRandom(state: seed)
                var settings = PatternSettings()
                settings.root = root
                let bars = (0..<124).map { _ in conductor.nextBar(settings: settings, using: &random) }
                let lead = bars.map { $0.notes.filter { $0.voice == .lead } }
                #expect(lead[4].map(\.pitch) == lead[96].map(\.pitch))
                #expect(lead[8].map(\.pitch) == lead[100].map(\.pitch))
                let degreesByPitch = Dictionary(uniqueKeysWithValues: (-8...12).map { degree in
                    (60 + root.rawValue + MinorScale.semitones(at: degree), degree)
                })
                var motifs: [[Int]] = []
                for range in [4..<8, 8..<32, 32..<40] {
                    let phrase = lead[range.lowerBound]
                    #expect((11...12).contains(phrase.count))
                    for index in range {
                        let position = bars[index].position
                        let offset = (index - range.lowerBound) % 8
                        let leadsIntoVerse = position.section == .build && position.bar > 2
                        let statement = leadsIntoVerse ? lead[8] : lead[range.lowerBound + (offset < 4 ? 0 : 4)]
                        let preDrop = leadsIntoVerse && position.bar == position.sectionBars
                            && lead[index].count < statement.count
                        let pickupStep = lead[index].last.map(gridStep)
                        let cutoff = pickupStep == 14 ? 12 : 14
                        let expected = preDrop
                            ? statement.filter { gridStep($0) < cutoff || gridStep($0) == pickupStep } : statement
                        let steps = expected.map(gridStep)
                        let pitches = expected.map { preDrop && gridStep($0) == pickupStep ? statement[0].pitch : $0.pitch }
                        #expect(lead[index].map(\.pitch) == pitches)
                        #expect(lead[index].map(gridStep) == steps)
                    }
                    let degrees = phrase.compactMap { degreesByPitch[Int($0.pitch)] }
                    guard degrees.count == phrase.count else {
                        Issue.record("A lead note was outside the selected scale.")
                        continue
                    }
                    let motif = degrees.prefix(4).map { $0 - degrees[0] }
                    motifs.append(motif)
                    #expect(Set(motif).count == 2)
                    #expect(motif.allSatisfy { abs($0) <= 2 })
                    var previousAnchor = degrees[0]
                    for repetition in 1..<4 {
                        let attacks = zip(phrase, degrees).filter { gridStep($0.0) / 4 == repetition }
                        let anchors = Set(attacks.map { $0.1 - motif[gridStep($0.0) % 4] })
                        #expect(anchors.count == 1)
                        if let anchor = anchors.first {
                            #expect((2...4).contains(abs(anchor - previousAnchor)))
                            let previousEnd = MinorScale.semitones(at: previousAnchor + motif[3])
                            #expect(abs(MinorScale.semitones(at: anchor) - previousEnd) <= 7)
                            previousAnchor = anchor
                        }
                    }
                }
                if motifs.count == 3 {
                    #expect(motifs[0] == motifs[2])
                    #expect(motifs[0] != motifs[1])
                }
            }
        }
    }

    @Test func songsVaryTheirHarmonicPlansAndKeepEightBarStatements() {
        var heardProgressions = Set<[[Int]]>()
        var heardVoicings = Set<[Int]>()
        var heardMotifIntervals = Set<Int>()
        for seed in UInt64(1)...20 {
            let conductor = Conductor()
            var random = ArrangementRandom(seed: seed)
            let bars = (0..<248).map { _ in conductor.nextBar(settings: PatternSettings(), using: &random) }
            var songProgressions: [[[Int]]] = []
            for (opening, reprise) in [(8, 108), (132, 232)] {
                let start = bars[opening].notes.contains { $0.voice == .pad } ? opening : reprise
                let key = bars[start].position.key.rawValue
                func chords(in range: Range<Int>) -> [[Int]] {
                    bars[range].map { bar in
                        bar.notes.filter { $0.voice == .pad }.map { Int($0.pitch) - key - 48 }
                    }
                }
                let progression = chords(in: start..<start + 8)
                #expect(progression.allSatisfy { $0.count == 3 })
                #expect(progression == chords(in: start + 8..<start + 16))
                heardProgressions.insert(progression)
                let voicing = progression[0].map { $0 - progression[0][0] }
                heardVoicings.insert(voicing)
                songProgressions.append(progression)

                let motif = bars[opening].notes.filter { $0.voice == .lead }.prefix(4)
                heardMotifIntervals.insert(Int(motif.map(\.pitch).max()!) - Int(motif.map(\.pitch).min()!))
            }
            #expect(songProgressions[0] != songProgressions[1])
        }
        #expect(heardProgressions.count == SongHarmony.plans.count)
        #expect(heardVoicings.count >= 4)
        #expect(heardMotifIntervals.contains { $0 >= 3 })
        #expect(heardMotifIntervals.contains { $0 <= 2 })
    }

    @Test func stressShapesBothPitchedRhythmsAndHumanizationKeepsNotesInTheirBars() {
        let conductor = Conductor()
        var random = RepeatableRandom(state: 23)
        let verse = (0..<24).map { _ in conductor.nextBar(settings: PatternSettings(), using: &random) }[8...]
        for voice in Voice.allCases where voice != .drone && voice != .pad && voice != .formants {
            let notes = verse.flatMap(\.notes).filter { $0.voice == voice }
            #expect(Set(notes.map(\.velocity)).count > 4)
            #expect(notes.allSatisfy { $0.beat >= 0 && $0.duration > 0 && $0.beat + $0.duration < 4 })
        }
        for bar in verse {
            let kicks = bar.notes.filter { $0.voice == .drums && $0.pitch == DrumPad.kick.rawValue }
            #expect(kicks.map(\.beat) == [0, 1, 2, 3])
            let bass = bar.notes.filter { $0.voice == .bass }
            #expect(bass.map(gridStep) == verse.first!.notes.filter { $0.voice == .bass }.map(gridStep))
            #expect(zip(bass, bass.dropFirst()).allSatisfy { $0.beat + $0.duration <= $1.beat })
        }
        for voice in [Voice.lead, .bass] {
            let firstStep = verse.map { bar in bar.notes.first { $0.voice == voice }! }
            #expect(Set(firstStep.map(\.beat)).count > 1)
            #expect(Set(firstStep.map(\.duration)).count > 1)
            let downbeatAverages = (0..<4).map { phraseBar in
                (0..<4).map { repeatIndex in
                    Int(firstStep[phraseBar + 4 * repeatIndex].velocity)
                }.reduce(0, +)
            }
            #expect(downbeatAverages[3] > downbeatAverages[2])
        }
    }

    @Test func leadRestsAndVariesGateWhileFollowingTheSongsAccent() {
        var accents = Set<Int>()
        for seed in UInt64(1)...12 {
            let conductor = Conductor()
            var random = ArrangementRandom(seed: seed)
            let bars = (0..<101).map { _ in conductor.nextBar(settings: PatternSettings(), using: &random) }
            let verse = bars[8].notes
            let bass = verse.filter { $0.voice == .bass }
            let sub = verse.filter { $0.voice == .subBass }
            let accent = zip(bass, sub).first { $1.duration / $0.duration > 0.9 }.map { gridStep($0.1) % 4 }
            guard let accent else {
                Issue.record("The verse had no stressed sub bass note.")
                continue
            }
            accents.insert(accent)
            for index in [4, 6, 8, 32, 40, 56, 98, 100] {
                let lead = bars[index].notes.filter { $0.voice == .lead }
                let onAccent = lead.filter { gridStep($0) % 4 == accent }
                let passing = lead.filter { gridStep($0) % 4 != accent }
                #expect((11...12).contains(lead.count))
                #expect(onAccent.map(gridStep) == (0..<4).map { $0 * 4 + accent })
                #expect(onAccent.map(\.velocity).min()! > passing.map(\.velocity).max()!)
                #expect(onAccent.map(\.duration).min()! > passing.map(\.duration).max()!)
                #expect(lead.contains { $0.duration > 0.32 })
                #expect(lead.contains { $0.duration < 0.19 })
                let gaps = zip(lead, lead.dropFirst()).map { $1.beat - ($0.beat + $0.duration) }
                #expect(gaps.allSatisfy { $0 > 0 })
                #expect(gaps.contains { $0 > 0.23 })
                #expect(lead.allSatisfy { $0.beat + $0.duration < 4 })
            }
        }
        #expect(accents == [0, 2])
    }

    @Test func cymbalFollowsTheFourBarDrumLoops() {
        let conductor = Conductor()
        var random = RepeatableRandom(state: 48)
        let bars = (0..<128).map { _ in conductor.nextBar(settings: PatternSettings(), using: &random) }
        func cymbals(_ range: Range<Int>) -> [[Int]] {
            bars[range].map { bar in
                bar.notes.filter { $0.voice == .drums && $0.pitch == DrumPad.cymbal.rawValue }
                    .map(gridStep)
            }
        }
        #expect(cymbals(0..<4) == [[], [0], [], [14]])
        #expect(cymbals(0..<4) == cymbals(124..<128))
        let buildCymbals = cymbals(4..<8)
        #expect(Array(buildCymbals.prefix(3)) == [[0], [], []])
        #expect(buildCymbals[3].isEmpty || buildCymbals[3] == [14])
        #expect(cymbals(8..<12) == [[0], [], [8], [14]])
        #expect(cymbals(8..<12) == cymbals(12..<16))
        #expect(cymbals(32..<40).allSatisfy { $0.isEmpty })
        #expect(cymbals(40..<44) == [[0], [], [], []])
        #expect(cymbals(92..<96) == [[], [], [], [14]])
    }

    @Test func shakerAndTambourineStayOccasional() {
        let conductor = Conductor()
        var random = RepeatableRandom(state: 71)
        let bars = (0..<128).map { _ in conductor.nextBar(settings: PatternSettings(), using: &random) }
        func barsWith(_ pad: DrumPad) -> [Int] {
            bars.indices.filter { index in
                bars[index].notes.contains { $0.voice == .drums && $0.pitch == pad.rawValue }
            }
        }
        #expect(barsWith(.shaker) == [6, 13, 14, 21, 22, 98, 105, 106, 113, 114])
        #expect(barsWith(.tambourine) == [15, 23, 107, 115])
    }

    @Test func consecutiveSongsUseNewContours() {
        func contour(in bar: ArrangedBar) -> [Int] {
            let pitches = bar.notes.filter { $0.voice == .lead }.prefix(4).map { Int($0.pitch) }
            return pitches.map { $0 == pitches[0] ? 0 : 1 }
        }

        for seed in UInt64(1)...12 {
            let conductor = Conductor()
            var random = RepeatableRandom(state: seed)
            let bars = (0..<261).map { _ in conductor.nextBar(settings: PatternSettings(), using: &random) }
            let motifs = [(4, 8), (128, 132), (252, 256)].map { build, verse in
                Set([contour(in: bars[build]), contour(in: bars[verse])])
            }
            #expect(motifs.allSatisfy { $0.count == 2 })
            #expect(motifs[0].isDisjoint(with: motifs[1]))
            #expect(motifs[1].isDisjoint(with: motifs[2]))
        }
    }

    @Test func subBassFollowsBassOnsetsWithOneAccentModePerSong() {
        var stressedStepsSeen = Set<Int>()
        for seed in UInt64(1)...12 {
            let conductor = Conductor()
            var random = RepeatableRandom(state: seed)
            var settings = PatternSettings()
            settings.root = .fSharp
            let bars = (0..<174).map { _ in conductor.nextBar(settings: settings, using: &random) }
            for song in [bars[0..<128], bars[128..<174]] {
                var songAccents = Set<Int>()
                var loudestUnstressed = 0
                var softestStressed = 127
                for bar in song {
                    let main = bar.notes.filter { $0.voice == .bass }
                    let sub = bar.notes.filter { $0.voice == .subBass }
                    #expect(main.map(\.beat) == sub.map(\.beat))
                    if !main.isEmpty {
                        #expect(zip(main, sub).contains { $1.duration / $0.duration > 0.9 })
                    }
                    for (bass, subNote) in zip(main, sub) {
                        #expect(subNote.pitch == 24 + bar.position.key.rawValue)
                        #expect([-2, 0, 7].contains(Int(bass.pitch) - Int(subNote.pitch) - 12))
                        let gate = subNote.duration / bass.duration
                        #expect(gate > 0.4 && gate < 1)
                        let step = gridStep(subNote) % 4
                        if gate > 0.9 {
                            songAccents.insert(step)
                            softestStressed = min(softestStressed, Int(subNote.velocity))
                        } else {
                            loudestUnstressed = max(loudestUnstressed, Int(subNote.velocity))
                        }
                    }
                }
                #expect(songAccents.count == 1)
                #expect(softestStressed > loudestUnstressed)
                stressedStepsSeen.formUnion(songAccents)
            }
        }
        #expect(stressedStepsSeen == [0, 2])
    }

    @Test func mainBassUsesOccasionalPickupsWhileTheSubStaysOnRoot() {
        var pickupBars = 0
        var bassBars = 0
        for seed in UInt64(1)...12 {
            let conductor = Conductor()
            var random = ArrangementRandom(seed: seed)
            var settings = PatternSettings()
            settings.root = .dSharp
            let bars = (0..<141).map { _ in conductor.nextBar(settings: settings, using: &random) }
            for bar in bars {
                let bass = bar.notes.filter { $0.voice == .bass }
                guard !bass.isEmpty else { continue }
                bassBars += 1
                let root = 36 + bar.position.key.rawValue
                let sub = bar.notes.filter { $0.voice == .subBass }
                let pickups = bass.filter { Int($0.pitch) != root }
                #expect(Int(bass[0].pitch) == root && gridStep(bass[0]) == 0)
                #expect(bass.map(\.beat) == sub.map(\.beat))
                #expect(sub.allSatisfy { Int($0.pitch) == root - 12 })
                #expect(pickups.count <= 1)
                if let pickup = pickups.first {
                    pickupBars += 1
                    #expect(bar.position.bar.isMultiple(of: 2))
                    #expect(gridStep(pickup) >= 8 && !gridStep(pickup).isMultiple(of: 4))
                    #expect([-2, 7].contains(Int(pickup.pitch) - root))
                }
            }
        }
        #expect(pickupBars > 0 && pickupBars * 2 < bassBars)
    }

    @Test func songHandoffsMoveToRelatedMinorKeys() {
        let conductor = Conductor()
        var random = RepeatableRandom(state: 73)
        let bars = (0..<377).map { _ in conductor.nextBar(settings: PatternSettings(), using: &random) }
        let transitions = [0, 124, 248, 372]
        func pitches(in key: Root) -> Set<Int> {
            Set([0, 2, 3, 5, 7, 8, 10].map { (key.rawValue + $0) % 12 })
        }
        #expect(bars.first?.position.key == .c)
        for (start, end) in zip(transitions, transitions.dropFirst() + [bars.count]) {
            let key = bars[start].position.key
            #expect(bars[start..<end].allSatisfy { $0.position.key == key })
            if start > 0 {
                #expect(bars[start].position.section == .outro)
                #expect(pitches(in: bars[start - 1].position.key).intersection(pitches(in: key)).count == 6)
            }
            for note in bars[start..<end].flatMap(\.notes) where note.voice != .drums {
                #expect(pitches(in: key).contains(Int(note.pitch) % 12))
            }
        }
    }

    @Test func environmentalDroneUsesLongChordsWithSectionRests() {
        var repriseCount = 0
        var silentReprises = 0
        for seed in UInt64(1)...12 {
            let conductor = Conductor()
            var random = ArrangementRandom(seed: seed)
            let bars = (0..<138).map { _ in conductor.nextBar(settings: PatternSettings(), using: &random) }
            let starts = bars.indices.filter { bars[$0].notes.contains { $0.voice == .drone } }
            #expect(starts == [0, 32, 124] || starts == [0, 32, 100, 124])
            if starts.contains(100) { repriseCount += 1 } else { silentReprises += 1 }
            for start in starts {
                let chord = bars[start].notes.filter { $0.voice == .drone }
                #expect(Set(chord.map(\.pitch)).count == 3)
                let expectedEnd = Double([0, 124].contains(start) ? 4 : 8) * AcidPattern.beatsPerBar
                #expect(chord.allSatisfy { (expectedEnd - 0.20..<expectedEnd).contains($0.beat + $0.duration) })
            }
        }
        #expect(repriseCount > 0)
        #expect(silentReprises > 0)
    }

    @Test func environmentalDroneResumesAfterRephaseOnlyWhenHeld() {
        let conductor = Conductor()
        var random = RepeatableRandom(state: 39)
        let firstChord = conductor.nextBar(settings: PatternSettings(), using: &random)
            .notes.filter { $0.voice == .drone }
        for _ in 1..<3 { _ = conductor.nextBar(settings: PatternSettings(), using: &random) }
        let resumed = conductor.nextBar(settings: PatternSettings(), resumeDrone: true, using: &random)
            .notes.filter { $0.voice == .drone }
        #expect(resumed.map(\.pitch) == firstChord.map(\.pitch))
        #expect(resumed.allSatisfy { (3.8..<4).contains($0.beat + $0.duration) })

        let build = conductor.nextBar(settings: PatternSettings(), resumeDrone: true, using: &random)
        #expect(build.position.section == .build)
        #expect(!build.notes.contains { $0.voice == .drone })
    }

    @Test func versePlucksKeepOneRoleAndPlayInFourBarPhrases() {
        var rolesHeard = Set<Int>()
        for seed in UInt64(1)...12 {
            let conductor = Conductor()
            var random = ArrangementRandom(seed: seed)
            let bars = (0..<128).map { _ in conductor.nextBar(settings: PatternSettings(), using: &random) }
            let openingAccent = bars[8].notes.first { $0.voice == .plucks }!
            let subdivision = gridStep(openingAccent) % 4
            let role = subdivision.isMultiple(of: 2) ? subdivision : 1
            rolesHeard.insert(role)

            func fitsRole(_ note: Note) -> Bool {
                let subdivision = gridStep(note) % 4
                return role == 1 ? !subdivision.isMultiple(of: 2) : subdivision == role
            }

            for bar in bars where bar.position.section != .verse {
                #expect(!bar.notes.contains { $0.voice == .plucks })
            }
            for start in [8, 100] {
                var timeline: [Int] = []
                var rhythms: [[Int]] = []
                for (index, bar) in bars[start..<start + 24].enumerated() {
                    let accents = bar.notes.filter { $0.voice == .plucks }
                    let lead = bar.notes.filter { $0.voice == .lead }
                    let steps = accents.map(gridStep)
                    let phraseBar = index % 4
                    let rest = role == 2 ? 2 : 1
                    #expect(accents.isEmpty == (phraseBar == rest))
                    #expect(accents.count <= (index >= 16 ? 1 : 2))
                    #expect(accents.allSatisfy(fitsRole))
                    if phraseBar == 3 {
                        let ending = role == 1 ? 12 : 8
                        let peak = lead.filter { fitsRole($0) && gridStep($0) >= ending }.map(\.pitch).max()
                        #expect(accents.count == 1)
                        #expect(accents.first?.pitch == peak.map { $0 + 12 })
                    }
                    for accent in accents {
                        #expect(lead.contains {
                            $0.beat == accent.beat && $0.pitch + 12 == accent.pitch
                                && $0.duration > accent.duration && $0.velocity > accent.velocity
                        })
                    }
                    rhythms.append(steps)
                    timeline += steps.map { index * 16 + $0 }
                }
                #expect(Array(rhythms[0..<8]) == Array(rhythms[8..<16]))
                #expect(rhythms[16..<24].enumerated().allSatisfy { offset, steps in
                    steps == Array(rhythms[offset].prefix(1))
                })
                #expect(zip(timeline, timeline.dropFirst()).allSatisfy { $1 - $0 >= 4 })
            }
        }
        #expect(rolesHeard == [0, 1, 2])
    }

    @Test func pluckWindowsFavorMelodicPeaksAndStressedNotes() {
        var random = ArrangementRandom(seed: 48)
        let stress = BarStress(using: &random)
        let melody = (0..<16).map { step in
            // The loudest and highest note is too early to be a syncopated phrase ending.
            let pitch: UInt8 = step == 1 ? 84 : (step == 15 ? 69 : 60)
            return Note(voice: .lead, pitch: pitch, velocity: step == 1 ? 110 : 80,
                        beat: Double(step) / 4, duration: 0.18)
        }
        let opening = PluckRole.downbeat.accents(for: melody, phraseBar: 0, sparse: true, stress: stress)
        #expect(opening.map(gridStep) == [0])

        let answer = PluckRole.downbeat.accents(for: melody, phraseBar: 2, sparse: true, stress: stress)
        let stressedStep = stress.pulse(at: 0) >= stress.pulse(at: 4) ? 0 : 4
        #expect(answer.map(gridStep) == [stressedStep])

        let ending = PluckRole.syncopation.accents(for: melody, phraseBar: 3, sparse: false, stress: stress)
        #expect(ending.map(gridStep) == [15])
        #expect(ending.map(\.pitch) == [81])
    }

    @Test func buildsVaryInIntensityAndHandOffToTheVerse() {
        var countsByIntensity: [Int: Int] = [:]
        for seed in UInt64(1)...32 {
            let conductor = Conductor()
            var random = ArrangementRandom(seed: seed)
            let bars = (0..<101).map { _ in conductor.nextBar(settings: PatternSettings(), using: &random) }
            var songIntensities = Set<Int>()
            for start in [4, 96] {
                let build = bars[start..<start + 4]
                #expect(!build.flatMap(\.notes).contains { $0.voice == .bass || $0.voice == .subBass })
                let verse = bars[start + 4]
                #expect(verse.position.section == .verse && verse.position.bar == 1)
                #expect(verse.notes.contains { $0.voice == .drums && $0.pitch == DrumPad.kick.rawValue && $0.beat == 0 })
                let bass = verse.notes.first { $0.voice == .bass }
                let sub = verse.notes.first { $0.voice == .subBass }
                #expect(bass.map(gridStep) == 0)
                #expect(bass?.beat == sub?.beat)
                #expect(bass?.pitch == UInt8(36 + verse.position.key.rawValue))
                #expect(sub?.pitch == UInt8(24 + verse.position.key.rawValue))
                let verseLead = verse.notes.filter { $0.voice == .lead }
                let bridge = bars[start + 2].notes.filter { $0.voice == .lead }
                #expect(bridge.map(\.pitch) == verseLead.map(\.pitch))
                #expect(!build.flatMap(\.notes).contains { $0.voice == .plucks })
                let snares = build.map { bar in
                    bar.notes.filter { $0.voice == .drums && $0.pitch == DrumPad.snare.rawValue }
                }
                let intensity = snares[1].count
                countsByIntensity[intensity, default: 0] += 1
                songIntensities.insert(intensity)
                let openingKick = build.first?.notes.first { $0.voice == .drums && $0.pitch == DrumPad.kick.rawValue }
                let closingKick = build.last?.notes.first { $0.voice == .drums && $0.pitch == DrumPad.kick.rawValue }
                #expect(openingKick!.velocity < closingKick!.velocity)
                if intensity == 0 {
                    #expect(snares.map(\.count) == [0, 0, 0, 2])
                    let finalLead = bars[start + 3].notes.filter { $0.voice == .lead }
                    #expect(finalLead.map(\.pitch) == verseLead.map(\.pitch))
                    continue
                }

                func grid(_ notes: [Note]) -> [Int] { notes.map { Int(($0.beat * 8).rounded()) } }
                let peak = intensity == 2
                if peak {
                    #expect(grid(snares[1]) == [16, 24])
                    #expect(grid(snares[2]) == [8, 12, 16, 20, 24, 28])
                    #expect(grid(snares[3]) == [0, 2, 4, 6, 8, 10, 12, 14] + Array(16..<24))
                } else {
                    #expect(grid(snares[1]) == [24])
                    #expect(grid(snares[2]) == [16, 20, 24, 28])
                    #expect(grid(snares[3]) == [0, 4, 8, 12, 16, 18, 20, 22, 24, 26])
                }
                let roll = snares[3]
                #expect(zip(roll, roll.dropFirst()).allSatisfy { $0.beat + $0.duration < $1.beat })

                let final = bars[start + 3].notes
                let cutoff = peak ? 3.0 : 3.5
                let preDrop = final.filter { $0.beat + $0.duration >= cutoff }
                #expect(preDrop.count == 1)
                #expect(preDrop.first?.voice == .lead)
                #expect(preDrop.first.map(gridStep) == (peak ? 14 : 15))
                #expect(preDrop.first.map { $0.velocity < 60 } == true)
                #expect(preDrop.first?.pitch == verseLead.first?.pitch)
            }
            #expect(songIntensities.count == 2)
        }
        #expect(Set(countsByIntensity.keys) == [0, 1, 2])
        #expect(countsByIntensity.values.allSatisfy { (11...33).contains($0) })
    }

    @Test func eightBarChangesKeepTheVerseGrooveAndTradeBreakdownLayers() {
        let conductor = Conductor()
        var random = ArrangementRandom(seed: 48)
        let bars = (0..<124).map { _ in conductor.nextBar(settings: PatternSettings(), using: &random) }
        for start in [8, 100] {
            let blocks = (0..<3).map { offset in bars[start + offset * 8 ..< start + (offset + 1) * 8] }
            let lead = bars[start..<start + 8].map { $0.notes.filter { $0.voice == .lead }.map(\.pitch) }
            #expect(lead[0] != lead[4])
            let bass = bars[start].notes.filter { $0.voice == .bass }.map(gridStep)
            let hats = blocks.map {
                $0.flatMap(\.notes).filter { $0.voice == .drums && $0.pitch == DrumPad.closedHat.rawValue }.count
            }
            #expect(hats[1] > hats[0] && hats[2] < hats[1])
            for block in blocks {
                for (index, bar) in block.enumerated() {
                    #expect(bar.notes.filter { $0.voice == .lead }.map(\.pitch) == lead[index])
                    #expect(bar.notes.filter { $0.voice == .bass }.map(gridStep) == bass)
                    #expect(bar.notes.filter { $0.voice == .drums && $0.pitch == DrumPad.kick.rawValue }
                        .map(\.beat) == [0, 1, 2, 3])
                }
            }
        }
        let opening = bars[32..<40].flatMap(\.notes)
        let ending = bars[40..<48].flatMap(\.notes)
        #expect(!opening.contains { $0.voice == .drums })
        #expect(opening.filter { $0.voice == .drone }.allSatisfy { $0.beat + $0.duration < 32 })
        #expect(ending.contains { $0.voice == .drums && $0.pitch == DrumPad.closedHat.rawValue })
        #expect(!ending.contains { $0.voice == .drone || ($0.voice == .drums && $0.pitch == DrumPad.kick.rawValue) })
    }

    @Test func longBreakdownRevisitsItsThreeEightBarPhrases() {
        let conductor = Conductor()
        var random = ArrangementRandom(seed: 48)
        let bars = (0..<101).map { _ in conductor.nextBar(settings: PatternSettings(), using: &random) }
        let names: [PhraseName] = [.c, .d, .c, .e, .d, .e, .c, .e]
        var melodyByPhrase: [PhraseName: [[UInt8]]] = [:]
        for (index, name) in names.enumerated() {
            let start = 32 + index * 8
            let block = bars[start..<start + 8]
            #expect(block.allSatisfy { $0.position.section == .breakdown && $0.position.phrase == name })
            let melody = block.map { $0.notes.filter { $0.voice == .lead }.map(\.pitch) }
            #expect(melody.allSatisfy { (11...12).contains($0.count) })
            #expect(Array(melody.prefix(4)) != Array(melody.suffix(4)))
            if let previous = melodyByPhrase[name] {
                #expect(melody == previous)
            } else {
                melodyByPhrase[name] = melody
            }
            let notes = block.flatMap(\.notes)
            let drums = notes.filter { $0.voice == .drums }
            let isSilent = [0, 2, 4].contains(index)
            #expect(drums.isEmpty == isSilent)
            #expect(!drums.contains { $0.pitch == DrumPad.kick.rawValue })
            for (offset, bar) in block.enumerated() {
                let hats = bar.notes.filter { $0.voice == .drums && $0.pitch == DrumPad.closedHat.rawValue }
                let finalFour = index == 7 && offset >= 4
                let expectedHats = finalFour ? [2, 6, 10, 14] : [2, 10]
                #expect(hats.map(gridStep) == (isSilent ? [] : expectedHats))
            }
            #expect(!notes.contains { [.bass, .subBass, .plucks].contains($0.voice) })
        }
        #expect(Set(melodyByPhrase.values).count == 3)
        #expect(bars[95].position.bar == 64)
        #expect(bars[96].position.section == .build)
        #expect(bars[100].position.section == .verse)
    }

    @Test func padDynamicsDistinguishSectionsAndRiseThroughSelectedBuilds() {
        var buildsWithPad = 0
        var buildsWithoutPad = 0
        var versesWithPad = 0
        var versesWithoutPad = 0
        var songsWithBoth = 0
        var breakdownsWithPad = 0
        var breakdownsWithoutPad = 0
        for seed in UInt64(1)...12 {
            let conductor = Conductor()
            var random = RepeatableRandom(state: seed)
            let bars = (0..<124).map { _ in conductor.nextBar(settings: PatternSettings(), using: &random) }
            func velocities(_ indices: Range<Int>) -> [UInt8] {
                bars[indices].flatMap(\.notes).filter { $0.voice == .pad }.map(\.velocity)
            }
            let breakdown = velocities(32..<96)
            if breakdown.isEmpty {
                breakdownsWithoutPad += 1
            } else {
                breakdownsWithPad += 1
                #expect((40 * 3...48 * 3).contains(breakdown.count))
            }
            let verse = velocities(8..<32)
            let reprise = velocities(100..<124)
            #expect(!verse.isEmpty || !reprise.isEmpty)
            #expect(velocities(24..<32).isEmpty)
            #expect(velocities(100..<108).isEmpty)
            for verseSection in [verse, reprise] {
                if let peak = verseSection.max() {
                    versesWithPad += 1
                    #expect(verseSection.count == 16 * 3)
                    if let breakdownPeak = breakdown.max() {
                        #expect(breakdownPeak < peak)
                    }
                } else {
                    versesWithoutPad += 1
                }
            }
            if !verse.isEmpty && !reprise.isEmpty {
                songsWithBoth += 1
                #expect(verse.reduce(0) { $0 + Int($1) } < reprise.reduce(0) { $0 + Int($1) })
            }

            for start in [4, 96] {
                let chords = (start..<start + 4).map { velocities($0..<$0 + 1) }
                if chords[0].isEmpty {
                    buildsWithoutPad += 1
                    #expect(chords.allSatisfy { $0.isEmpty })
                } else {
                    buildsWithPad += 1
                    #expect(chords.allSatisfy { $0.count == 3 })
                    for (before, after) in zip(chords, chords.dropFirst()) {
                        #expect(zip(before, after).allSatisfy { $0 < $1 })
                    }
                }
            }
        }
        #expect(buildsWithPad > 0)
        #expect(buildsWithoutPad > 0)
        #expect(versesWithPad > 0)
        #expect(versesWithoutPad > 0)
        #expect(songsWithBoth > 0)
        #expect(breakdownsWithPad > 0)
        #expect(breakdownsWithoutPad > 0)
    }

    @Test func versePadsSometimesUseHalfAndQuarterLengthChords() {
        let lengths = [3.85, 3.85 / 2, 3.85 / 4]
        var heard = Set<Double>()
        for seed in UInt64(1)...12 {
            let conductor = Conductor()
            var random = ArrangementRandom(seed: seed)
            let bars = (0..<124).map { _ in conductor.nextBar(settings: PatternSettings(), using: &random) }
            for verse in [8..<32, 100..<124] {
                for start in stride(from: verse.lowerBound, to: verse.upperBound, by: 4) {
                    let chords = bars[start..<start + 4].flatMap(\.notes).filter { $0.voice == .pad }
                    guard let first = chords.first else { continue }
                    let length = lengths.first { abs(first.beat + first.duration - $0) < 0.025 }
                    if let length {
                        heard.insert(length)
                        #expect(chords.count == 12)
                        #expect(chords.allSatisfy { abs($0.beat + $0.duration - length) < 0.025 })
                    } else {
                        Issue.record("Verse pad did not use a full, half, or quarter-length gate.")
                    }
                }
            }
        }
        #expect(heard == Set(lengths))
    }

    @Test func breakdownPadsSometimesHoldAcrossTwoBarsAndResumeAfterRephase() {
        let settings = PatternSettings()
        var checkedHold = false
        for seed in UInt64(1)...12 {
            let conductor = Conductor()
            var random = ArrangementRandom(seed: seed)
            let bars = (0..<97).map { _ in conductor.nextBar(settings: settings, using: &random) }
            var sustainedBlocks = Set<Int>()
            var singleBars = 0
            for index in 32..<96 {
                let pads = bars[index].notes.filter { $0.voice == .pad }
                guard let first = pads.first else { continue }
                #expect(pads.count == 3)
                let doubled = first.duration > 4
                let duration = doubled ? 7.70 : 3.85
                #expect(pads.allSatisfy { abs($0.beat + $0.duration - duration) < 0.025 })
                guard doubled else {
                    singleBars += 1
                    continue
                }
                let sectionBar = bars[index].position.bar - 1
                #expect(sectionBar.isMultiple(of: 2))
                #expect(!bars[index + 1].notes.contains { $0.voice == .pad })
                sustainedBlocks.insert(sectionBar / 8)

                if !checkedHold {
                    let rephased = Conductor()
                    var replay = ArrangementRandom(seed: seed)
                    for _ in 0...index { _ = rephased.nextBar(settings: settings, using: &replay) }
                    let resumed = rephased.nextBar(settings: settings, resumeDrone: true, using: &replay)
                        .notes.filter { $0.voice == .pad }
                    #expect(resumed.map(\.pitch) == pads.map(\.pitch))
                    #expect(resumed.allSatisfy { abs($0.beat + $0.duration - 3.70) < 0.025 })
                    checkedHold = true
                }
            }
            if singleBars > 0 { #expect(sustainedBlocks.count == 2) }
        }
        #expect(checkedHold)
    }

    @Test func formantsReplySparinglyInSelectedVerses() {
        var songsWithReplies = 0
        var songsWithoutReplies = 0
        for seed in UInt64(1)...20 {
            let conductor = Conductor()
            var random = ArrangementRandom(seed: seed)
            let bars = (0..<128).map { _ in conductor.nextBar(settings: PatternSettings(), using: &random) }
            let replyBars = bars.indices.filter { bars[$0].notes.contains { $0.voice == .formants } }
            if replyBars.isEmpty {
                songsWithoutReplies += 1
                continue
            }
            songsWithReplies += 1
            #expect((1...2).contains(replyBars.count))
            #expect(replyBars.allSatisfy { $0 < 32 } || replyBars.allSatisfy { $0 >= 100 })
            let oneVerseHasPads = bars[8].notes.contains { $0.voice == .pad }
                != bars[108].notes.contains { $0.voice == .pad }
            for index in replyBars {
                let bar = bars[index]
                #expect(bar.position.section == .verse)
                #expect([8, 16, 24].contains(bar.position.bar))
                if oneVerseHasPads {
                    #expect(!bar.notes.contains { $0.voice == .pad })
                }
                let replies = bar.notes.filter { $0.voice == .formants }
                #expect(replies.map(gridStep) == [13, 15])
                #expect(replies.allSatisfy { reply in
                    (60...71).contains(reply.pitch) && reply.duration < 0.18
                        && bar.notes.contains {
                            $0.voice == .lead && $0.beat == reply.beat && $0.pitch % 12 == reply.pitch % 12
                        }
                })
            }
        }
        #expect(songsWithReplies > 0)
        #expect(songsWithoutReplies > 0)
    }

    @Test func oneSeedReplaysTheWholeArrangement() {
        func arrangement(seed: UInt64) -> [ArrangedBar] {
            var random = ArrangementRandom(seed: seed)
            var settings = PatternSettings()
            settings.root = Root.c.relatedMinor(using: &random)
            let conductor = Conductor()
            return (0..<376).map { _ in conductor.nextBar(settings: settings, using: &random) }
        }

        let first = arrangement(seed: 1201)
        let replay = arrangement(seed: 1201)
        let changed = arrangement(seed: 2089)
        #expect(first.map(\.position) == replay.map(\.position))
        #expect(first.map(\.notes) == replay.map(\.notes))
        for voice in Voice.allCases {
            let original = first.flatMap(\.notes).filter { $0.voice == voice }
            let differentSeed = changed.flatMap(\.notes).filter { $0.voice == voice }
            #expect(!original.isEmpty)
            #expect(original != differentSeed)
        }
    }

    @Test func pitchedPartsTransposeIndependentlyAndPadCanBeMuted() {
        var shifted = PatternSettings()
        shifted.leadOctave = 2
        shifted.bassOctave = -2
        shifted.padOctave = 1
        func song(settings: PatternSettings) -> [ArrangedBar] {
            let conductor = Conductor()
            var random = RepeatableRandom(state: 96)
            return (0..<124).map { _ in conductor.nextBar(settings: settings, using: &random) }
        }
        let originalSong = song(settings: PatternSettings())
        let verse = originalSong[8].notes.contains { $0.voice == .pad } ? 8 : 108
        let original = originalSong[verse].notes
        #expect(original.contains { $0.voice == .pad })
        let transposed = song(settings: shifted)[verse].notes
        let offsets: [Voice: Int] = [.lead: 24, .bass: -24, .drums: 0, .pad: 12, .subBass: -24, .drone: 0, .plucks: 24, .formants: 0]
        #expect(original.count == transposed.count)
        for (before, after) in zip(original, transposed) {
            #expect(before.voice == after.voice)
            #expect(before.beat == after.beat)
            #expect(before.duration == after.duration)
            #expect(Int(before.pitch) + offsets[before.voice]! == Int(after.pitch))
        }
        shifted.padEnabled = false
        let muted = song(settings: shifted)[verse].notes
        let expected = transposed.filter { $0.voice != .pad }
        #expect(muted.map(\.voice) == expected.map(\.voice))
        #expect(muted.map(\.pitch) == expected.map(\.pitch))
        #expect(muted.map(gridStep) == expected.map(gridStep))
    }

    private func gridStep(_ note: Note) -> Int { Int((note.beat * 4).rounded()) }
}

private struct RepeatableRandom: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}
