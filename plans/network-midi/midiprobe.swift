import CoreMIDI
import Foundation

// Network MIDI diagnostics for the WING lamp tests. See 1-church-day-runbook.md.
// Usage:
//   midiprobe list                         every device, source and destination, incl. offline ones
//   midiprobe listen "<source name>"       print what arrives on a source, with its timestamp
//   midiprobe dest                         create a "LiveCue Probe" destination and print what arrives
//   midiprobe flash "<destination>" [--loop]   ch 6 CC 16 ON/OFF; Ctrl-C stops a loop; always ends OFF
setbuf(stdout, nil)
let args = Array(CommandLine.arguments.dropFirst())

var timebase = mach_timebase_info_data_t()
mach_timebase_info(&timebase)
func milliseconds(_ ticks: Int64) -> Double {
    Double(ticks) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000
}

func string(_ object: MIDIObjectRef, _ key: CFString = kMIDIPropertyDisplayName) -> String {
    var value: Unmanaged<CFString>?
    guard MIDIObjectGetStringProperty(object, key, &value) == noErr, let value else { return "-" }
    return value.takeRetainedValue() as String
}

func integer(_ object: MIDIObjectRef, _ key: CFString) -> Int32 {
    var value: Int32 = 0
    MIDIObjectGetIntegerProperty(object, key, &value)
    return value
}

func timeOfDay() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    return formatter.string(from: Date())
}

// Prints each packet's bytes and how far its timestamp is from now. A large
// positive offset means CoreMIDI will hold the message that long before a
// hardware port plays it.
func report(_ list: UnsafePointer<MIDIPacketList>) {
    let now = mach_absolute_time()
    for packet in list.unsafeSequence() {
        let length = Int(packet.pointee.length)
        let data = UnsafeRawPointer(packet) + MemoryLayout<MIDIPacket>.offset(of: \MIDIPacket.data)!
        let bytes = UnsafeRawBufferPointer(start: data, count: length).map { String(format: "%02X", $0) }
        let stamp = packet.pointee.timeStamp
        let timing = stamp == 0 ? "timestamp 0 (now)"
            : String(format: "timestamp %+.1f ms from now", milliseconds(Int64(bitPattern: stamp &- now)))
        print("\(timeOfDay())  \(bytes.joined(separator: " "))  \(timing)")
    }
}

var client = MIDIClientRef()
MIDIClientCreateWithBlock("midiprobe" as CFString, &client) { _ in }

func endpoint(named name: String, sources: Bool) -> MIDIEndpointRef? {
    let count = sources ? MIDIGetNumberOfSources() : MIDIGetNumberOfDestinations()
    for index in 0..<count {
        let candidate = sources ? MIDIGetSource(index) : MIDIGetDestination(index)
        if string(candidate) == name || string(candidate, kMIDIPropertyName) == name { return candidate }
    }
    print("\(sources ? "Source" : "Destination") \"\(name)\" not found. Run: midiprobe list")
    exit(1)
}

switch args.first {
case "list":
    print("DEVICES (offline = greyed out in MIDI Studio)")
    for index in 0..<MIDIGetNumberOfDevices() {
        let device = MIDIGetDevice(index)
        let offline = integer(device, kMIDIPropertyOffline) != 0 ? "OFFLINE" : "online"
        print("  \(string(device, kMIDIPropertyName))  [\(offline)]  id \(integer(device, kMIDIPropertyUniqueID))  driver \(string(device, kMIDIPropertyDriverOwner))")
    }
    for (title, count, get) in [("SOURCES", MIDIGetNumberOfSources(), MIDIGetSource),
                                ("DESTINATIONS", MIDIGetNumberOfDestinations(), MIDIGetDestination)] {
        print(title)
        for index in 0..<count {
            let point = get(index)
            let offline = integer(point, kMIDIPropertyOffline) != 0 ? "  OFFLINE" : ""
            print("  \(string(point))  id \(integer(point, kMIDIPropertyUniqueID))\(offline)")
        }
    }

case "listen" where args.count > 1:
    let source = endpoint(named: args[1], sources: true)!
    var input = MIDIPortRef()
    MIDIInputPortCreateWithBlock(client, "midiprobe input" as CFString, &input) { list, _ in report(list) }
    print("Listening to \"\(args[1])\". Ctrl-C to stop.", MIDIPortConnectSource(input, source, nil))
    RunLoop.main.run()

case "dest":
    var destination = MIDIEndpointRef()
    let status = MIDIDestinationCreateWithBlock(client, "LiveCue Probe" as CFString, &destination) { list, _ in report(list) }
    print("Created destination \"LiveCue Probe\" (status \(status)). Pick it in a Live routing. Ctrl-C to stop.")
    RunLoop.main.run()

case "flash" where args.count > 1:
    let destination = endpoint(named: args[1], sources: false)!
    var output = MIDIPortRef()
    MIDIOutputPortCreate(client, "midiprobe output" as CFString, &output)
    func send(_ value: UInt8) -> OSStatus {
        var list = MIDIPacketList()
        let first = MIDIPacketListInit(&list)
        let bytes: [UInt8] = [0xB5, 0x10, value]
        _ = MIDIPacketListAdd(&list, MemoryLayout<MIDIPacketList>.size, first, 0, bytes.count, bytes)
        return MIDISend(output, destination, &list)
    }
    func finish() -> Never {
        print("Final OFF status:", send(0))
        usleep(300_000)
        exit(0)
    }
    if args.contains("--loop") {
        signal(SIGINT, SIG_IGN)
        let stop = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        stop.setEventHandler { finish() }
        stop.resume()
        var on = true
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            print(timeOfDay(), on ? "ON " : "OFF", send(on ? 127 : 0))
            on.toggle()
        }
        print("Flashing \"\(args[1])\" every 0.5 s. Ctrl-C to stop.")
        RunLoop.main.run()
    }
    for step in 0..<12 {
        let value: UInt8 = step.isMultiple(of: 2) ? 127 : 0
        print(timeOfDay(), value == 127 ? "ON " : "OFF", send(value))
        usleep(250_000)
    }
    finish()

default:
    print("""
    Usage:
      midiprobe list
      midiprobe listen "<source name>"
      midiprobe dest
      midiprobe flash "<destination>" [--loop]
    """)
}
