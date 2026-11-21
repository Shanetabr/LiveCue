import SwiftUI

private let bg = Color(red: 0.11, green: 0.11, blue: 0.11)
private let card = Color(red: 0.19, green: 0.19, blue: 0.19)
private let lineColor = Color(red: 0.28, green: 0.28, blue: 0.28)
private let mint = Color(red: 0.0, green: 0.90, blue: 0.46)
private let amber = Color(red: 1.0, green: 0.65, blue: 0.10)
private let red = Color(red: 1.0, green: 0.25, blue: 0.25)
private let grey = Color(white: 0.45)

/// The "LiveCue Status" window: what's working right now, plus Test Connection.
struct StatusView: View {
    var model: Model
    private var test: ConnectionTest { model.connectionTest }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    liveStatus(now: context.date)
                }
                testSection
            }
            .padding(18)
        }
        .frame(minWidth: 520, minHeight: 560)
        .background(bg)
        .preferredColorScheme(.dark)
    }

    // MARK: Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("LiveCue Status").font(.system(size: 20, weight: .heavy))
                Text("Stage Mac → network → audio MacBook → WING lamp")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                test.run()
            } label: {
                Label(test.isRunning ? "Testing…" : "Test Connection", systemImage: "checklist")
                    .font(.system(size: 13, weight: .bold))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(mint).foregroundStyle(.black).cornerRadius(5)
            }
            .buttonStyle(.plain)
            .disabled(test.isRunning)
        }
    }

    // MARK: Live status

    private func liveStatus(now: Date) -> some View {
        let midi = model.midiEngine
        return VStack(alignment: .leading, spacing: 0) {
            sectionTitle("RIGHT NOW")
            row(model.running ? mint : grey, "Listening",
                model.running ? model.status : "Stopped. Press START in the main window to listen.")
            if model.running {
                row(mint, "Audio input", model.audioInputStatus)
            }
            if !model.channelsMissingOnDevice.isEmpty {
                row(amber, "Channels", "\(model.channelsMissingOnDevice.map(\.name).joined(separator: ", ")) use an input this device doesn't have and will be skipped.")
            }
            if midi.selectedUSBOutput != 0 {
                let ok = midi.usbOutputs.contains { $0.id == midi.selectedUSBOutput }
                row(ok ? mint : red, "WING (USB)", ok ? "Sending straight to the WING over USB." : "The WING USB port isn't connected.")
            } else {
                let session = midi.networkOutputs.first { $0.id == midi.selectedNetworkOutputID }
                row(session != nil ? mint : red, "Network MIDI",
                    session.map { "Sending on \($0.name)." } ?? "No network session. Set one up in Audio MIDI Setup.")
                let others = midi.otherHostNames
                row(others.isEmpty ? amber : mint, "Macs on the network",
                    others.isEmpty ? "No other Mac is advertising network MIDI. Check the Ethernet cable and that the audio MacBook is on."
                                   : others.joined(separator: ", "))
                bridgeRow(now: now)
            }
            if let lamp = midi.lastLampCommand {
                row(grey, "Last lamp message", "\(lamp.value == 0 ? "OFF" : "ON") sent \(ago(lamp.at, now))")
            }
            if let banner = model.lastTriggerBanner {
                row(model.lastTriggerFailed ? red : mint, "Last rule", banner)
            }
            if let error = midi.lastError {
                row(amber, "Last problem", error)
            }
        }
        .background(card).cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(lineColor, lineWidth: 1))
    }

    @ViewBuilder
    private func bridgeRow(now: Date) -> some View {
        let midi = model.midiEngine
        if let reply = midi.lastBridgeReply, now.timeIntervalSince(reply.at) < 25 {
            row(mint, "Audio MacBook bridge", "Online. WING Lamp Bridge \(reply.version), answered \(ago(reply.at, now)) in \(reply.roundTripMs) ms.")
            row(reply.wingFound ? mint : red, "WING", reply.wingFound ? "Plugged into the audio MacBook (WING Port 4)." : "The bridge can't see WING Port 4. Check the USB cable and that the WING is on.")
        } else if let reply = midi.lastBridgeReply {
            row(red, "Audio MacBook bridge", "Not answering. Last answer \(ago(reply.at, now)). Check the cable and that the audio MacBook is on.")
        } else {
            row(amber, "Audio MacBook bridge", midi.bridgePingsSent == 0
                ? "Checking…"
                : "Hasn't answered. It needs WING Lamp Bridge 1.1 or newer on the audio MacBook (1.0 works but can't answer).")
        }
    }

    // MARK: Test Connection

    private var testSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("TEST CONNECTION")
            Text(test.summary)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 12).padding(.bottom, 8)
            ForEach(test.steps) { step in
                stepRow(step)
            }
            HStack {
                Button("Get bridge installer for the audio MacBook") {
                    test.perform(.getBridgeInstaller)
                }
                Spacer()
            }
            .padding(12)
            if let message = test.installerMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.bottom, 12)
            }
        }
        .background(card).cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(lineColor, lineWidth: 1))
    }

    private func stepRow(_ step: ConnectionTest.Step) -> some View {
        HStack(alignment: .top, spacing: 10) {
            icon(step.state).frame(width: 18)
            VStack(alignment: .leading, spacing: 4) {
                Text(step.title).font(.system(size: 13, weight: .bold))
                if !step.detail.isEmpty {
                    Text(step.detail).font(.system(size: 12)).foregroundStyle(Color(white: 0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if step.state == .needsAnswer {
                    HStack {
                        Button("Yes, it flashed") { test.answerLamp(flashed: true) }
                        Button("No flash") { test.answerLamp(flashed: false) }
                    }
                }
                if let fix = step.fix {
                    Button(fix == .openAudioMIDISetup ? "Open Audio MIDI Setup" : "Get bridge installer") {
                        test.perform(fix)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    @ViewBuilder
    private func icon(_ state: ConnectionTest.State) -> some View {
        switch state {
        case .waiting: Image(systemName: "circle").foregroundStyle(grey)
        case .running: ProgressView().controlSize(.small)
        case .passed: Image(systemName: "checkmark.circle.fill").foregroundStyle(mint)
        case .warning: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(amber)
        case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(red)
        case .skipped: Image(systemName: "minus.circle").foregroundStyle(grey)
        case .needsAnswer: Image(systemName: "questionmark.circle.fill").foregroundStyle(amber)
        }
    }

    // MARK: Helpers

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .heavy, design: .monospaced))
            .foregroundStyle(Color(white: 0.6))
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 6)
    }

    private func row(_ color: Color, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(color).frame(width: 9, height: 9).padding(.top, 4)
            Text(title).font(.system(size: 12, weight: .bold)).frame(width: 150, alignment: .leading)
            Text(detail).font(.system(size: 12)).foregroundStyle(Color(white: 0.8))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    private func ago(_ date: Date, _ now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(date)))
        if s < 2 { return "just now" }
        if s < 60 { return "\(s) s ago" }
        if s < 3600 { return "\(s / 60) min ago" }
        return "at \(date.formatted(date: .omitted, time: .shortened))"
    }
}
