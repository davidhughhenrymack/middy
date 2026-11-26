import MiddyCore
import SwiftUI

struct PianoRoll: View {
    @ObservedObject var model: MiddyModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lastRoll: TimeInterval?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: model.status.error != nil)) { frame in
            let beat = model.currentBeat()
            let notes = model.notes
            let time = reduceMotion ? 0 : frame.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 600)
            let readout = phraseReadout
            let uptime = ProcessInfo.processInfo.systemUptime
            let motion = reduceMotion ? .zero : CabinetMotion(notes: notes, uptime: uptime)
            let flash = lastRoll.map { max(0, 1 - (uptime - $0) * 5) } ?? 0
            let diceBrightness = model.status.error == nil ? 0.88 + flash * 0.12 : 0.33
            Canvas { context, size in
                let tube = Tube(size: size, time: time, animateInterference: !reduceMotion, motion: motion)
                tube.drawFace(in: context)
                tube.drawTraces(notes, through: beat, in: context)
                tube.drawLabels(in: context)
                tube.drawReadout(readout, in: context)
                tube.drawDice(brightness: diceBrightness, in: context)
                tube.drawRaster(in: context)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("MIDI oscilloscope")
        .accessibilityValue(phraseReadout)
        .overlay(alignment: .topTrailing) {
            Button {
                model.rollSeed()
                if !reduceMotion { lastRoll = ProcessInfo.processInfo.systemUptime }
            } label: {
                Color.clear
                    .frame(width: DiceControl.size, height: DiceControl.size)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.status.error != nil)
            .accessibilityLabel("Roll a new seed")
            .help("Start a fresh arrangement at the next bar")
            .padding(.top, DiceControl.top)
            .padding(.trailing, DiceControl.trailing)
        }
    }

    private var phraseReadout: String {
        if let error = model.status.error { return error.uppercased() }
        guard let position = model.status.arrangement else { return "SYNCING" }
        let section = position.section.rawValue.uppercased()
        let phrase = position.phrase.map { " \($0.rawValue)" } ?? ""
        let bars = String(format: "%02d / %02d", position.bar, position.sectionBars)
        return "\(section)\(phrase)  \(bars)   ·   \(position.key.name) MINOR"
    }
}

private enum DiceControl {
    static let size = 44.0
    static let top = 24.0
    static let trailing = 25.0
}

private struct CabinetMotion {
    static let zero = Self(horizontal: 0, vertical: 0)

    private(set) var horizontal: Double
    private(set) var vertical: Double

    private init(horizontal: Double, vertical: Double) {
        self.horizontal = horizontal
        self.vertical = vertical
    }

    init(notes: [MiddyModel.PlayedNote], uptime: TimeInterval) {
        self = .zero
        for played in notes.reversed() {
            let elapsed = uptime - played.uptime
            if elapsed > 0.22 { break }
            guard elapsed >= 0 else { continue }

            let note = played.note
            let strength: Double
            if note.voice == .drums && note.pitch == DrumPad.kick.rawValue {
                strength = 0.75 + Double(note.velocity) / 127 * 0.25
            } else if note.voice == .bass && note.velocity > 94 {
                strength = Double(note.velocity - 94) / 33 * 0.30
            } else {
                continue
            }

            // The tube shifts quickly, overshoots once, then settles.
            let envelope = strength * (1 - exp(-125 * elapsed)) * exp(-21 * elapsed)
            vertical += 8 * envelope * cos(47 * elapsed)
            horizontal += 2.8 * envelope * sin(47 * elapsed)
        }
    }
}

private struct Tube {
    private struct Trace {
        let path: Path
        let intensity: Double
        let width: Double
        let phosphor: Phosphor
    }

    private enum Phosphor {
        case blue, green, white, yellow, mutedRed

        var glow: Color {
            switch self {
            case .blue: Color(red: 0.25, green: 0.62, blue: 1)
            case .green: Color(red: 0.31, green: 1, blue: 0.56)
            case .white: Color(red: 0.69, green: 0.81, blue: 0.89)
            case .yellow: Color(red: 1, green: 0.70, blue: 0.24)
            case .mutedRed: Color(red: 0.69, green: 0.25, blue: 0.18)
            }
        }

