import SwiftUI
import CoreMIDI
import AppKit

// Ableton Live Theme Colors
private let abletonBg = Color(red: 0.11, green: 0.11, blue: 0.11)
private let abletonSurface = Color(red: 0.16, green: 0.16, blue: 0.16)
private let abletonCard = Color(red: 0.20, green: 0.20, blue: 0.20)
private let abletonBorder = Color(red: 0.28, green: 0.28, blue: 0.28)
private let abletonMint = Color(red: 0.0, green: 0.90, blue: 0.46)     // #00E575
private let abletonAmber = Color(red: 1.0, green: 0.65, blue: 0.10)    // #FFA71A

/// Network MIDI tab: where cues go, the WING lamp and its flash pattern,
/// and everything technical folded under Advanced.
struct MIDISettingsView: View {
    var model: Model
    @State private var testChannel: Int = 1
    @State private var showAdvanced = false

    private var midi: MIDIEngine { model.midiEngine }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    sendToCard
                    lampCard
                    if let err = midi.lastError {
                        errorBanner(err)
                    }
                    advancedSection
                }
                .padding(16)
            }
        }
        .background(abletonBg)
    }

    // MARK: Header

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Circle()
                    .fill(midi.networkPortAvailable ? abletonMint : Color.gray)
                    .frame(width: 8, height: 8)
                Text("NETWORK MIDI")
                    .font(.system(size: 15, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white)
            }
            Spacer()
            OpenStatusButton(model: model, runTest: true, title: "TEST CONNECTION")
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(abletonMint).foregroundStyle(.black).cornerRadius(4)
            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Audio MIDI Setup.app"))
            } label: {
                Label("AUDIO MIDI SETUP", systemImage: "network")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(abletonCard).foregroundStyle(.white).cornerRadius(4)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(abletonBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(abletonSurface)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(abletonBorder), alignment: .bottom)
    }

    // MARK: Send to

    private var sendToCard: some View {
        card("SEND TO") {
            Picker("Send to", selection: Bindable(midi).selectedUSBOutput) {
                Text("Network MIDI session (audio Mac and bridge)").tag(MIDIEndpointRef(0))
                ForEach(midi.usbOutputs) { output in
                    Text("\(output.name) (USB, this Mac)").tag(output.id)
                }
                if midi.selectedUSBOutput != 0, !midi.usbOutputs.contains(where: { $0.id == midi.selectedUSBOutput }) {
                    Text("Selected WING USB port unavailable").tag(midi.selectedUSBOutput)
                }
            }
            if midi.selectedUSBOutput == 0 {
                HStack {
                    Picker("Network session", selection: Bindable(midi).selectedNetworkOutputID) {
                        Text("Choose a network session").tag(Optional<MIDIUniqueID>.none)
                        ForEach(midi.networkOutputs) { output in
                            Text(output.name).tag(Optional(output.id))
                        }
                        if let id = midi.selectedNetworkOutputID, !midi.networkOutputs.contains(where: { $0.id == id }) {
                            Text("Selected session unavailable").tag(Optional(id))
                        }
                    }
                    Button("Refresh") { midi.refreshMIDIPorts() }
                }
                TimelineView(.periodic(from: .now, by: 2)) { _ in
                    statusLine(
                        ok: midi.bridgeOnline,
                        okText: "Bridge on the audio Mac is online\(midi.lastBridgeReply.map { $0.wingFound ? " and sees the WING" : ", but can't see the WING" } ?? "").",
                        badText: midi.networkPortAvailable
                            ? "The audio Mac's bridge isn't answering. Press TEST CONNECTION to find out why."
                            : "No network session. Turn one on in Audio MIDI Setup and connect the audio Mac."
                    )
                }
            } else {
                let ok = midi.usbOutputs.contains { $0.id == midi.selectedUSBOutput }
                statusLine(ok: ok, okText: "Sending straight to the WING over USB.",
                           badText: "The WING USB port isn't connected. Check the cable and that the WING is on.")
            }
        }
    }

    // MARK: WING lamp

    private var lampCard: some View {
        let flash = Bindable(midi).lampFlash
        return card("WING LAMP") {
            HStack(spacing: 8) {
                bigButton(midi.isLampFlashing ? "FLASHING…" : "FLASH", color: abletonAmber) { midi.flashWINGLamp() }
                bigButton("ON", color: Color(white: 0.85)) { midi.setWINGLamp(on: true) }
                bigButton("OFF", color: Color(white: 0.85)) { midi.setWINGLamp(on: false) }
                Spacer()
                Text("Last sent: \(midi.lastSentMIDI)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Divider().background(abletonBorder)

            HStack {
                Text("Flash pattern").font(.system(size: 13, weight: .bold))
                Spacer()
                Text(midi.lampFlash.presetName ?? "Custom")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(abletonAmber)
            }
            HStack(spacing: 6) {
                ForEach(LampFlashSettings.presets) { preset in
                    let selected = midi.lampFlash.presetName == preset.name
                    Button(preset.name) {
                        var next = preset.settings
                        next.brightness = midi.lampFlash.brightness
                        midi.lampFlash = next
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(selected ? abletonAmber : abletonSurface)
                    .foregroundStyle(selected ? .black : .white)
                    .cornerRadius(4)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(selected ? abletonAmber : abletonBorder, lineWidth: 1))
                }
            }

            sliderRow("Light on", value: flash.onSeconds, range: 0.1...5, step: 0.05,
                      label: LampFlashSettings.fmt(midi.lampFlash.onSeconds))
            sliderRow("Light off between", value: flash.offSeconds, range: 0.1...5, step: 0.05,
                      label: LampFlashSettings.fmt(midi.lampFlash.offSeconds))
                .disabled(midi.lampFlash.flashes == 1)
                .opacity(midi.lampFlash.flashes == 1 ? 0.45 : 1)
            HStack {
                Text("Flashes").frame(width: 130, alignment: .leading)
                Stepper(value: flash.flashes, in: 1...20) {
                    Text("\(midi.lampFlash.flashes)").font(.system(size: 13, weight: .bold, design: .monospaced))
                }
                Spacer()
            }
            sliderRow("Brightness", value: Binding(
                get: { Double(midi.lampFlash.brightness) },
                set: { midi.lampFlash.brightness = Int($0.rounded()) }),
                range: 1...127, step: 1,
                label: "\(Int((Double(midi.lampFlash.brightness) / 127 * 100).rounded()))%")

            FlashPatternPreview(settings: midi.lampFlash)
                .frame(height: 26)
            HStack {
                Text(midi.lampFlash.summary + ", then off.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(white: 0.75))
                Spacer()
                Button("Reset") { midi.lampFlash = .default }
                    .disabled(midi.lampFlash == .default)
            }
            Text("Saved automatically. Used by the Front of House rule, the FLASH button and Test Connection. The lamp always ends off.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onChange(of: midi.lampFlash) { _, _ in model.saveConfig() }
    }

    // MARK: Advanced

    private var advancedSection: some View {
        DisclosureGroup(isExpanded: $showAdvanced) {
            VStack(alignment: .leading, spacing: 14) {
                card("RECEIVING") {
                    Picker("Network receive port", selection: Bindable(midi).selectedNetworkInputID) {
                        Text("Choose a network port").tag(Optional<MIDIUniqueID>.none)
                        ForEach(midi.networkInputs) { input in
                            Text(input.name).tag(Optional(input.id))
                        }
                        if let id = midi.selectedNetworkInputID, !midi.networkInputs.contains(where: { $0.id == id }) {
                            Text("Selected network port unavailable").tag(Optional(id))
                        }
                    }
                    Text("LiveCue hears the bridge's answers here. It normally matches the session you send on.")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("Bridge incoming network MIDI to the selected WING USB output", isOn: Bindable(midi).bridgeNetworkToUSB)
                        .disabled(!midi.usbOutputs.contains(where: { $0.id == midi.selectedUSBOutput }))
                    Text("Only when LiveCue runs on the Mac plugged into the WING. A separate audio Mac uses WING Lamp Bridge instead. Keep Audio MIDI Setup's Live routings blank while any bridge is on.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Received: \(midi.receivedNetworkMessages) • Forwarded to USB: \(midi.forwardedMessages) • Sent: \(midi.sentMessageCount)")
                        .font(.system(size: 11, design: .monospaced))
                    Text("Last received: \(midi.lastReceivedMIDI)")
                        .font(.system(size: 11, design: .monospaced))
                }

                card("AUDIO MAC BRIDGE") {
                    HStack {
                        Button("Get bridge installer") { model.connectionTest.perform(.getBridgeInstaller) }
                        Spacer()
                    }
                    Text(model.connectionTest.installerMessage
                         ?? "Saves WINGLampBridge.zip to Downloads, ready to copy to the audio Mac.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                card("MACS ON THE NETWORK") {
                    if midi.advertisedHostNames.isEmpty {
                        Text("No network MIDI sessions seen yet.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    } else {
                        ForEach(midi.advertisedHostNames, id: \.self) { name in
                            HStack(spacing: 8) {
                                Image(systemName: "desktopcomputer").foregroundStyle(abletonMint)
                                Text(name).font(.system(size: 12, weight: .semibold))
                                if name == MIDIEngine.thisMacName {
                                    Text("this Mac").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    Text("Being seen doesn't mean connected. Connect Macs in Audio MIDI Setup → Network.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                card("QUICK MIDI TEST") {
                    HStack(spacing: 10) {
                        Button("Note On (C4)") { midi.sendNoteOn(channel: UInt8(testChannel - 1), note: 60, velocity: 127) }
                        Button("Note Off (C4)") { midi.sendNoteOff(channel: UInt8(testChannel - 1), note: 60, velocity: 0) }
                        Button("MSC GO cue 1") { midi.sendMSC(deviceID: 1, commandFormat: 0x01, command: 0x01, cueNumber: "1") }
                        Spacer()
                    }
                    Text("Sends to the output chosen in Send to. The WING Lamp Bridge ignores these; they're for QLab or a lighting desk.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.top, 10)
        } label: {
            Text("ADVANCED")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundStyle(Color(white: 0.6))
        }
    }

    // MARK: Pieces

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundStyle(Color(white: 0.6))
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(abletonCard)
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(abletonBorder, lineWidth: 1))
    }

    private func statusLine(ok: Bool, okText: String, badText: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(ok ? abletonMint : abletonAmber).frame(width: 8, height: 8)
            Text(ok ? okText : badText)
                .font(.system(size: 12))
                .foregroundStyle(ok ? abletonMint : abletonAmber)
        }
    }

    private func bigButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                .frame(minWidth: 64)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(color).foregroundStyle(.black).cornerRadius(4)
        }
        .buttonStyle(.plain)
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, label: String) -> some View {
        HStack {
            Text(title).frame(width: 130, alignment: .leading)
            Slider(value: value, in: range, step: step)
            Text(label)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .frame(width: 60, alignment: .trailing)
        }
    }

    private func errorBanner(_ err: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(abletonAmber)
            Text(err).font(.system(size: 12, design: .monospaced)).foregroundStyle(abletonAmber)
            Spacer()
        }
        .padding(10)
        .background(abletonAmber.opacity(0.12))
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(abletonAmber.opacity(0.3), lineWidth: 1))
    }
}

/// A strip showing when the lamp is on (amber, by brightness) across the pattern.
struct FlashPatternPreview: View {
    let settings: LampFlashSettings

    var body: some View {
        let s = settings.clamped
        let total = max(s.schedule.last?.time ?? 1, 0.1)
        Canvas { context, size in
            let back = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 4)
            context.fill(back, with: .color(Color(white: 0.13)))
            let schedule = s.schedule
            let alpha = 0.35 + 0.65 * Double(s.brightness) / 127
            for i in stride(from: 0, to: schedule.count - 1, by: 2) {
                let x0 = schedule[i].time / total * size.width
                let x1 = schedule[i + 1].time / total * size.width
                let rect = CGRect(x: x0, y: 3, width: max(2, x1 - x0), height: size.height - 6)
                context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(abletonAmber.opacity(alpha)))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Text(LampFlashSettings.fmt(total))
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(white: 0.6))
                .padding(.trailing, 4).padding(.bottom, 1)
        }
        .accessibilityLabel("Flash pattern: \(settings.summary)")
    }
}
