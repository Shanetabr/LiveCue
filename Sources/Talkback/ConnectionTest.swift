import AppKit
import CoreMIDI
import Foundation
import Observation

/// "Test Connection": walks the lamp path one hop at a time and explains each
/// result in plain words. Stage Mac → network → audio MacBook bridge → WING → lamp.
/// Only the person watching the lamp can confirm the last step.
@Observable
@MainActor
final class ConnectionTest {
    enum State: Equatable {
        case waiting, running, passed, warning, failed, skipped, needsAnswer
    }

    enum Fix: Equatable {
        case openAudioMIDISetup
        case getBridgeInstaller
    }

    struct Step: Identifiable, Equatable {
        let id: String
        let title: String
        var state: State = .waiting
        var detail = ""
        var fix: Fix?
    }

    private(set) var steps: [Step] = []
    private(set) var isRunning = false
    private(set) var finishedAt: Date?
    var installerMessage: String?

    private let midi: MIDIEngine

    init(midi: MIDIEngine) {
        self.midi = midi
        reset()
    }

    var usesUSB: Bool { midi.selectedUSBOutput != 0 }

    /// One plain sentence about the whole test.
    var summary: String {
        if isRunning { return "Testing…" }
        if steps.contains(where: { $0.state == .needsAnswer }) { return "Look at the WING lamp. Did it flash?" }
        guard finishedAt != nil else { return "Press Test Connection to check every step from this Mac to the WING lamp." }
        if let failed = steps.first(where: { $0.state == .failed }) { return "Problem found: \(failed.title.lowercased()). See below for what to do." }
        if steps.contains(where: { $0.state == .warning }) { return "It works, with a warning below." }
        return "Everything works. The lamp flashed."
    }

    func reset() {
        if usesUSB {
            steps = [
                Step(id: "usb", title: "WING plugged into this Mac"),
                Step(id: "lamp", title: "WING lamp flashes"),
            ]
        } else {
            steps = [
                Step(id: "session", title: "Network MIDI on this Mac"),
                Step(id: "audioMac", title: "Audio MacBook on the network"),
                Step(id: "bridge", title: "Lamp bridge on the audio MacBook"),
                Step(id: "wing", title: "WING plugged into the audio MacBook"),
                Step(id: "lamp", title: "WING lamp flashes"),
            ]
        }
        finishedAt = nil
    }

    private func set(_ id: String, _ state: State, _ detail: String, fix: Fix? = nil) {
        guard let i = steps.firstIndex(where: { $0.id == id }) else { return }
        steps[i].state = state
        steps[i].detail = detail
        steps[i].fix = fix
    }

    func run() {
        guard !isRunning else { return }
        reset()
        isRunning = true
        Task { await runSteps() }
    }

    private func runSteps() async {
        defer { isRunning = false }
        midi.refreshMIDIPorts()

        if usesUSB {
            guard midi.usbOutputs.contains(where: { $0.id == midi.selectedUSBOutput }) else {
                set("usb", .failed, "The WING USB port you picked isn't connected. Check the USB cable and that the WING is on, then pick WING Port 4 again in Network MIDI.")
                set("lamp", .skipped, "Skipped until the WING is connected.")
                finishedAt = Date()
                return
            }
            let name = midi.usbOutputs.first { $0.id == midi.selectedUSBOutput }?.name ?? "WING"
            set("usb", .passed, "Sending straight to \(name) over USB.")
            await flashAndAsk()
            return
        }

        // 1. This Mac's network session
        set("session", .running, "Checking…")
        guard let output = midi.networkOutputs.first(where: { $0.id == midi.selectedNetworkOutputID }) else {
            let detail = midi.networkOutputs.isEmpty
                ? "This Mac has no network MIDI session turned on. Open Audio MIDI Setup → Window → Show MIDI Studio → Network, turn on a session, and connect the audio MacBook to it."
                : "Pick the network session to send to in the Network MIDI tab."
            set("session", .failed, detail, fix: midi.networkOutputs.isEmpty ? .openAudioMIDISetup : nil)
            for id in ["audioMac", "bridge", "wing", "lamp"] { set(id, .skipped, "Skipped until network MIDI is set up.") }
            finishedAt = Date()
            return
        }
        set("session", .passed, "Sending on \(output.name).")

        // 2. Audio MacBook seen on the network (Bonjour). Informational only.
        let hosts = midi.otherHostNames
        if hosts.isEmpty {
            set("audioMac", .warning, "No other Mac is advertising network MIDI. Check the Ethernet cable, and that the audio MacBook is on and logged in. If it is, allow LiveCue in System Settings → Privacy & Security → Local Network.")
        } else {
            set("audioMac", .passed, "Seen on the network: \(hosts.joined(separator: ", ")).")
        }

        // 3 + 4. Ping the bridge (two tries).
        set("bridge", .running, "Asking the bridge to answer…")
        var reply = await midi.pingBridge()
        if reply == nil { reply = await midi.pingBridge() }
        if let reply {
            set("bridge", .passed, "WING Lamp Bridge \(reply.version) answered in \(reply.roundTripMs) ms.")
            if reply.wingFound {
                set("wing", .passed, "The bridge can see WING Port 4.")
            } else {
                set("wing", .failed, "The bridge is running but can't see WING Port 4. Check the USB cable from the audio MacBook to the WING, and that the WING is on.")
                set("lamp", .skipped, "Skipped: the WING isn't connected to the audio MacBook.")
                finishedAt = Date()
                return
            }
        } else {
            set("bridge", .failed, "No answer from the audio MacBook. Check that it's on and logged in, connected to this Mac in Audio MIDI Setup → Network, and running WING Lamp Bridge 1.1 or newer. Version 1.0 can still flash the lamp but can't answer this test, so the lamp is tried anyway.", fix: .getBridgeInstaller)
            set("wing", .skipped, "Unknown without an answer from the bridge.")
        }

        // 5. The lamp, confirmed by a person.
        await flashAndAsk()
    }

