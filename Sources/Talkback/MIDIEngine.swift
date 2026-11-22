import Foundation
import CoreMIDI
import Network
import Observation
import SystemConfiguration

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

/// How the WING lamp flashes: on time, off time, number of flashes, brightness.
/// Every pattern ends with the lamp OFF.
public struct LampFlashSettings: Codable, Equatable, Sendable {
    public var onSeconds: Double = 0.25
    public var offSeconds: Double = 0.25
    public var flashes: Int = 6
    public var brightness: Int = 127   // CC value sent for "on", 1-127

    public static let `default` = LampFlashSettings()

    public struct Preset: Identifiable, Sendable {
        public let name: String
        public let settings: LampFlashSettings
        public var id: String { name }
    }
    public static let presets: [Preset] = [
        Preset(name: "Quick blink", settings: LampFlashSettings(onSeconds: 0.25, offSeconds: 0.25, flashes: 6)),
        Preset(name: "Pulse", settings: LampFlashSettings(onSeconds: 0.5, offSeconds: 0.5, flashes: 4)),
        Preset(name: "Slow blink", settings: LampFlashSettings(onSeconds: 1.0, offSeconds: 0.5, flashes: 3)),
        Preset(name: "Long flash", settings: LampFlashSettings(onSeconds: 3.0, offSeconds: 0.5, flashes: 1)),
    ]

    public init(onSeconds: Double = 0.25, offSeconds: Double = 0.25, flashes: Int = 6, brightness: Int = 127) {
        self.onSeconds = onSeconds
        self.offSeconds = offSeconds
        self.flashes = flashes
        self.brightness = brightness
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LampFlashSettings.default
        onSeconds = try c.decodeIfPresent(Double.self, forKey: .onSeconds) ?? d.onSeconds
        offSeconds = try c.decodeIfPresent(Double.self, forKey: .offSeconds) ?? d.offSeconds
        flashes = try c.decodeIfPresent(Int.self, forKey: .flashes) ?? d.flashes
        brightness = try c.decodeIfPresent(Int.self, forKey: .brightness) ?? d.brightness
    }

    /// Values kept inside safe ranges (0.1-5 s, 1-20 flashes, 1-127).
    public var clamped: LampFlashSettings {
        LampFlashSettings(onSeconds: min(max(onSeconds, 0.1), 5),
                          offSeconds: min(max(offSeconds, 0.1), 5),
                          flashes: min(max(flashes, 1), 20),
                          brightness: min(max(brightness, 1), 127))
    }

    /// Seconds from the first ON to the final OFF.
    public var totalSeconds: Double {
        let s = clamped
        return Double(s.flashes) * s.onSeconds + Double(s.flashes - 1) * s.offSeconds
    }

    /// (time in seconds, lamp on?) for every message. Starts ON, ends OFF.
    public var schedule: [(time: Double, on: Bool)] {
        let s = clamped
        var steps: [(time: Double, on: Bool)] = []
        for i in 0..<s.flashes {
            let start = Double(i) * (s.onSeconds + s.offSeconds)
            steps.append((start, true))
            steps.append((start + s.onSeconds, false))
        }
        return steps
    }

    /// The preset this matches, if any.
    public var presetName: String? {
        Self.presets.first { $0.settings.onSeconds == onSeconds && $0.settings.offSeconds == offSeconds
            && $0.settings.flashes == flashes }?.name
    }

    /// e.g. "6 flashes, 0.25 s on / 0.25 s off, 2.8 s in all"
    public var summary: String {
        let s = clamped
        let flashesText = s.flashes == 1 ? "1 flash, \(Self.fmt(s.onSeconds)) on" :
            "\(s.flashes) flashes, \(Self.fmt(s.onSeconds)) on / \(Self.fmt(s.offSeconds)) off"
        return "\(flashesText), \(Self.fmt(totalSeconds)) in all"
    }

