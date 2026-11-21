import CoreMIDI
import Foundation
import Darwin

private final class PacketCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [UInt8] = []
    func receive(_ list: UnsafePointer<MIDIPacketList>) {
        let bytes = MIDIWire.packets(list).flatMap { $0 }
        lock.withLock { stored.append(contentsOf: bytes) }
    }
    var bytes: [UInt8] { lock.withLock { stored } }
}

/// Exercises real CoreMIDI callbacks using virtual endpoints only. Never sends
/// to physical USB devices or to the actual Network MIDI driver destinations.
@main
struct NetworkMIDITest {
    @MainActor
    static func main() async throws {
        setbuf(stdout, nil)
        print("Starting virtual CoreMIDI regression")
        var client: MIDIClientRef = 0
        precondition(MIDIClientCreateWithBlock("LiveCue network regression" as CFString, &client, { @Sendable _ in }) == noErr)
        defer { MIDIClientDispose(client) }
        let capture = PacketCapture()
        var destination: MIDIEndpointRef = 0
        var source: MIDIEndpointRef = 0
        precondition(MIDIDestinationCreateWithBlock(client, "Network LiveCue virtual test output" as CFString, &destination, { @Sendable list, _ in capture.receive(list) }) == noErr)
        precondition(MIDISourceCreate(client, "Network LiveCue virtual test input" as CFString, &source) == noErr)
        defer {
            if destination != 0 { MIDIEndpointDispose(destination) }
            MIDIEndpointDispose(source)
        }
        var outputID: MIDIUniqueID = 0
        var inputID: MIDIUniqueID = 0
        precondition(MIDIObjectGetIntegerProperty(destination, kMIDIPropertyUniqueID, &outputID) == noErr)
        precondition(MIDIObjectGetIntegerProperty(source, kMIDIPropertyUniqueID, &inputID) == noErr)

        let engine = MIDIEngine()
        engine.heartbeatEnabled = false  // keep bridge pings out of the captured bytes
        print("Available network outputs: \(engine.networkOutputs.map(\.name))")
        print("Available network inputs: \(engine.networkInputs.map(\.name))")
        precondition(engine.networkOutputs.contains { $0.id == outputID && $0.endpoint == destination })
        precondition(engine.networkInputs.contains { $0.id == inputID && $0.endpoint == source })
        engine.selectedNetworkOutputID = outputID
        engine.selectedNetworkInputID = inputID
        precondition(engine.networkPortAvailable)
        // An unknown/default-session participant list must not prevent a send
        // through an explicitly selected, enumerated endpoint.
        engine.sendControlChange(channel: 5, controller: 16, value: 127)
        engine.sendControlChange(channel: 5, controller: 16, value: 0)
        try await Task.sleep(for: .milliseconds(150))
        precondition(capture.bytes == [0xB5, 0x10, 0x7F, 0xB5, 0x10, 0])
        precondition(engine.sentMessageCount == 2)

        var list = MIDIPacketList()
        let first = MIDIPacketListInit(&list)
        let received: [UInt8] = [0xB5, 0x10, 0x7F]
        let packet: UnsafeMutablePointer<MIDIPacket>? = MIDIPacketListAdd(&list, MemoryLayout<MIDIPacketList>.size, first, 0, received.count, received)
        precondition(packet != nil)
        precondition(MIDIReceived(source, &list) == noErr)
        try await Task.sleep(for: .milliseconds(150))
        precondition(engine.receivedNetworkMessages == 1)
        precondition(engine.lastReceivedMIDI == "B5 10 7F")
        precondition(engine.forwardedMessages == 0)

        // Connection test: a ping goes out on the selected output, and the bridge's
        // reply on the selected input resolves it with the WING flag and version.
        let before = capture.bytes.count
        let pending = Task { @MainActor in await engine.pingBridge(timeout: .seconds(2)) }
        try await Task.sleep(for: .milliseconds(150))
        let ping = Array(capture.bytes.dropFirst(before))
        precondition(ping.count == 7 && ping[0] == 0xF0 && ping[1] == 0x7D && ping[4] == 0x01, "ping bytes: \(ping)")
        var replyList = MIDIPacketList()
        let replyBytes: [UInt8] = [0xF0, 0x7D, 0x4C, 0x43, 0x02, ping[5], 0x01, 0x01, 0x01, 0xF7]
        precondition(MIDIPacketListAdd(&replyList, MemoryLayout<MIDIPacketList>.size, MIDIPacketListInit(&replyList), 0, replyBytes.count, replyBytes) != nil)
        precondition(MIDIReceived(source, &replyList) == noErr)
        let reply = await pending.value
        precondition(reply?.wingFound == true && reply?.version == "1.1", "reply: \(String(describing: reply))")
        precondition(engine.receivedNetworkMessages == 1, "replies are not counted as received cues")
        let silent = await engine.pingBridge(timeout: .milliseconds(300))
        precondition(silent == nil, "no reply means nil")
        print("PASS: bridge ping out, reply in, no reply times out")

        // A rename must preserve the unique-ID selection and input subscription.
        precondition(MIDIObjectSetStringProperty(destination, kMIDIPropertyName, "Network Renamed virtual test output" as CFString) == noErr)
        engine.refreshMIDIPorts()
        precondition(engine.selectedNetworkOutputID == outputID && engine.networkPortAvailable)
        precondition(engine.selectedNetworkInputID == inputID)

        // Removing that output must not redirect subsequent cues to any real
        // network port that happens to exist on the machine running the test.
        precondition(MIDIEndpointDispose(destination) == noErr)
        destination = 0
        engine.refreshMIDIPorts()
        precondition(engine.selectedNetworkOutputID == outputID && !engine.networkPortAvailable)
        engine.sendControlChange(channel: 5, controller: 16, value: 127)
        precondition(engine.sentMessageCount == 2)
        precondition(engine.lastError?.contains("unavailable") == true)

        // Likewise, a missing USB selection must remain a failed USB route.
        engine.selectedUSBOutput = MIDIEndpointRef.max
        engine.refreshMIDIPorts()
        precondition(engine.selectedUSBOutput == MIDIEndpointRef.max)
        engine.sendControlChange(channel: 5, controller: 16, value: 127)
        precondition(engine.sentMessageCount == 2)
        precondition(engine.lastError?.contains("USB output is unavailable") == true)
        print("PASS: enumerated network send/receive, selection after rename, and no fallback after disconnection")
    }
}
