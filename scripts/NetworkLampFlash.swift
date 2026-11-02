import CoreMIDI
import Foundation

// Flashes the WING lamp (channel 6, CC 16) through a named CoreMIDI destination.
// Usage: NetworkLampFlash "<destination name>" [--loop <stop file>]
let args = CommandLine.arguments
guard args.count > 1 else {
    print("Usage: NetworkLampFlash \"<destination name>\" [--loop <stop file>]")
    exit(2)
}

var client = MIDIClientRef()
MIDIClientCreateWithBlock("Lamp test" as CFString, &client) { _ in }
var port = MIDIPortRef()
MIDIOutputPortCreate(client, "Lamp test output" as CFString, &port)

var destination: MIDIEndpointRef = 0
for i in 0..<MIDIGetNumberOfDestinations() {
    let endpoint = MIDIGetDestination(i)
    var name: Unmanaged<CFString>?
    if MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &name) == noErr,
       let name, (name.takeRetainedValue() as String) == args[1] {
        destination = endpoint
    }
}
guard destination != 0 else { print("Destination \"\(args[1])\" not found"); exit(1) }

func send(_ value: UInt8) -> OSStatus {
    var list = MIDIPacketList()
    let first = MIDIPacketListInit(&list)
    let bytes: [UInt8] = [0xB5, 0x10, value]
    _ = MIDIPacketListAdd(&list, MemoryLayout<MIDIPacketList>.size, first, 0, bytes.count, bytes)
    return MIDISend(port, destination, &list)
}

if let flag = args.firstIndex(of: "--loop"), args.count > flag + 1 {
    let stop = args[flag + 1]
    var on = true
    var count = 0
    while !FileManager.default.fileExists(atPath: stop) {
        let status = send(on ? 127 : 0)
        guard status == noErr else { print("Send failed: \(status)"); break }
        count += 1
        on.toggle()
        usleep(500_000)
    }
    print("Stopped after \(count) sends")
} else {
    for step in 0..<12 {
        let value: UInt8 = step.isMultiple(of: 2) ? 127 : 0
        print(step, value, send(value))
        usleep(250_000)
    }
}
print("Final OFF status:", send(0))
usleep(300_000)
