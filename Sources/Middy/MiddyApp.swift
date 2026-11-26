import AppKit
import MiddyCore
import SwiftUI

@main
struct MiddyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Middy", id: "middy") {
            MainView(model: delegate.model)
                .frame(minWidth: 690, minHeight: 460)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 990, height: 615)
        .windowStyle(.hiddenTitleBar)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = MiddyModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.connect()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@MainActor
final class MiddyModel: ObservableObject {
    struct PlayedNote: Sendable {
        let note: Note
        let beat: Double
        let uptime: TimeInterval
    }

    @Published private(set) var status = SequencerStatus()
    private(set) var notes: [PlayedNote] = []

    private var sequencer: Sequencer?
    private var position: (beat: Double, uptime: TimeInterval, tempo: Double)?
    private var frozenBeat = 0.0

    func connect() {
        sequencer = Sequencer { [weak self] update in
            DispatchQueue.main.async {
                self?.receive(update)
            }
        }
        sequencer?.start()
    }

    func rollSeed() {
        sequencer?.rollSeed()
    }

    func shutdown() {
        sequencer?.shutdown()
    }

    func currentBeat() -> Double {
        guard status.playback == .playing, let position else { return frozenBeat }
        let elapsed = min(0.10, ProcessInfo.processInfo.systemUptime - position.uptime)
        return position.beat + elapsed * position.tempo / 60
    }

    private func receive(_ update: SequencerUpdate) {
        switch update {
        case .reseeded:
            notes.removeAll(keepingCapacity: true)
        case .status(let next):
            if status.playback == .playing && next.playback != .playing {
                frozenBeat = currentBeat()
                notes.removeAll { $0.beat + $0.note.duration > frozenBeat }
                position = nil
            }
            if status != next { status = next }
        case .position(let beat, let uptime, let tempo):
            position = (beat, uptime, tempo)
        case .note(let note, let beat, let uptime):
            if let last = notes.last, beat < last.beat {
                notes.removeAll()
            }
            notes.removeAll { $0.beat + $0.note.duration < beat - 32 }
            notes.append(PlayedNote(note: note, beat: beat, uptime: uptime))
        }
    }
}