        var beam: Color {
            switch self {
            case .blue: Color(red: 0.51, green: 0.79, blue: 1)
            case .green: Color(red: 0.58, green: 1, blue: 0.72)
            case .white: Color(red: 0.95, green: 0.98, blue: 1)
            case .yellow: Color(red: 1, green: 0.89, blue: 0.49)
            case .mutedRed: Color(red: 0.86, green: 0.47, blue: 0.37)
            }
        }
    }

    let size: CGSize
    let time: Double
    let animateInterference: Bool
    let motion: CabinetMotion

    private var bounds: CGRect { CGRect(origin: .zero, size: size) }
    private var center: CGPoint { CGPoint(x: size.width / 2, y: size.height / 2) }
    private var plotStart: Double { max(54, size.width * 0.054) }
    private var syncTear: Double? {
        guard animateInterference else { return nil }
        return (size.height + 100) * (time * 0.10).truncatingRemainder(dividingBy: 1) - 50
    }

    func drawFace(in context: GraphicsContext) {
        context.fill(Path(bounds), with: .radialGradient(
            Gradient(colors: [Color(red: 0.028, green: 0.070, blue: 0.082),
                              Color(red: 0.011, green: 0.038, blue: 0.050),
                              Color(red: 0.004, green: 0.014, blue: 0.022)]),
            center: center, startRadius: 0, endRadius: max(size.width, size.height) * 0.62
        ))
    }

    func drawTraces(_ notes: [MiddyModel.PlayedNote], through beat: Double, in context: GraphicsContext) {
        let sweepX = size.width * 0.93
        let pointsPerBeat = (sweepX - plotStart) / 14
        let traces: [Trace] = notes.compactMap { played in
            let start = sweepX + (played.beat - beat) * pointsPerBeat
            let gateEnd = start + played.note.duration * pointsPerBeat
            let end = min(gateEnd, sweepX)
            guard end > plotStart, start < end else { return nil }

            let note = played.note
            let velocity = Double(note.velocity) / 127
            let age = max(0, beat - played.beat)
            let persistence = 0.30 + 0.70 * exp(-age / 8.5)
            let y = elevation(note)
            let left = max(plotStart - 6, start)
            let subdivisions = max(1, Int(ceil((end - left) / 4)))
            var path = Path()
            path.move(to: project(x: left, y: y, signalInterference: true))
            for index in 1...subdivisions {
                let x = left + (end - left) * Double(index) / Double(subdivisions)
                let travel = x - start
                let ring = 1.10 * sin(travel * 0.96) * exp(-travel / 7.8)
                let ripple = 0.29 * sin(x * 0.21 + y * 0.31 + time * 8)
                path.addLine(to: project(x: x, y: y - ring + ripple, signalInterference: true))
            }
            return Trace(path: path, intensity: persistence, width: 0.52 + velocity * 2.3,
                         phosphor: phosphor(for: note))
        }

        var plot = context
        plot.clip(to: Path(CGRect(x: plotStart, y: 0, width: size.width - plotStart, height: size.height)))
        plot.drawLayer { glow in
            glow.addFilter(.blur(radius: 6))
            for trace in traces {
                glow.stroke(trace.path, with: .color(trace.phosphor.glow.opacity(trace.intensity * 0.70)),
                            lineWidth: trace.width + 3.4)
            }
        }
        plot.drawLayer { halo in
            halo.addFilter(.blur(radius: 1.65))
            for trace in traces {
                halo.stroke(trace.path, with: .color(trace.phosphor.glow.opacity(trace.intensity * 0.70)),
                            lineWidth: trace.width + 1.2)
            }
        }
        for trace in traces {
            plot.stroke(trace.path, with: .color(trace.phosphor.beam.opacity(trace.intensity)),
                        style: StrokeStyle(lineWidth: trace.width, lineCap: .butt, lineJoin: .round))
        }
    }

    func drawLabels(in context: GraphicsContext) {
        for voice in Voice.allCases {
            let lane = channel(voice)
            let y = lane.height * size.height
            let point = project(x: plotStart * 0.51, y: y)
            var label = context
            label.translateBy(x: point.x, y: point.y)
            label.rotate(by: .degrees(-90))
            let lines: [String]
            switch voice {
            case .subBass: lines = ["SUB", "BASS \(voice.rawValue)"]
            case .formants: lines = [lane.label, String(voice.rawValue)]
            default: lines = ["\(lane.label) \(voice.rawValue)"]
            }
            let fontSize = min(11, max(8.5, size.height / 56))
            for (index, line) in lines.enumerated() {
                let lineOffset = (Double(index) - Double(lines.count - 1) / 2) * (fontSize + 2)
                label.draw(
                    Text(line)
                        .font(.system(size: fontSize, weight: .semibold, design: .monospaced))
                        .tracking(0.64)
                        .foregroundStyle(lane.phosphor.beam.opacity(0.90)),
                    at: CGPoint(x: 0, y: lineOffset)
                )
            }
        }
    }

