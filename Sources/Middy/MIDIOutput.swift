import CoreMIDI
import Foundation

final class MIDIOutput {
    enum Failure: LocalizedError {
        case setup(OSStatus)

        var errorDescription: String? {
            switch self {
            case .setup(let status): "MIDI output unavailable (\(status))"
            }
        }
    }

    private let client: MIDIClientRef
    private let source: MIDIEndpointRef

    init() throws {
        var client: MIDIClientRef = 0
        let clientStatus = MIDIClientCreateWithBlock("Middy" as CFString, &client, nil)
        guard clientStatus == noErr else { throw Failure.setup(clientStatus) }
        var source: MIDIEndpointRef = 0
        let sourceStatus = MIDISourceCreateWithProtocol(client, "Middy" as CFString, ._1_0, &source)
        guard sourceStatus == noErr else {
            MIDIClientDispose(client)
            throw Failure.setup(sourceStatus)
        }
        let persistentID: MIDIUniqueID = 0x4D696464
        _ = MIDIObjectSetIntegerProperty(source, kMIDIPropertyUniqueID, persistentID)
        self.client = client
        self.source = source
    }

    deinit {
        MIDIEndpointDispose(source)
        MIDIClientDispose(client)
    }

    func send(status: UInt8, pitch: UInt8, velocity: UInt8) {
        var events = MIDIEventList()
        let packet = MIDIEventListInit(&events, ._1_0)
        // UMP message type 2 carries a MIDI 1.0 channel voice message.
        var word = 0x2000_0000 | UInt32(status) << 16 | UInt32(pitch) << 8 | UInt32(velocity)
        _ = MIDIEventListAdd(&events, MemoryLayout<MIDIEventList>.size,
                             packet, mach_absolute_time(), 1, &word)
        MIDIReceivedEventList(source, &events)
    }
}
