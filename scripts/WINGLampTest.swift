import CoreMIDI
import Foundation
import Darwin

private final class Received: @unchecked Sendable {
    let semaphore = DispatchSemaphore(value: 0)
    let lock = NSLock()
    var bytes: [[UInt8]] = []
    func accept(_ packets: [[UInt8]]) {
        lock.withLock { bytes.append(contentsOf: packets) }
        semaphore.signal()
    }
    func snapshot() -> [[UInt8]] { lock.withLock { bytes } }
}

@main struct WINGLampTest {
    static func main() throws {
        setbuf(stdout, nil)
        var client: MIDIClientRef = 0
        guard MIDIClientCreateWithBlock("LiveCue lamp diagnostic" as CFString, &client, { _ in }) == noErr else { fatalError("Cannot create MIDI client") }
        defer { MIDIClientDispose(client) }
        var port: MIDIPortRef = 0
        guard MIDIOutputPortCreate(client, "Lamp test output" as CFString, &port) == noErr else { fatalError("Cannot create output port") }
        defer { MIDIPortDispose(port) }

        if CommandLine.arguments.contains("--self-test") {
            let received = Received()
            var virtual: MIDIEndpointRef = 0
            let status = MIDIDestinationCreateWithBlock(client, "LiveCue lamp packet test" as CFString, &virtual) { list, _ in received.accept(MIDIWire.packets(list)) }
            guard status == noErr else { fatalError("Cannot create virtual destination: \(status)") }
            defer { MIDIEndpointDispose(virtual) }
            for bytes: [UInt8] in [[0xB5, 0x10, 0x7F], [0xB5, 0x10, 0x00]] {
                precondition(MIDIWire.send(bytes, port: port, destination: virtual) == noErr)
                precondition(received.semaphore.wait(timeout: .now() + 3) == .success, "No MIDI callback")
            }
            precondition(received.snapshot() == [[0xB5, 0x10, 0x7F], [0xB5, 0x10, 0x00]], "Wrong wire bytes")
            print("PASS: actual CoreMIDI virtual destination received B5 10 7F and B5 10 00 in order")
            return
        }
        guard CommandLine.arguments.contains("--run") else { print("Use --self-test or --run"); return }
        let stopURL = URL(fileURLWithPath: "/private/tmp/livecue-wing-lamp.stop")
        if FileManager.default.fileExists(atPath: stopURL.path) { try FileManager.default.removeItem(at: stopURL) }
        let network = CommandLine.arguments.contains("--network")
        var endpoint: MIDIEndpointRef = 0
        for index in 0..<MIDIGetNumberOfDestinations() {
            let candidate = MIDIGetDestination(index)
            var value: Unmanaged<CFString>?
            if MIDIObjectGetStringProperty(candidate, kMIDIPropertyDisplayName, &value) == noErr, let value {
                let name = value.takeRetainedValue() as String
                if (network && name == "Network Danny Macbook") || (!network && name == "WING Port 4") {
                    endpoint = candidate
                    print("Selected \(name), endpoint \(endpoint)")
                }
            }
        }
        guard endpoint != 0 else { fatalError("MIDI destination is unavailable") }
        print("ATTEMPT \(network ? "4 NETWORK RUNLOOP" : "1 USB"): channel 6 / CC16, ON 127 / OFF 0 every 500 ms. Stop by creating \(stopURL.path)")
        var on = true
        var count = 0
        while !FileManager.default.fileExists(atPath: stopURL.path) {
            let bytes: [UInt8] = [0xB5, 0x10, on ? 0x7F : 0x00]
            let status = MIDIWire.send(bytes, port: port, destination: endpoint)
            guard status == noErr else { print("SEND FAILED: \(status). Stopping."); break }
            count += 1
            if count <= 4 || count % 60 == 0 { print("\(Date().ISO8601Format()) sent \(count): \(on ? "B5 10 7F ON" : "B5 10 00 OFF"), CoreMIDI status 0") }
            on.toggle()
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        let status = MIDIWire.send([0xB5, 0x10, 0], port: port, destination: endpoint)
        print("Stopped. Final lamp OFF send status: \(status)")
    }
}
