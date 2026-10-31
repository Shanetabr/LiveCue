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
            if !synchronizingSession { updateConnections(previous: oldValue) }
        }
    }
    public var isConnected: Bool = false
    public var lastError: String?

    private var midiClient: MIDIClientRef = 0
    private var outputPort: MIDIPortRef = 0

    private let browserQueue = DispatchQueue(label: "local.livecue.app.MIDIBrowser")
    private var browser: NWBrowser?
    private var resolving: [String: NWConnection] = [:]
    private var sessionObserver: NSObjectProtocol?
    private var synchronizingSession = false
    public private(set) var sentMessageCount = 0

    private let session = MIDINetworkSession.default()

    // Store hosts by ID for connection management
    private var hosts: [String: MIDINetworkHost] = [:]

    public init() {
        setupCoreMIDI()
        setupNetworkSession()
        refreshConnectionState()
        sessionObserver = NotificationCenter.default.addObserver(forName: NSNotification.Name(MIDINetworkNotificationSessionDidChange), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshConnectionState() }
        }
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
            let key = endpoint.debugDescription
            guard resolving[key] == nil else { return }
            let connection = NWConnection(to: endpoint, using: .udp)
            resolving[key] = connection
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
                    Task { @MainActor [weak self] in self?.resolving.removeValue(forKey: key) }
                case .failed, .cancelled:
                    Task { @MainActor [weak self] in self?.resolving.removeValue(forKey: key) }
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

    private func updateConnections(previous: Set<String> = []) {
        // Only an explicit deselection may remove a connection. Discovery must never
        // tear down participants connected through Audio MIDI Setup.
        for connection in session.connections() {
            let id = "\(connection.host.address):\(connection.host.port)"
            if previous.subtracting(selectedDestinationIDs).contains(id) {
                session.removeConnection(connection)
            }
        }
        for id in selectedDestinationIDs {
            if let host = hosts[id], !session.connections().contains(where: { $0.host.hasSameAddress(as: host) }) {
                if !session.addConnection(MIDINetworkConnection(host: host)) {
                    lastError = "Could not add MIDI connection to \(host.name)"
                }
            }
        }
        refreshConnectionState()
    }

    private func refreshConnectionState() {
        let connections = session.connections()
        synchronizingSession = true
        defer { synchronizingSession = false }
        for connection in connections {
            let host = connection.host
            let id = "\(host.address):\(host.port)"
            hosts[id] = host
            if !destinations.contains(where: { $0.id == id }) {
                destinations.append(MIDIDestination(id: id, name: host.name, address: host.address, port: UInt16(clamping: host.port), isConnected: true, isManual: false))
            }
            selectedDestinationIDs.insert(id)
        }
        for i in destinations.indices {
            destinations[i].isConnected = connections.contains { connection in
                guard let host = hosts[destinations[i].id] else { return false }
                return connection.host.hasSameAddress(as: host)
            }
        }
        isConnected = !connections.isEmpty
    }

    // MARK: - Sending MIDI

    private func sendUMP(words: [UInt32]) {
        refreshConnectionState()
        guard !session.connections().isEmpty else {
            lastError = "No network MIDI participants. Connect the WING bridge Mac in Audio MIDI Setup or select it here."
            return
        }
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
        } else {
            lastError = nil
            sentMessageCount += 1
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

    // A single task owns the lamp so repeated cues cannot interleave on/off messages.
    private var lampFlashTask: Task<Void, Never>?

    public func flashWINGLamp() {
        lampFlashTask?.cancel()
        sendControlChange(channel: 5, controller: 16, value: 127)
        lampFlashTask = Task { @MainActor [weak self] in
            let clock = ContinuousClock()
            let start = clock.now
            do {
                // Six half-second flashes; use absolute deadlines to avoid timing drift.
                for step in 1...11 {
                    try await clock.sleep(until: start.advanced(by: .milliseconds(step * 250)))
                    try Task.checkCancellation()
                    self?.sendControlChange(channel: 5, controller: 16, value: step.isMultiple(of: 2) ? 127 : 0)
                }
                try await clock.sleep(until: start.advanced(by: .seconds(3)))
                try Task.checkCancellation()
                self?.sendControlChange(channel: 5, controller: 16, value: 0)
                self?.lampFlashTask = nil
            } catch {
                // A replacement flash owns the lamp after cancellation.
            }
        }
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
        refreshConnectionState()
        guard !session.connections().isEmpty else {
            lastError = "No network MIDI participants. Connect the WING bridge Mac in Audio MIDI Setup or select it here."
            return
        }
        let destination = session.destinationEndpoint()
        if destination == 0 {
            lastError = "Network session destination endpoint not available"
            return
        }

        var packetList = MIDIPacketList()
        var packet = MIDIPacketListInit(&packetList)
        guard bytes.count <= 256 else {
            lastError = "SysEx exceeds MIDI packet capacity"
            return
        }
        packet = MIDIPacketListAdd(&packetList, MemoryLayout<MIDIPacketList>.size, packet, 0, bytes.count, bytes)

        let status = MIDISend(outputPort, destination, &packetList)
        if status != noErr {
            self.lastError = "Failed to send SysEx: \(status)"
        }
    }
}
