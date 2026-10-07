import AppKit
import AVFoundation
import CoreAudio
import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

@Observable
@MainActor
final class Model {
    var devices: [InputDevice] = []
    var deviceID: AudioDeviceID = 0
    var channel = 0          // fallback single channel; counts from 0, shown from 1
    var running = false
    var busy = false         // starting or stopping
    var status = "Stopped"
    var level: Float = 0
    var lines: [Line] = []

    // Multi-channel runtime state (enforced max 6 channels)
    var channels: [ChannelConfig] = []
    var channelStates: [ChannelState] = []

    // MIDI & Keyword Triggering
    var midiEngine = MIDIEngine()
    var keywordMatcher = KeywordMatcher()
    var triggerLogs: [TriggerLogItem] = []
    var lastTriggerBanner: String? = nil
    var flashTrigger = false

    // Document & Session State (Save / Save As / Open / Recent)
    var currentDocumentURL: URL? = nil
    var hasUnsavedChanges: Bool = false
    var recentDocumentURLs: [URL] = []
    var sessionCreatedAt: Date = Date()

    @ObservationIgnored
    private let capture = AudioCapture()
    @ObservationIgnored
    private var activeTranscribers: [UUID: Transcriber] = [:]
    @ObservationIgnored
    private let configManager = ConfigManager.shared
    @ObservationIgnored
    private var deviceMonitor: AudioDeviceMonitor?
    @ObservationIgnored
    private var meterTimer: Timer?
    @ObservationIgnored
    private var wasRunningBeforeDisconnect = false
    @ObservationIgnored
    private var disconnectedDeviceName: String?

    var device: InputDevice? { devices.first { $0.id == deviceID } }
    var maxChannelsLimit: Int { AppConfig.maxChannelsLimit }

    var documentTitle: String {
        let name = currentDocumentURL?.deletingPathExtension().lastPathComponent ?? "Untitled Session"
        let dirty = hasUnsavedChanges ? " •" : ""
        return "\(name)\(dirty) — LiveCue"
    }

    var documentDisplayName: String {
        currentDocumentURL?.deletingPathExtension().lastPathComponent ?? "Untitled Session"
    }

    var isMicrophoneDenied: Bool = false

    init() {
        refreshDevices()
        loadConfig()
        loadRecentDocuments()
        checkMicrophoneAuthorization()
        setupDeviceMonitoring()
        setupCaptureRecovery()
    }

    func checkMicrophoneAuthorization() {
        let authStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        isMicrophoneDenied = (authStatus == .denied || authStatus == .restricted)
    }

    func openMicrophonePrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Device Monitoring & Fault Tolerance