    /// 0.25 → "0.25 s", 0.5 → "0.5 s", 3 → "3 s"
    static func fmt(_ seconds: Double) -> String {
        var text = String(format: "%.2f", seconds)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text + " s"
    }
}

/// The WING Lamp Bridge's answer to a connection-test ping (bridge v1.1+).
public struct BridgeReply: Equatable, Sendable {
    public let wingFound: Bool
    public let version: String
    public let roundTripMs: Int
    public let at: Date
}

/// Connection-test SysEx shared with tools/WINGLampBridge (0x7D non-commercial, "LC").
enum BridgePing {
    static func ping(nonce: UInt8) -> [UInt8] { [0xF0, 0x7D, 0x4C, 0x43, 0x01, nonce & 0x7F, 0xF7] }
    /// Returns (nonce, wingFound, major, minor) for a reply packet.
    static func parseReply(_ bytes: [UInt8]) -> (nonce: UInt8, wing: Bool, major: UInt8, minor: UInt8)? {
        guard let start = bytes.firstIndex(of: 0xF0), bytes.count - start >= 10 else { return nil }
        let b = Array(bytes[start..<(start + 10)])
        guard b[1] == 0x7D, b[2] == 0x4C, b[3] == 0x43, b[4] == 0x02, b[9] == 0xF7 else { return nil }
        return (b[5], b[6] != 0, b[7], b[8])
    }
    static func isLiveCueSysEx(_ bytes: [UInt8]) -> Bool {
        bytes.count >= 4 && bytes[0] == 0xF0 && bytes[1] == 0x7D && bytes[2] == 0x4C && bytes[3] == 0x43
    }
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
    public var selectedNetworkOutputID: MIDIUniqueID? {
        didSet {
            guard oldValue != selectedNetworkOutputID else { return }
            if let id = selectedNetworkOutputID { UserDefaults.standard.set(Int(id), forKey: Self.savedOutputKey) }
            matchInputToOutput()
        }
    }
    private static let savedOutputKey = "LiveCueNetworkOutputUniqueID"
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

    // Bridge health (WING Lamp Bridge v1.1+ answers pings over the network session).
    public private(set) var lastBridgeReply: BridgeReply?
    public private(set) var bridgePingsSent = 0
    public private(set) var lastLampCommand: (value: UInt8, at: Date)?
    /// True when the bridge answered within the last 25 seconds.
    public var bridgeOnline: Bool {
        guard let reply = lastBridgeReply else { return false }
        return Date().timeIntervalSince(reply.at) < 25
    }
    private var pendingPings: [UInt8: (sent: ContinuousClock.Instant, done: CheckedContinuation<BridgeReply?, Never>)] = [:]
    private var nextNonce: UInt8 = 0
    private var heartbeat: Task<Void, Never>?

    /// Background bridge check every 10 s (first one after 3 s). Tests turn it off.
    public var heartbeatEnabled = true

    public init() {
        setupCoreMIDI()
        setupNetworkReceiver()
        // Reuse last launch's session only if it still exists; otherwise the normal
        // rules apply (auto-pick a single session, never switch silently).
        if let saved = UserDefaults.standard.object(forKey: Self.savedOutputKey) as? Int {
            let id = MIDIUniqueID(saved)
            let available = (0..<MIDIGetNumberOfDestinations()).compactMap { Self.networkEndpoint(MIDIGetDestination($0)) }
            if available.contains(where: { $0.id == id }) { selectedNetworkOutputID = id }
        }
        refreshMIDIPorts()
        startBonjourDiscovery()
        startHeartbeat()
    }

