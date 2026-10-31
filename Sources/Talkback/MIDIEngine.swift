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

public struct MIDIUSBOutput: Identifiable, Equatable, Sendable {
    public let id: MIDIEndpointRef
    public let name: String
}

public struct MIDINetworkEndpoint: Identifiable, Equatable, Sendable {
    /// CoreMIDI unique IDs survive endpoint-reference changes and session renaming.
    public let id: MIDIUniqueID
    public let endpoint: MIDIEndpointRef
    public let name: String

    static func selectedID(current: MIDIUniqueID?, available: [MIDINetworkEndpoint]) -> MIDIUniqueID? {
        // Retain an unavailable selection: never silently send to another session.
        current ?? (available.count == 1 ? available[0].id : nil)
    }
}

@Observable
@MainActor
public final class MIDIEngine {
    public var destinations: [MIDIDestination] = []
    // Retained for saved configuration compatibility. Participants are managed in
    // Audio MIDI Setup; MIDINetworkSession's management API is not functional on macOS.
    public var selectedDestinationIDs: Set<String> = []
    public private(set) var isConnected = false // Remote participant state is unknown.
    public private(set) var networkOutputs: [MIDINetworkEndpoint] = []
    public private(set) var networkInputs: [MIDINetworkEndpoint] = []
    public var selectedNetworkOutputID: MIDIUniqueID?
    public var selectedNetworkInputID: MIDIUniqueID? {
        didSet { if oldValue != selectedNetworkInputID { connectNetworkInput() } }
    }
    public var networkPortAvailable: Bool {
        networkOutputs.contains { $0.id == selectedNetworkOutputID }
    }
    public var lastError: String?
    public var usbOutputs: [MIDIUSBOutput] = []
    public var selectedUSBOutput: MIDIEndpointRef = 0
    public var bridgeNetworkToUSB = false
    public private(set) var receivedNetworkMessages = 0
    public private(set) var forwardedMessages = 0
    public private(set) var lastReceivedMIDI = "No network MIDI received"
    public private(set) var lastSentMIDI = "No MIDI sent"
    private var inputPort: MIDIPortRef = 0
    private var connectedNetworkSource: MIDIEndpointRef = 0
    private var networkInputGeneration: UInt = 0

    private var midiClient: MIDIClientRef = 0
    private var outputPort: MIDIPortRef = 0

    private let browserQueue = DispatchQueue(label: "local.livecue.app.MIDIBrowser")
    private var browser: NWBrowser?
    private var resolving: [String: NWConnection] = [:]
    public private(set) var sentMessageCount = 0

    public init() {
        setupCoreMIDI()
        setupNetworkReceiver()
        refreshMIDIPorts()
        startBonjourDiscovery()
    }

    private func setupCoreMIDI() {
        var status = MIDIClientCreateWithBlock("LiveCue MIDI Client" as CFString, &midiClient) { @Sendable [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshMIDIPorts() }
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
        }
    }

    public func addManualDestination(name: String, address: String, port: UInt16) {
        let id = "\(address):\(port)"
        if !destinations.contains(where: { $0.id == id }) {
            destinations.append(MIDIDestination(id: id, name: name, address: address,
                                               port: port, isConnected: false, isManual: true))
        }
    }

    /// Refresh real driver endpoints; Audio MIDI Setup owns their peer connections.
    public func refreshMIDIPorts() {
        refreshUSBOutputs()
        networkOutputs = (0..<MIDIGetNumberOfDestinations()).compactMap {
            Self.networkEndpoint(MIDIGetDestination($0))
        }
        networkInputs = (0..<MIDIGetNumberOfSources()).compactMap {
            Self.networkEndpoint(MIDIGetSource($0))
        }
        selectedNetworkOutputID = MIDINetworkEndpoint.selectedID(current: selectedNetworkOutputID, available: networkOutputs)
        selectedNetworkInputID = MIDINetworkEndpoint.selectedID(current: selectedNetworkInputID, available: networkInputs)
        connectNetworkInput()
    }

    private static func stringProperty(_ object: MIDIObjectRef, _ property: CFString) -> String? {
        var value: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(object, property, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private static func networkEndpoint(_ endpoint: MIDIEndpointRef) -> MIDINetworkEndpoint? {
        var offline: Int32 = 0
        MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyOffline, &offline)
        guard offline == 0, let name = stringProperty(endpoint, kMIDIPropertyDisplayName) else { return nil }
        let owner = stringProperty(endpoint, kMIDIPropertyDriverOwner)?.lowercased() ?? ""
        // Driver ownership survives user-renamed sessions. Older drivers may only
        // expose the standard Network display-name prefix.
        guard owner.contains("midirtp") || owner.contains("networkmidi") ||
                name.hasPrefix("Network ") else { return nil }
        var uniqueID: MIDIUniqueID = 0
        guard MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uniqueID) == noErr,
              uniqueID != 0 else { return nil }
        return MIDINetworkEndpoint(id: uniqueID, endpoint: endpoint, name: name)
    }

