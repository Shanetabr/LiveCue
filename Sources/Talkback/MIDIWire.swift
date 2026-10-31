import CoreMIDI
import Foundation

/// MIDI 1.0 bytes shared by USB and Apple network MIDI, with real packet-list bounds.
enum MIDIWire {
    static func send(_ bytes: [UInt8], port: MIDIPortRef, destination: MIDIEndpointRef) -> OSStatus {
        guard !bytes.isEmpty, bytes.count <= 256, port != 0, destination != 0 else { return kMIDIInvalidClient }
        var list = MIDIPacketList()
        let first = MIDIPacketListInit(&list)
        let added: UnsafeMutablePointer<MIDIPacket>? = MIDIPacketListAdd(&list, MemoryLayout<MIDIPacketList>.size, first, 0, bytes.count, bytes)
        guard added != nil else {
            return kMIDIMessageSendErr
        }
        return MIDISend(port, destination, &list)
    }

    static func packets(_ list: UnsafePointer<MIDIPacketList>) -> [[UInt8]] {
        var result: [[UInt8]] = []
        var packet = UnsafeRawPointer(list).advanced(by: MemoryLayout<MIDIPacketList>.offset(of: \.packet)!).assumingMemoryBound(to: MIDIPacket.self)
        for _ in 0..<list.pointee.numPackets {
            let data = UnsafeRawPointer(packet).advanced(by: MemoryLayout<MIDIPacket>.offset(of: \.data)!).assumingMemoryBound(to: UInt8.self)
            result.append(Array(UnsafeBufferPointer(start: data, count: Int(packet.pointee.length))))
            packet = UnsafePointer(MIDIPacketNext(packet))
        }
        return result
    }
}