    /// This Mac's own Bonjour name, so it can be told apart from the audio Mac.
    public static let thisMacName: String = (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? ""

    /// Every network MIDI session name advertised on the local network (Bonjour).
    public private(set) var advertisedHostNames: [String] = []

    /// Network MIDI sessions advertised by Macs other than this one.
    public var otherHostNames: [String] {
        advertisedHostNames.filter { $0 != Self.thisMacName }
    }

    private func startHeartbeat() {
        heartbeat = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            while !Task.isCancelled {
                if let self, self.heartbeatEnabled, self.networkPortAvailable, self.selectedNetworkInput != nil {
                    _ = await self.pingBridge()
                }
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    private var selectedNetworkInput: MIDINetworkEndpoint? {
        networkInputs.first { $0.id == selectedNetworkInputID }
    }

    /// Network input and output of one session share a name; keep them paired so
    /// replies from the audio Mac are heard on the session we send to.
    private func matchInputToOutput() {
        guard let output = networkOutputs.first(where: { $0.id == selectedNetworkOutputID }),
              let input = networkInputs.first(where: { $0.name == output.name }),
              input.id != selectedNetworkInputID else { return }
        selectedNetworkInputID = input.id
    }

    /// Sends a connection-test ping to the audio Mac's bridge and waits for its answer.
    /// Returns nil if nothing answered (no bridge, old bridge, or no connection).
    public func pingBridge(timeout: Duration = .seconds(2)) async -> BridgeReply? {
        refreshMIDIPorts()
        guard let output = networkOutputs.first(where: { $0.id == selectedNetworkOutputID }) else { return nil }
        nextNonce = (nextNonce &+ 1) & 0x7F
        let nonce = nextNonce
        let sent = ContinuousClock.now
        guard MIDIWire.send(BridgePing.ping(nonce: nonce), port: outputPort, destination: output.endpoint) == noErr else { return nil }
        bridgePingsSent += 1
        return await withCheckedContinuation { continuation in
            pendingPings[nonce] = (sent, continuation)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: timeout)
                self?.pendingPings.removeValue(forKey: nonce)?.done.resume(returning: nil)
            }
        }
    }

    private func handleBridgeReply(_ bytes: [UInt8]) -> Bool {
        guard let reply = BridgePing.parseReply(bytes) else { return false }
        guard let pending = pendingPings.removeValue(forKey: reply.nonce) else { return true }
        let elapsed = ContinuousClock.now - pending.sent
        let ms = Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
        let result = BridgeReply(wingFound: reply.wing, version: "\(reply.major).\(reply.minor)", roundTripMs: ms, at: Date())
        lastBridgeReply = result
        pending.done.resume(returning: result)
        return true
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
            let names = results.compactMap { result -> String? in
                if case let .service(name, _, _, _) = result.endpoint { return name }
                return nil
            }
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.advertisedHostNames = Array(Set(names)).sorted()
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
        matchInputToOutput()
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
                    if self.handleBridgeReply(bytes) { continue }
                    self.receivedNetworkMessages += 1
                    self.lastReceivedMIDI = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
                    // Connection-test pings are answered by the bridge, never sent to the console.
                    if BridgePing.isLiveCueSysEx(bytes) { continue }
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

    /// Sends to the selected USB or network output. Returns false (and sets
    /// `lastError`) when nothing was sent.
    @discardableResult
    private func sendMessage(_ bytes: [UInt8]) -> Bool {
        if selectedUSBOutput != 0 {
            guard usbOutputs.contains(where: { $0.id == selectedUSBOutput }) else {
                lastError = "Selected WING USB output is unavailable"; return false
            }
            return sendBytes(bytes, destination: selectedUSBOutput)
        } else {
            // The network driver exposes normal CoreMIDI destinations on macOS.
            // A destination can exist before peers connect, so send acceptance is
            // deliberately not presented as proof that the receiving Mac got it.
            refreshMIDIPorts()
            guard let id = selectedNetworkOutputID else {
                lastError = networkOutputs.isEmpty
                    ? "No network MIDI output. Enable a session in Audio MIDI Setup and connect the audio Mac."
                    : "Choose a network MIDI output before sending."
                return false
            }
            guard let output = networkOutputs.first(where: { $0.id == id }) else {
                lastError = "Selected network MIDI output is unavailable. Enable its session in Audio MIDI Setup or select another output."
                return false
            }
            return sendBytes(bytes, destination: output.endpoint)
        }
    }

    @discardableResult
    public func sendNoteOn(channel: UInt8, note: UInt8, velocity: UInt8) -> Bool {
        sendMessage([0x90 | (channel & 0x0F), note & 0x7F, velocity & 0x7F])
    }
    @discardableResult
    public func sendNoteOff(channel: UInt8, note: UInt8, velocity: UInt8) -> Bool {
        sendMessage([0x80 | (channel & 0x0F), note & 0x7F, velocity & 0x7F])
    }
    @discardableResult
    public func sendControlChange(channel: UInt8, controller: UInt8, value: UInt8) -> Bool {
        let ok = sendMessage([0xB0 | (channel & 0x0F), controller & 0x7F, value & 0x7F])
        if ok, channel == 5, controller == 16 { lastLampCommand = (value, Date()) }
        return ok
    }
    @discardableResult
    public func sendProgramChange(channel: UInt8, program: UInt8) -> Bool {
        sendMessage([0xC0 | (channel & 0x0F), program & 0x7F])
    }

    @discardableResult
    public func setWINGLamp(on: Bool) -> Bool {
        lampFlashTask?.cancel()
        lampFlashTask = nil
        return sendControlChange(channel: 5, controller: 16, value: on ? 127 : 0)
    }

    // A single task owns the lamp so repeated cues cannot interleave on/off messages.
    private var lampFlashTask: Task<Void, Never>?

    /// The saved flash pattern used by rules, the FLASH button and Test Connection.
    public var lampFlash = LampFlashSettings.default

    /// True while a flash pattern is playing.
    public var isLampFlashing: Bool { lampFlashTask != nil }

    /// Plays a flash pattern (the saved one by default). Always ends OFF.
    /// Returns false if the first message couldn't be sent.
    @discardableResult
    public func flashWINGLamp(_ pattern: LampFlashSettings? = nil) -> Bool {
        let settings = (pattern ?? lampFlash).clamped
        let value = UInt8(settings.brightness)
        lampFlashTask?.cancel()
        guard sendControlChange(channel: 5, controller: 16, value: value) else { lampFlashTask = nil; return false }
        lampFlashTask = Task { @MainActor [weak self] in
            let clock = ContinuousClock()
            let start = clock.now
            do {
                // Absolute deadlines so long patterns don't drift.
                for step in settings.schedule.dropFirst() {
                    try await clock.sleep(until: start.advanced(by: .milliseconds(Int((step.time * 1000).rounded()))))
                    try Task.checkCancellation()
                    self?.sendControlChange(channel: 5, controller: 16, value: step.on ? value : 0)
                }
                self?.lampFlashTask = nil
            } catch {
                // A replacement flash (or LAMP OFF) owns the lamp after cancellation.
            }
        }
        return true
    }

    // MARK: - Sending MSC

    @discardableResult
    public func sendMSC(deviceID: UInt8, commandFormat: UInt8, command: UInt8, cueNumber: String? = nil, cueList: String? = nil) -> Bool {
        var sysex: [UInt8] = [
            0xF0, 0x7F,
            deviceID & 0x7F,
            0x02,
            commandFormat & 0x7F,
            command & 0x7F
        ]

        if command == 0x07 {
            // FIRE takes a single macro-number byte, not ASCII cue text.
            let macro = UInt8(clamping: Int(cueNumber?.trimmingCharacters(in: .whitespaces) ?? "") ?? 0)
            sysex.append(macro & 0x7F)
        } else if let cueNumber = cueNumber {
            sysex.append(contentsOf: cueNumber.utf8)

            if let cueList = cueList {
                sysex.append(0x00)
                sysex.append(contentsOf: cueList.utf8)
            }
        }

        sysex.append(0xF7)
        return sendMessage(sysex)
    }
}