    func drawReadout(_ value: String, in context: GraphicsContext) {
        let at = project(x: 18, y: 22)
        let label = Text(value)
            .font(.system(size: 14, weight: .medium, design: .monospaced))
            .tracking(1.9)
            .foregroundStyle(Phosphor.green.beam.opacity(0.93))
        context.drawLayer { bloom in
            bloom.addFilter(.blur(radius: 3))
            bloom.opacity = 0.55
            bloom.draw(label, at: at, anchor: .leading)
        }
        context.draw(label, at: at, anchor: .leading)
    }

    func drawDice(brightness: Double, in context: GraphicsContext) {
        let x = size.width - DiceControl.trailing - DiceControl.size / 2
        let y = DiceControl.top + DiceControl.size / 2

        func projected(_ point: CGPoint) -> CGPoint {
            project(x: x + point.x, y: y + point.y, signalInterference: true)
        }

        let rear: [CGPoint] = [
            .init(x: -4, y: 4), .init(x: -7, y: 4), .init(x: -8.5, y: 2.5),
            .init(x: -8.5, y: -7), .init(x: -7, y: -8.5), .init(x: 2.5, y: -8.5),
            .init(x: 4, y: -7), .init(x: 4, y: -4)
        ]
        let front: [CGPoint] = [
            .init(x: -2.5, y: -4), .init(x: 7, y: -4), .init(x: 8.5, y: -2.5),
            .init(x: 8.5, y: 7), .init(x: 7, y: 8.5), .init(x: -2.5, y: 8.5),
            .init(x: -4, y: 7), .init(x: -4, y: -2.5)
        ]
        var glyph = Path()
        glyph.addLines(rear.map(projected))
        glyph.move(to: projected(front[0]))
        glyph.addLines(front.map(projected))
        glyph.closeSubpath()
        var pips = Path()
        for pip in [CGPoint(x: -5.6, y: -5.6), CGPoint(x: -0.8, y: -0.8),
                    CGPoint(x: 2.25, y: 2.25), CGPoint(x: 5.25, y: 5.25)] {
            let dot = projected(pip)
            pips.addEllipse(in: CGRect(x: dot.x - 0.7, y: dot.y - 0.7, width: 1.4, height: 1.4))
        }

        context.drawLayer { bloom in
            bloom.addFilter(.blur(radius: 3))
            let glow = Phosphor.green.glow.opacity(brightness)
            bloom.stroke(glyph, with: .color(glow), lineWidth: 3)
            bloom.fill(pips, with: .color(glow))
        }
        let ink = Phosphor.green.beam.opacity(brightness)
        context.stroke(glyph, with: .color(ink), style: StrokeStyle(lineWidth: 1.13, lineJoin: .round))
        context.fill(pips, with: .color(ink))
    }

