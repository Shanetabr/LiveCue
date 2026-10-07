import Foundation
import CoreMIDI
import Network
import Observation

public struct MIDIDestination: Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let address: String
    public let port: UInt16
    public var isConnected: Bool
    public let isManual: Bool
}

@Observable
@MainActor
public final class MIDIEngine {
    public var destinations: [MIDIDestination] = []
    public var selectedDestinationIDs: Set<String> = [] {
        didSet {
            updateConnections()
        }
    }
    public var isConnected: Bool = false
    public var lastError: String?

    private var midiClient: MIDIClientRef = 0
    private var outputPort: MIDIPortRef = 0

    private let browserQueue = DispatchQueue(label: "local.livecue.app.MIDIBrowser")
    private var browser: NWBrowser?

    private let session = MIDINetworkSession.default()

    // Store hosts by ID for connection management
    private var hosts: [String: MIDINetworkHost] = [:]

    public init() {
        setupCoreMIDI()
        setupNetworkSession()
        startBonjourDiscovery()
    }

    private func setupCoreMIDI() {
        var status = MIDIClientCreateWithBlock("LiveCue MIDI Client" as CFString, &midiClient) { _ in
            // Handle MIDI setup changes if needed
        }

        if status != noErr {
            lastError = "Failed to create MIDI client: \(status)"
            return
        }

        status = MIDIOutputPortCreate(midiClient, "LiveCue Output" as CFString, &outputPort)
        if status != noErr {
            lastError = "Failed to create MIDI output port: \(status)"
        }
    }

    private func setupNetworkSession() {
        session.isEnabled = true
        session.connectionPolicy = .anyone
    }