    private func flashAndAsk() async {
        let pattern = midi.lampFlash
        set("lamp", .running, "Flashing the lamp: \(pattern.summary)…")
        guard midi.flashWINGLamp() else {
            set("lamp", .failed, "Nothing could be sent: \(midi.lastError ?? "MIDI send failed").")
            finishedAt = Date()
            return
        }
        try? await Task.sleep(for: .seconds(pattern.totalSeconds + 0.3))
        set("lamp", .needsAnswer, "Flashed (\(pattern.summary)), then turned off. Did you see the WING lamp flash?")
        finishedAt = Date()
    }

    /// The person at the console answers whether the lamp flashed.
    func answerLamp(flashed: Bool) {
        if flashed {
            set("lamp", .passed, "You saw the lamp flash.")
        } else if usesUSB {
            set("lamp", .failed, "The message went out but the lamp didn't flash. On the WING, check Setup → MIDI → Custom Controls is set to USB, and Layer 2, encoder 1 is set to Lamp Brightness.")
        } else {
            let bridgeOK = steps.first { $0.id == "bridge" }?.state == .passed
            set("lamp", .failed, bridgeOK
                ? "The bridge got the message but the lamp didn't flash. On the WING, check Setup → MIDI → Custom Controls is set to USB, and Layer 2, encoder 1 is set to Lamp Brightness. On the audio MacBook, run Test Lamp Flash."
                : "The lamp didn't flash and the bridge didn't answer. Install WING Lamp Bridge 1.1 on the audio MacBook, then test again.",
                fix: bridgeOK ? nil : .getBridgeInstaller)
        }
    }

    func perform(_ fix: Fix) {
        switch fix {
        case .openAudioMIDISetup:
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Audio MIDI Setup.app"))
        case .getBridgeInstaller:
            installerMessage = Self.saveBridgeInstaller()
        }
    }

    /// Copies the bridge installer bundled inside LiveCue to Downloads and shows it in
    /// Finder, ready for AirDrop or a USB stick to the audio MacBook.
    static func saveBridgeInstaller() -> String {
        guard let source = Bundle.main.url(forResource: "WINGLampBridge", withExtension: "zip") else {
            return "This copy of LiveCue doesn't include the bridge installer. Build LiveCue with build.sh."
        }
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let target = downloads.appendingPathComponent("WINGLampBridge.zip")
        do {
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
            try FileManager.default.copyItem(at: source, to: target)
            NSWorkspace.shared.activateFileViewerSelecting([target])
            return "Saved WINGLampBridge.zip to Downloads. AirDrop it or copy it to the audio MacBook, unzip it, then right-click Install WING Lamp Bridge.command and choose Open."
        } catch {
            return "Couldn't save the installer: \(error.localizedDescription)"
        }
    }
}
