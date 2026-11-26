import AbletonLink
import Foundation
import MiddyCore

enum Playback: Equatable, Sendable {
    case stopped, queued, playing
}

struct SequencerStatus: Equatable, Sendable {
    var playback: Playback = .stopped
    var tempo = 120.0
    var peers: UInt64 = 0
    var error: String?
    var arrangement: ArrangementPosition?
}

enum SequencerUpdate: Sendable {
    case reseeded
    case status(SequencerStatus)
    case position(beat: Double, uptime: TimeInterval, tempo: Double)
    case note(Note, beat: Double, uptime: TimeInterval)
}

/// Link and MIDI state are owned exclusively by the sequencer queue.
final class Sequencer: @unchecked Sendable {
    private struct Event {
        let beat: Double
        let note: Note
        let isOn: Bool
    }

    private let queue = DispatchQueue(label: "Middy.sequencer", qos: .userInteractive)
    private let link = abl_link_create(120)
    private let linkState = abl_link_create_session_state()
    private let quantum = AcidPattern.beatsPerBar
    private let tickTimer: DispatchSourceTimer
    private let update: @Sendable (SequencerUpdate) -> Void
    private let midi: MIDIOutput?
    private var status = SequencerStatus()
    private var settings = PatternSettings()
    private var conductor = Conductor()
    private var random: ArrangementRandom
    private var seed: UInt64
    private var pendingSeed: UInt64?
    private var nextBar: Double?
    private var resumeSustainedNotes = false
    private var events: [Event] = []
    private var eventIndex = 0
    private var sounding: [Voice: Set<UInt8>] = [:]
    private var lastTick: (time: Int64, beat: Double)?
    private var lastPositionTime: Int64 = 0
    private var lastStatusTime: Int64 = 0
    private var closed = false

    init(seed: UInt64 = UInt64.random(in: UInt64.min...UInt64.max),
         update: @escaping @Sendable (SequencerUpdate) -> Void) {
        self.seed = seed
        self.random = ArrangementRandom(seed: seed)
        self.update = update
        do {
            midi = try MIDIOutput()
        } catch {
            midi = nil
            status.error = error.localizedDescription
        }
        tickTimer = DispatchSource.makeTimerSource(queue: queue)
        tickTimer.schedule(deadline: .now(), repeating: .milliseconds(50), leeway: .milliseconds(5))
        tickTimer.setEventHandler { [weak self] in self?.tick() }
        queue.async { [self] in abl_link_enable(link, true) }
        tickTimer.resume()
    }

    deinit {
        tickTimer.cancel()
        abl_link_destroy_session_state(linkState)
        abl_link_destroy(link)
    }

    func start() {
        queue.async { [self] in
            guard !closed, midi != nil, status.playback == .stopped else { return }
            abl_link_capture_app_session_state(link, linkState)
            let now = abl_link_clock_micros(link)
            let beat = abl_link_beat_at_time(linkState, now, quantum)
            cueNextBar(at: beat)
            tickTimer.schedule(deadline: .now(), repeating: .milliseconds(1), leeway: .microseconds(150))
            update(.status(status))
        }
    }

    func rollSeed() {
        queue.async { [self] in
            guard !closed, midi != nil else { return }
            pendingSeed = seed &+ UInt64.random(in: 1...UInt64.max)
        }
    }

    func shutdown() {
        queue.sync {
            closed = true
            silence()
            abl_link_enable(link, false)
            tickTimer.cancel()
        }
    }

    private func cueNextBar(at beat: Double) {
        silence()
        nextBar = (floor(beat / quantum) + 1) * quantum
        status.playback = .queued
    }

    private func silence() {
        for voice in Voice.allCases {
            for pitch in sounding[voice] ?? [] { noteOff(voice, pitch: pitch) }
        }
        events.removeAll(keepingCapacity: true)
        eventIndex = 0
        nextBar = nil
    }