    private func connectNetworkInput() {
        guard inputPort != 0 else { return }
        let source = networkInputs.first { $0.id == selectedNetworkInputID }?.endpoint ?? 0
        guard source != connectedNetworkSource else { return }
        networkInputGeneration &+= 1
        if connectedNetworkSource != 0 {
            MIDIPortDisconnectSource(inputPort, connectedNetworkSource)
            connectedNetworkSource = 0
        }
        guard source != 0 else {
            if selectedNetworkInputID != nil {
                lastError = "Selected network MIDI input is unavailable. Enable its session in Audio MIDI Setup or select another input."
            }
            return
        }
        let status = MIDIPortConnectSource(inputPort, source, UnsafeMutableRawPointer(bitPattern: networkInputGeneration))
        if status == noErr {
            connectedNetworkSource = source
        } else {
            lastError = "Cannot monitor selected network MIDI input: \(status)"
        }
    }

    // MARK: - Sending MIDI

    public func refreshUSBOutputs() {
        usbOutputs = (0..<MIDIGetNumberOfDestinations()).compactMap { index in
            let endpoint = MIDIGetDestination(index)
            var name: Unmanaged<CFString>?
            guard MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &name) == noErr, let name else { return nil }
            let label = name.takeRetainedValue() as String
            guard label.localizedCaseInsensitiveContains("WING") else { return nil }
            return MIDIUSBOutput(id: endpoint, name: label)
        }
        if selectedUSBOutput != 0 && !usbOutputs.contains(where: { $0.id == selectedUSBOutput }) {
            // Keep the missing USB selection so a later cue cannot unexpectedly
            // fall back to a network destination.
            bridgeNetworkToUSB = false
            lastError = "Selected WING USB output disconnected. Select it again."
        }
    }

    private func setupNetworkReceiver() {
        let status = MIDIInputPortCreateWithBlock(midiClient, "LiveCue Network Monitor" as CFString, &inputPort) { @Sendable [weak self] list, context in
            let packets = MIDIWire.packets(list)
            let generation = UInt(bitPattern: context)
            Task { @MainActor [weak self] in
                guard let self, self.networkInputGeneration == generation else { return }
                for bytes in packets {
                    self.receivedNetworkMessages += 1
                    self.lastReceivedMIDI = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
                    if self.bridgeNetworkToUSB && self.selectedUSBOutput != 0 {
                        if self.sendBytes(bytes, destination: self.selectedUSBOutput) { self.forwardedMessages += 1 }
                    }
                }
            }
        }
        guard status == noErr else { lastError = "Cannot create MIDI receiver: \(status)"; return }
    }

    @discardableResult
    private func sendBytes(_ bytes: [UInt8], destination: MIDIEndpointRef) -> Bool {
        let status = MIDIWire.send(bytes, port: outputPort, destination: destination)
        guard status == noErr else { lastError = "MIDI send failed: \(status)"; return false }
        sentMessageCount += 1
        lastSentMIDI = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        lastError = nil
        return true
    }

    private func sendMessage(_ bytes: [UInt8]) {
        if selectedUSBOutput != 0 {
            guard usbOutputs.contains(where: { $0.id == selectedUSBOutput }) else {
                lastError = "Selected WING USB output is unavailable"; return
            }
            sendBytes(bytes, destination: selectedUSBOutput)
        } else {
            // The network driver exposes normal CoreMIDI destinations on macOS.
            // A destination can exist before peers connect, so send acceptance is
            // deliberately not presented as proof that the receiving Mac got it.
            refreshMIDIPorts()
            guard let id = selectedNetworkOutputID else {
                lastError = networkOutputs.isEmpty
                    ? "No network MIDI output. Enable a session in Audio MIDI Setup and connect the audio Mac."
                    : "Choose a network MIDI output before sending."
                return
            }
            guard let output = networkOutputs.first(where: { $0.id == id }) else {
                lastError = "Selected network MIDI output is unavailable. Enable its session in Audio MIDI Setup or select another output."
                return
            }
            sendBytes(bytes, destination: output.endpoint)
        }
    }

    public func sendNoteOn(channel: UInt8, note: UInt8, velocity: UInt8) {
        sendMessage([0x90 | (channel & 0x0F), note & 0x7F, velocity & 0x7F])
    }
    public func sendNoteOff(channel: UInt8, note: UInt8, velocity: UInt8) {
        sendMessage([0x80 | (channel & 0x0F), note & 0x7F, velocity & 0x7F])
    }
    public func sendControlChange(channel: UInt8, controller: UInt8, value: UInt8) {
        sendMessage([0xB0 | (channel & 0x0F), controller & 0x7F, value & 0x7F])
    }
    public func sendProgramChange(channel: UInt8, program: UInt8) {
        sendMessage([0xC0 | (channel & 0x0F), program & 0x7F])
    }

    public func setWINGLamp(on: Bool) {
        lampFlashTask?.cancel()
        lampFlashTask = nil
        sendControlChange(channel: 5, controller: 16, value: on ? 127 : 0)
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
        sendMessage(bytes)
    }
}