    private func setupDeviceMonitoring() {
        let monitor = AudioDeviceMonitor { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleDeviceChange()
            }
        }
        self.deviceMonitor = monitor
        monitor.start()
    }

    private func setupCaptureRecovery() {
        capture.onConfigurationChange = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self, self.running else { return }
                self.status = "Audio hardware clock/format changed. Recovering capture pipeline…"
                do {
                    try self.capture.restart()
                    let activeCount = self.channels.filter { $0.isEnabled }.count
                    self.status = "Listening to \(activeCount) channel(s) on \(self.device?.name ?? "interface")"
                } catch {
                    self.status = "Failed to recover audio capture: \(error.localizedDescription)"
                }
            }
        }
    }

    private func handleDeviceChange() {
        let previousID = deviceID
        let previousDevice = devices.first { $0.id == previousID }
        refreshDevices()

        let deviceStillPresent = devices.contains { $0.id == previousID }

        if !deviceStillPresent {
            // Selected audio device was unplugged or taken offline (e.g. Dante stopped)
            if running {
                wasRunningBeforeDisconnect = true
                disconnectedDeviceName = previousDevice?.name ?? "Audio Device"
                status = "Audio interface '\(disconnectedDeviceName!)' disconnected. Waiting for reconnect…"
                capture.stop()
                stopMeterTimer()
                running = false
            }
        } else if wasRunningBeforeDisconnect {
            // Previously disconnected device has re-appeared!
            if let discName = disconnectedDeviceName,
               let reconnected = devices.first(where: { $0.name == discName || $0.id == previousID }) {
                deviceID = reconnected.id
                wasRunningBeforeDisconnect = false
                disconnectedDeviceName = nil
                status = "Interface '\(reconnected.name)' reconnected. Resuming capture…"
                Task {
                    await start()
                }
            }
        }
    }

    // MARK: - Configuration

    func loadConfig() {
        let config = configManager.load()
        keywordMatcher.rules = config.rules
        // Enforce max 6 channels limit
        channels = Array(config.channels.prefix(AppConfig.maxChannelsLimit))
        syncChannelStates()

        // Configure manual destinations in MIDIEngine
        for dest in config.manualMIDIDestinations {
            midiEngine.addManualDestination(name: dest.name, address: dest.address, port: dest.port)
        }
        if !config.selectedMIDIDestinationIDs.isEmpty {
            midiEngine.selectedDestinationIDs = Set(config.selectedMIDIDestinationIDs)
        }
        validateChannelsForCurrentDevice()
    }

    func syncChannelStates() {
        var newStates: [ChannelState] = []
        for ch in channels {
            let existing = channelStates.first(where: { $0.id == ch.id })
            newStates.append(ChannelState(
                id: ch.id,
                name: ch.name,
                colorHex: ch.colorHex,
                channelIndex: ch.channelIndex,
                isEnabled: ch.isEnabled,
                level: existing?.level ?? 0,
                partial: existing?.partial ?? "",
                partialTime: existing?.partialTime ?? Date()
            ))
        }
        channelStates = newStates
    }

    func saveConfig() {
        var manualDests: [ManualMIDIDestinationConfig] = []
        for d in midiEngine.destinations where d.isManual {
            manualDests.append(ManualMIDIDestinationConfig(name: d.name, address: d.address, port: d.port))
        }

        let config = AppConfig(
            rules: keywordMatcher.rules,
            manualMIDIDestinations: manualDests,
            selectedMIDIDestinationIDs: Array(midiEngine.selectedDestinationIDs),
            channels: Array(channels.prefix(AppConfig.maxChannelsLimit))
        )
        configManager.save(config)
    }

    func refreshDevices() {
        devices = AudioDevices.inputs()
        if device == nil {
            let preferred = AudioDevices.defaultInput()
            deviceID = devices.first { $0.id == preferred }?.id ?? devices.first?.id ?? 0
        }
        channel = min(channel, max(0, (device?.channels ?? 1) - 1))
        validateChannelsForCurrentDevice()
    }

    func validateChannelsForCurrentDevice() {
        guard let dev = device else { return }
        let maxIn = max(1, dev.inputChannels)
        var changed = false
        for i in 0..<channels.count {
            if channels[i].channelIndex >= maxIn {
                channels[i].channelIndex = maxIn - 1
                changed = true
            }
        }
        if changed {
            syncChannelStates()
            saveConfig()
        }
    }

    // MARK: - Metering Timer

    private func startMeterTimer() {
        stopMeterTimer()
        let timer = Timer(timeInterval: 0.033, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollLevels()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        meterTimer = timer
    }

    private func stopMeterTimer() {
        meterTimer?.invalidate()
        meterTimer = nil
        level = 0
        for i in 0..<channelStates.count {
            channelStates[i].level = 0
        }
    }

    private func pollLevels() {
        guard running else { return }
        let overall = capture.overallPeak()
        level = max(overall, level * 0.82)

        for i in 0..<channelStates.count {
            let chID = channelStates[i].id
            let peak = capture.peak(for: chID)
            channelStates[i].level = max(peak, channelStates[i].level * 0.82)
        }
    }

    // MARK: - Controls

    func toggle() {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            if running { await stop() } else { await start() }
        }
    }

    func clear() {
        lines.removeAll()
        for i in 0..<channelStates.count {
            channelStates[i].partial = ""
        }
        triggerLogs.removeAll()
        lastTriggerBanner = nil
        hasUnsavedChanges = true
    }

    private func start() async {
        guard let device else {
            status = "No input device selected"
            return
        }

        let authStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if authStatus == .notDetermined {
            status = "Requesting microphone permission…"
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            isMicrophoneDenied = !granted
            if !granted {
                status = "Microphone access denied. Open System Settings › Privacy & Security › Microphone."
                return
            }
        } else if authStatus == .denied || authStatus == .restricted {
            isMicrophoneDenied = true
            status = "Microphone access denied. Open System Settings › Privacy & Security › Microphone."
            return
        }
        isMicrophoneDenied = false
        status = "Initializing speech engines…"

        // Filter enabled channels and enforce maximum of 6 channels limit
        var targetConfigs = Array(channels.filter { $0.isEnabled }.prefix(AppConfig.maxChannelsLimit))
        if targetConfigs.isEmpty {
            let fallback = ChannelConfig(id: UUID(), name: "Input \(channel + 1)", colorHex: "#00E575", channelIndex: channel, isEnabled: true)
            channels = [fallback]
            syncChannelStates()
            targetConfigs = [fallback]
        }

        do {
            var targets: [ChannelTarget] = []
            var transcribers: [UUID: Transcriber] = [:]

            for config in targetConfigs {
                let transcriber = try await Transcriber.make { [weak self] text in
                    self?.status = "[\(config.name)]: \(text)"
                }

                try await transcriber.start(
                    onResult: { [weak self] text, final in
                        self?.channelHeard(config: config, text: text, final: final)
                    },
                    onError: { [weak self] error in
                        self?.status = "\(config.name) error: \(error.localizedDescription)"
                    })

                transcribers[config.id] = transcriber

                let target = ChannelTarget(
                    id: config.id,
                    channel: config.channelIndex,
                    target: transcriber.format,
                    sink: transcriber.audioSink
                )
                targets.append(target)
            }

            self.activeTranscribers = transcribers
            try capture.startMulti(device: device.id, targets: targets)
            running = true
            status = "Listening to \(targetConfigs.count) channel(s) on \(device.name)"
            startMeterTimer()
        } catch {
            capture.stop()
            stopMeterTimer()
            let toFinish = Array(activeTranscribers.values)
            activeTranscribers.removeAll()
            for t in toFinish {
                await t.finish()
            }
            running = false
            status = "Audio Error: \(error.localizedDescription)"
        }
    }

    func selectDevice(_ id: AudioDeviceID) {
        guard deviceID != id else { return }
        deviceID = id
        refreshDevices()
        if running {
            Task {
                await stop()
                await start()
            }
        }
    }

    private func stop() async {
        capture.stop()
        stopMeterTimer()
        for i in 0..<channelStates.count {
            channelStates[i].partial = ""
        }
        status = "Stopping…"
        let toFinish = Array(activeTranscribers.values)
        activeTranscribers.removeAll()
        for transcriber in toFinish {
            await transcriber.finish()
        }
        running = false
        status = "Stopped"
    }

    private func channelHeard(config: ChannelConfig, text: String, final: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if final {
            if !trimmed.isEmpty {
                let partialTime = channelStates.first(where: { $0.id == config.id })?.partialTime ?? Date()
                lines.append(Line(
                    time: partialTime,
                    text: trimmed,
                    channelID: config.id,
                    channelName: config.name,
                    channelColorHex: config.colorHex
                ))
                hasUnsavedChanges = true

                // Check keyword rules against this channel's recognized text
                let matchedRules = keywordMatcher.match(text: trimmed, channelID: config.id, isFinal: true)
                for rule in matchedRules {
                    executeTrigger(rule: rule, channelName: config.name, channelIndex: config.channelIndex)
                }
            }
            if let idx = channelStates.firstIndex(where: { $0.id == config.id }) {
                channelStates[idx].partial = ""
            }
        } else {
            if let idx = channelStates.firstIndex(where: { $0.id == config.id }) {
                if channelStates[idx].partial.isEmpty {
                    channelStates[idx].partialTime = Date()
                }
                channelStates[idx].partial = trimmed
            }
        }
    }

    // MARK: - Keyword Rule & Trigger Execution

    public func executeTrigger(rule: KeywordRule, channelName: String? = nil, channelIndex: Int? = nil) {
        var actionDesc = ""

        // Dynamic MIDI channel routing: if followAudioChannel is true, route to MIDI channel matching audio input
        let resolveChannel: (UInt8) -> UInt8 = { defaultCh in
            if rule.followAudioChannel, let idx = channelIndex {
                return UInt8(idx % 16)
            }
            return defaultCh
        }

        switch rule.action {
        case .midiNoteOn(let ch, let note, let vel):
            let targetCh = resolveChannel(ch)
            midiEngine.sendNoteOn(channel: targetCh, note: note, velocity: vel)
            actionDesc = "MIDI Note On (Ch:\(targetCh + 1) Note:\(note) Vel:\(vel))"

        case .midiNoteOff(let ch, let note, let vel):
            let targetCh = resolveChannel(ch)
            midiEngine.sendNoteOff(channel: targetCh, note: note, velocity: vel)
            actionDesc = "MIDI Note Off (Ch:\(targetCh + 1) Note:\(note) Vel:\(vel))"

        case .midiCC(let ch, let ctrl, let val):
            let targetCh = resolveChannel(ch)
            midiEngine.sendControlChange(channel: targetCh, controller: ctrl, value: val)
            actionDesc = "MIDI CC (Ch:\(targetCh + 1) CC:\(ctrl) Val:\(val))"

        case .midiProgramChange(let ch, let prog):
            let targetCh = resolveChannel(ch)
            midiEngine.sendProgramChange(channel: targetCh, program: prog)
            actionDesc = "MIDI Program Change (Ch:\(targetCh + 1) Prog:\(prog))"

        case .midiMSC(let devID, let cmdFormat, let cmd, let cueNum, let cueList):
            midiEngine.sendMSC(deviceID: devID, commandFormat: cmdFormat, command: cmd, cueNumber: cueNum, cueList: cueList)
            actionDesc = "MIDI Show Control (Dev:\(devID) Cue:\(cueNum ?? "-"))"

        case .flashWindow:
            actionDesc = "Visual Alert"
            triggerFlashAlert()
        }

        let item = TriggerLogItem(
            ruleKeyword: rule.keyword,
            description: actionDesc,
            channelName: channelName
        )
        triggerLogs.insert(item, at: 0)
        hasUnsavedChanges = true
        if triggerLogs.count > 100 {
            triggerLogs.removeLast()
        }

        let chLabel = channelName.map { "[\($0)] " } ?? ""
        lastTriggerBanner = "\(chLabel)Fired rule '\(rule.keyword)': \(actionDesc)"
    }

    public func testRule(_ rule: KeywordRule) {
        executeTrigger(rule: rule, channelName: "Manual Test", channelIndex: 0)
    }

    private func triggerFlashAlert() {
        flashTrigger = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            self.flashTrigger = false
        }
    }

    // MARK: - Document Operations (Save / Save As / Open / Recent)

    private func loadRecentDocuments() {
        if let paths = UserDefaults.standard.stringArray(forKey: "LiveCueRecentDocumentPaths") {
            recentDocumentURLs = paths.compactMap { path in
                let url = URL(fileURLWithPath: path)
                return FileManager.default.fileExists(atPath: url.path) ? url : nil
            }
        }
    }

    private func addRecentDocument(_ url: URL) {
        var existing = recentDocumentURLs.filter { $0.path != url.path }
        existing.insert(url, at: 0)
        if existing.count > 10 {
            existing = Array(existing.prefix(10))
        }
        recentDocumentURLs = existing
        let paths = existing.map { $0.path }
        UserDefaults.standard.set(paths, forKey: "LiveCueRecentDocumentPaths")
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }

    public func clearRecentDocuments() {
        recentDocumentURLs.removeAll()
        UserDefaults.standard.removeObject(forKey: "LiveCueRecentDocumentPaths")
    }

    public func newSession() {
        lines.removeAll()
        for i in 0..<channelStates.count {
            channelStates[i].partial = ""
        }
        triggerLogs.removeAll()
        lastTriggerBanner = nil
        currentDocumentURL = nil
        sessionCreatedAt = Date()
        hasUnsavedChanges = false
        status = "New session started"
    }

    public func save() {
        if let url = currentDocumentURL {
            saveToURL(url)
        } else {
            saveAs()
        }
    }

    public func saveAs() {
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        let liveCueType = UTType(filenameExtension: "livecue") ?? .json
        savePanel.allowedContentTypes = [liveCueType, .json]

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        let timestamp = formatter.string(from: Date())
        let defaultName = currentDocumentURL?.lastPathComponent ?? "LiveCue_Session_\(timestamp).livecue"
        savePanel.nameFieldStringValue = defaultName

        if savePanel.runModal() == .OK, let url = savePanel.url {
            saveToURL(url)
        }
    }

    private func saveToURL(_ url: URL) {
        let session = LiveCueSession(
            version: "1.0",
            title: url.deletingPathExtension().lastPathComponent,
            createdAt: sessionCreatedAt,
            modifiedAt: Date(),
            lines: lines,
            channels: channels,
            rules: keywordMatcher.rules,
            triggerLogs: triggerLogs,
            deviceName: device?.name
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        do {
            let data = try encoder.encode(session)
            try data.write(to: url, options: .atomic)
            currentDocumentURL = url
            addRecentDocument(url)
            hasUnsavedChanges = false
            status = "Saved session to \(url.lastPathComponent)"
        } catch {
            status = "Failed to save session: \(error.localizedDescription)"
        }
    }

    public func openFile() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        let liveCueType = UTType(filenameExtension: "livecue") ?? .json
        openPanel.allowedContentTypes = [liveCueType, .json]

        if openPanel.runModal() == .OK, let url = openPanel.url {
            openURL(url)
        }
    }

    public func openURL(_ url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let session = try decoder.decode(LiveCueSession.self, from: data)

            lines = session.lines
            if !session.channels.isEmpty {
                channels = Array(session.channels.prefix(AppConfig.maxChannelsLimit))
                syncChannelStates()
            }
            if !session.rules.isEmpty {
                keywordMatcher.rules = session.rules
            }
            triggerLogs = session.triggerLogs
            sessionCreatedAt = session.createdAt
            currentDocumentURL = url
            addRecentDocument(url)
            hasUnsavedChanges = false
            status = "Opened session '\(url.deletingPathExtension().lastPathComponent)' (\(session.lines.count) transcript lines)"
        } catch {
            status = "Failed to open session: \(error.localizedDescription)"
        }
    }

    // MARK: - Export

    public func exportTranscript(format: ExportFormat) -> String {
        return TranscriptExporter.export(lines: lines, format: format, defaultChannel: "Comms")
    }
}