    private func startBonjourDiscovery() {
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_apple-midi._udp", domain: "local.")
        let b = NWBrowser(for: descriptor, using: .udp)
        self.browser = b

        b.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                for result in results {
                    self.resolveEndpoint(result.endpoint)
                }
            }
        }

        b.start(queue: browserQueue)
    }

    private func resolveEndpoint(_ endpoint: NWEndpoint) {
        if case let .service(name, _, _, _) = endpoint {
            let connection = NWConnection(to: endpoint, using: .udp)
            connection.stateUpdateHandler = { [weak self, weak connection] state in
                switch state {
                case .ready:
                    if let ep = connection?.currentPath?.remoteEndpoint,
                       case let .hostPort(host, port) = ep {
                        let address = host.debugDescription
                        let portValue = port.rawValue
                        let id = "\(address):\(portValue)"
                        let dest = MIDIDestination(id: id, name: name, address: address, port: portValue, isConnected: false, isManual: false)
                        Task { @MainActor [weak self] in
                            self?.addDiscoveredDestination(dest)
                        }
                    }
                    connection?.cancel()
                default:
                    break
                }
            }
            connection.start(queue: browserQueue)
        }
    }

    private func addDiscoveredDestination(_ dest: MIDIDestination) {
        if !destinations.contains(where: { $0.id == dest.id }) {
            destinations.append(dest)

            let host = MIDINetworkHost(name: dest.name, address: dest.address, port: Int(dest.port))
            hosts[dest.id] = host
            session.addContact(host)

            updateConnections()
        }
    }

    public func addManualDestination(name: String, address: String, port: UInt16) {
        let id = "\(address):\(port)"
        if !destinations.contains(where: { $0.id == id }) {
            let dest = MIDIDestination(id: id, name: name, address: address, port: port, isConnected: false, isManual: true)
            destinations.append(dest)

            let host = MIDINetworkHost(name: dest.name, address: dest.address, port: Int(dest.port))
            hosts[id] = host
            session.addContact(host)

            updateConnections()
        }
    }

    private func updateConnections() {
        // Disconnect unselected
        for connection in session.connections() {
            let host = connection.host
            let id = "\(host.address):\(host.port)"
            if !selectedDestinationIDs.contains(id) {
                session.removeConnection(connection)
            }
        }

        // Connect selected
        for id in selectedDestinationIDs {
            if let host = hosts[id] {
                let isAlreadyConnected = session.connections().contains(where: { $0.host == host })
                if !isAlreadyConnected {
                    let connection = MIDINetworkConnection(host: host)
                    session.addConnection(connection)
                }
            }
        }

        // Update connected state
        var anyConnected = false
        for i in 0..<destinations.count {
            let id = destinations[i].id
            let isConn = session.connections().contains(where: { "\($0.host.address):\($0.host.port)" == id })
            destinations[i].isConnected = isConn
            if isConn {
                anyConnected = true
            }
        }
        isConnected = anyConnected
    }

    // MARK: - Sending MIDI

    private func sendUMP(words: [UInt32]) {
        let destination = session.destinationEndpoint()
        if destination == 0 {
            lastError = "Network session destination endpoint not available"
            return
        }

        var eventList = MIDIEventList()
        let packet = MIDIEventListInit(&eventList, ._1_0)

        MIDIEventListAdd(&eventList, MemoryLayout<MIDIEventList>.size, packet, 0, words.count, words)

        let status = MIDISendEventList(outputPort, destination, &eventList)
        if status != noErr {
            self.lastError = "Failed to send MIDI: \(status)"
        }
    }

    public func sendNoteOn(channel: UInt8, note: UInt8, velocity: UInt8) {
        let ch = channel & 0x0F
        let n = note & 0x7F
        let v = velocity & 0x7F
        let word = UInt32(0x20900000) | (UInt32(ch) << 16) | (UInt32(n) << 8) | UInt32(v)
        sendUMP(words: [word])
    }

    public func sendNoteOff(channel: UInt8, note: UInt8, velocity: UInt8) {
        let ch = channel & 0x0F
        let n = note & 0x7F
        let v = velocity & 0x7F
        let word = UInt32(0x20800000) | (UInt32(ch) << 16) | (UInt32(n) << 8) | UInt32(v)
        sendUMP(words: [word])
    }

    public func sendControlChange(channel: UInt8, controller: UInt8, value: UInt8) {
        let ch = channel & 0x0F
        let c = controller & 0x7F
        let v = value & 0x7F
        let word = UInt32(0x20B00000) | (UInt32(ch) << 16) | (UInt32(c) << 8) | UInt32(v)
        sendUMP(words: [word])
    }

    public func sendProgramChange(channel: UInt8, program: UInt8) {
        let ch = channel & 0x0F
        let p = program & 0x7F
        let word = UInt32(0x20C00000) | (UInt32(ch) << 16) | (UInt32(p) << 8)
        sendUMP(words: [word])
    }

    // MARK: - Sending MSC

    public func sendMSC(deviceID: UInt8, commandFormat: UInt8, command: UInt8, cueNumber: String? = nil, cueList: String? = nil) {
        var sysex: [UInt8] = [
            0xF0, 0x7F,
            deviceID & 0x7F,
            0x02,
            commandFormat & 0x7F,
            command & 0x7F
        ]

        if let cueNumber = cueNumber {
            sysex.append(contentsOf: cueNumber.utf8)

            if let cueList = cueList {
                sysex.append(0x00)
                sysex.append(contentsOf: cueList.utf8)
            }
        }

        sysex.append(0xF7)
        sendSysEx(bytes: sysex)
    }

    private func sendSysEx(bytes: [UInt8]) {
        let destination = session.destinationEndpoint()
        if destination == 0 {
            lastError = "Network session destination endpoint not available"
            return
        }

        var packetList = MIDIPacketList()
        var packet = MIDIPacketListInit(&packetList)
        packet = MIDIPacketListAdd(&packetList, 1024, packet, 0, bytes.count, bytes)

        let status = MIDISend(outputPort, destination, &packetList)
        if status != noErr {
            self.lastError = "Failed to send SysEx: \(status)"
        }
    }
}