    private func tick() {
        guard !closed else { return }
        abl_link_capture_app_session_state(link, linkState)
        let now = abl_link_clock_micros(link)
        let beat = abl_link_beat_at_time(linkState, now, quantum)
        let tempo = abl_link_tempo(linkState)
        if status.playback != .stopped, let lastTick {
            let elapsed = Double(now - lastTick.time) / 1_000_000
            // A session re-alignment or a machine wake can jump over scheduled events.
            if elapsed > 0.25 || abs(beat - lastTick.beat - elapsed * tempo / 60) > 0.12 {
                resumeSustainedNotes = resumeSustainedNotes || status.playback == .playing
                cueNextBar(at: beat)
                update(.status(status))
            }
        }
        lastTick = (now, beat)

        // Deliver due releases before admitting events for the next bar.
        emitDueEvents(now: now)
        if let bar = nextBar, abl_link_time_at_beat(linkState, bar, quantum) <= now {
            if status.playback != .playing {
                status.playback = .playing
                lastPositionTime = 0
                update(.status(status))
            }
            prepareBar(startingAt: bar)
            emitDueEvents(now: now)
        }

        if status.playback == .playing, now - lastPositionTime >= 33_000 {
            lastPositionTime = now
            update(.position(beat: beat, uptime: ProcessInfo.processInfo.systemUptime, tempo: tempo))
        }

        if now - lastStatusTime >= 150_000 {
            status.tempo = tempo
            status.peers = abl_link_num_peers(link)
            lastStatusTime = now
            update(.status(status))
        }
    }

    private func prepareBar(startingAt beat: Double) {
        if let pendingSeed {
            silence()
            seed = pendingSeed
            self.pendingSeed = nil
            random = ArrangementRandom(seed: seed)
            if let key = status.arrangement?.key {
                settings.root = key.relatedMinor(using: &random)
            }
            conductor = Conductor()
            resumeSustainedNotes = false
            update(.reseeded)
        }
        let bar = conductor.nextBar(settings: settings, resumeDrone: resumeSustainedNotes, using: &random)
        resumeSustainedNotes = false
        status.arrangement = bar.position
        update(.status(status))
        let barEvents = bar.notes.flatMap { note in
            [Event(beat: beat + note.beat, note: note, isOn: true),
             Event(beat: beat + note.beat + note.duration, note: note, isOn: false)]
        }
        events = (Array(events[eventIndex...]) + barEvents).sorted {
            if $0.beat != $1.beat { return $0.beat < $1.beat }
            if $0.isOn != $1.isOn { return !$0.isOn }
            if $0.note.voice != $1.note.voice { return $0.note.voice.rawValue < $1.note.voice.rawValue }
            return $0.note.pitch < $1.note.pitch
        }
        eventIndex = 0
        nextBar = beat + quantum
    }

    private func emitDueEvents(now: Int64) {
        while eventIndex < events.count {
            let event = events[eventIndex]
            let deadline = abl_link_time_at_beat(linkState, event.beat, quantum)
            guard deadline <= now else { return }
            eventIndex += 1
            let note = event.note
            if event.isOn {
                // Skip expired attacks after a scheduler stall, while still processing their releases.
                guard now - deadline < 25_000 else { continue }
                if sounding[note.voice]?.contains(note.pitch) == true { noteOff(note.voice, pitch: note.pitch) }
                midi?.send(status: 0x90 | (note.voice.rawValue - 1), pitch: note.pitch,
                           velocity: note.velocity)
                sounding[note.voice, default: []].insert(note.pitch)
                update(.note(note, beat: event.beat, uptime: ProcessInfo.processInfo.systemUptime))
            } else if sounding[note.voice]?.contains(note.pitch) == true {
                noteOff(note.voice, pitch: note.pitch)
            }
        }
    }

    private func noteOff(_ voice: Voice, pitch: UInt8) {
        midi?.send(status: 0x80 | (voice.rawValue - 1), pitch: pitch, velocity: 0)
        sounding[voice]?.remove(pitch)
    }
}