    func drawRaster(in context: GraphicsContext) {
        var scanlines = Path()
        for row in stride(from: 0.5, to: size.height, by: 2.75) {
            scanlines.move(to: CGPoint(x: 0, y: row))
            scanlines.addLine(to: CGPoint(x: size.width, y: row))
        }
        context.stroke(scanlines, with: .color(.black.opacity(0.32)), lineWidth: 0.85)

        if let syncTear, syncTear > -12, syncTear < size.height + 12 {
            var interruptions = Path()
            let field = floor(time * 23)
            for index in 0..<34 {
                let seed = Double(index) + field * 29.7
                let x = fract(sin(seed * 51.27) * 13789.54) * size.width
                let y = syncTear + Double(index % 8) * 1.15 - 5
                let width = 3 + fract(sin(seed * 78.31) * 9791.21) * 36
                interruptions.addRect(CGRect(x: x, y: y, width: width, height: 0.55))
            }
            context.fill(interruptions, with: .color(Phosphor.blue.beam.opacity(0.18)))
        }

        var noise = Path()
        let frame = floor(time * 23)
        for index in 0..<540 {
            let sample = Double(index)
            let x = fract(sin(sample * 81.37 + frame * 6.616) * 12719.36) * size.width
            let y = fract(sin(sample * 41.91 + frame * 17.96) * 45326.56) * size.height
            noise.addRect(CGRect(x: x, y: y, width: index.isMultiple(of: 12) ? 1.8 : 0.8, height: 0.65))
        }
        context.fill(noise, with: .color(Phosphor.blue.beam.opacity(0.13)))

        context.fill(Path(bounds), with: .linearGradient(
            Gradient(stops: [.init(color: .white.opacity(0.075), location: 0),
                             .init(color: .white.opacity(0.020), location: 0.24),
                             .init(color: .clear, location: 0.46)]),
            startPoint: .zero, endPoint: CGPoint(x: size.width * 0.46, y: size.height)
        ))
        context.fill(Path(bounds), with: .radialGradient(
            Gradient(stops: [.init(color: .clear, location: 0.45), .init(color: .black.opacity(0.62), location: 1)]),
            center: center, startRadius: 0, endRadius: max(size.width, size.height) * 0.58
        ))
    }

    private func channel(_ voice: Voice) -> (label: String, height: Double, phosphor: Phosphor) {
        switch voice {
        case .plucks: ("PLUCKS", 0.159, .yellow)
        case .lead: ("LEAD", 0.260, .white)
        case .formants: ("FORMANTS", 0.373, .yellow)
        case .pad: ("PAD", 0.470, .green)
        case .drone: ("DRONE", 0.575, .blue)
        case .drums: ("DRUMS", 0.684, .blue)
        case .bass: ("BASS", 0.794, .green)
        case .subBass: ("SUB BASS", 0.906, .green)
        }
    }

    private func phosphor(for note: Note) -> Phosphor {
        if note.voice == .drums, note.beat >= 3.5,
           note.pitch == DrumPad.snare.rawValue || note.pitch == DrumPad.cymbal.rawValue {
            return .mutedRed
        }
        return channel(note.voice).phosphor
    }

    private func elevation(_ note: Note) -> Double {
        let pitch = Double(note.pitch)
        let offset: Double
        switch note.voice {
        case .plucks: offset = -0.036 * tanh((pitch - 77) / 13)
        case .lead: offset = -0.047 * tanh((pitch - 65) / 13)
        case .formants: offset = -0.038 * tanh((pitch - 65) / 11)
        case .bass: offset = -0.045 * tanh((pitch - 41) / 13)
        case .subBass: offset = -0.040 * tanh((pitch - 29) / 13)
        case .drums:
            switch DrumPad(rawValue: note.pitch) {
            case .kick: offset = 0.044
            case .snare: offset = 0.027
            case .clap: offset = 0.010
            case .closedHat: offset = -0.025
            case .cymbal: offset = -0.046
            case .shaker: offset = -0.037
            case .tambourine: offset = -0.055
            case nil: offset = 0
            }
        case .pad: offset = -0.050 * tanh((pitch - 56) / 14)
        case .drone: offset = -0.044 * tanh((pitch - 58) / 13)
        }
        return (channel(note.voice).height + offset) * size.height
    }

    private func project(x: Double, y: Double, signalInterference: Bool = false) -> CGPoint {
        guard size.width > 0, size.height > 0 else { return .zero }
        let u = (x - center.x) / center.x
        let v = (y - center.y) / center.y
        let curved = CGPoint(x: x - u * v * v * size.width * 0.022,
                             y: y - v * u * u * size.height * 0.037)
        guard signalInterference else { return curved }

        let flutter = sin(time * 17 + y * 0.14) * 0.52 + sin(time * 4.1 + y * 0.035) * 0.35
        let tear = syncTear.map { line in
            let distance = abs(y - line)
            return distance < 5 ? sin(y * 1.31 + time * 51) * (1 - distance / 5) * 4.5 : 0
        } ?? 0
        return CGPoint(
            x: curved.x + flutter + tear + motion.horizontal * (0.7 + 0.3 * v),
            y: curved.y + motion.vertical * (1 - 0.30 * u * u)
        )
    }

    private func fract(_ value: Double) -> Double { value - floor(value) }
}
