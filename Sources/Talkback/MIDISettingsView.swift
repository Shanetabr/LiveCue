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

struct MIDISettingsView: View {
    var model: Model
    @State private var testChannel: Int = 1

    var body: some View {
        VStack(spacing: 0) {
            // Ableton Header bar
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(model.midiEngine.networkPortAvailable ? abletonMint : Color.gray)
                        .frame(width: 8, height: 8)
                    Text("NETWORK MIDI SESSION ROUTING")
                        .font(.system(size: 15, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white)
                }

                Spacer()

                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Audio MIDI Setup.app"))
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "network")
                        Text("AUDIO MIDI SETUP")
                    }
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(abletonMint)
                    .foregroundStyle(.black)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(abletonSurface)
            .overlay(Rectangle().frame(height: 1).foregroundStyle(abletonBorder), alignment: .bottom)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("WING OUTPUT & LAMP TEST").font(.headline)
                        Picker("Send to", selection: Bindable(model.midiEngine).selectedUSBOutput) {
                            Text("Network MIDI session (stage Mac)").tag(MIDIEndpointRef(0))
                            ForEach(model.midiEngine.usbOutputs) { output in
                                Text(output.name).tag(output.id)
                            }
                            if model.midiEngine.selectedUSBOutput != 0,
                               !model.midiEngine.usbOutputs.contains(where: { $0.id == model.midiEngine.selectedUSBOutput }) {
                                Text("Selected WING USB port unavailable").tag(model.midiEngine.selectedUSBOutput)
                            }
                        }
                        if model.midiEngine.selectedUSBOutput == 0 {
                            Picker("Local network output", selection: Bindable(model.midiEngine).selectedNetworkOutputID) {
                                Text("Choose a network port").tag(Optional<MIDIUniqueID>.none)
                                ForEach(model.midiEngine.networkOutputs) { output in
                                    Text(output.name).tag(Optional(output.id))
                                }
                                if let id = model.midiEngine.selectedNetworkOutputID,
                                   !model.midiEngine.networkOutputs.contains(where: { $0.id == id }) {
                                    Text("Selected network port unavailable").tag(Optional(id))
                                }
                            }
                        }
                        Button("Refresh MIDI ports") { model.midiEngine.refreshMIDIPorts() }
                        Text("On the stage Mac, select its local network output. Connect the audio Mac as a participant in Audio MIDI Setup.")
                            .font(.caption)
                        Text("For direct USB, select WING Port 4 / MIDI Control. These buttons send channel 6, CC 16 to Layer 2 encoder 1 assigned to Lamp Brightness.")
                            .font(.caption)
                        HStack {
                            Button("LAMP ON") { model.midiEngine.setWINGLamp(on: true) }
                            Button("LAMP OFF") { model.midiEngine.setWINGLamp(on: false) }
                            Button("FLASH 3 SECONDS") { model.midiEngine.flashWINGLamp() }
                        }
                        Text("Last sent: \(model.midiEngine.lastSentMIDI)").font(.system(.caption, design: .monospaced))
                        Picker("Network receive port", selection: Bindable(model.midiEngine).selectedNetworkInputID) {
                            Text("Choose a network port").tag(Optional<MIDIUniqueID>.none)
                            ForEach(model.midiEngine.networkInputs) { input in
                                Text(input.name).tag(Optional(input.id))
                            }
                            if let id = model.midiEngine.selectedNetworkInputID,
                               !model.midiEngine.networkInputs.contains(where: { $0.id == id }) {
                                Text("Selected network port unavailable").tag(Optional(id))
                            }
                        }
                        Toggle("Bridge incoming Network MIDI to selected WING USB output", isOn: Bindable(model.midiEngine).bridgeNetworkToUSB)
                            .disabled(!model.midiEngine.usbOutputs.contains(where: { $0.id == model.midiEngine.selectedUSBOutput }))
                        Text("On the audio Mac, use either this bridge or Audio MIDI Setup’s bottom Live routing to WING Port 4. Leave both Live routings blank when this bridge is on.")
                            .font(.caption)
                        Text("Network received: \(model.midiEngine.receivedNetworkMessages) • Forwarded to USB: \(model.midiEngine.forwardedMessages)")
                        Text("Last received: \(model.midiEngine.lastReceivedMIDI)").font(.system(.caption, design: .monospaced))
                    }
                    .padding(14)
                    .background(abletonCard)
                    .cornerRadius(6)

                    // Status Banner
                    HStack(spacing: 14) {
                        Image(systemName: model.midiEngine.networkPortAvailable ? "network" : "network.slash")
                            .font(.system(size: 26))
                            .foregroundStyle(model.midiEngine.networkPortAvailable ? abletonMint : Color(white: 0.5))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.midiEngine.networkPortAvailable ? "LOCAL NETWORK MIDI PORT AVAILABLE" : "SELECT AN AVAILABLE NETWORK MIDI PORT")
                                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                                .foregroundStyle(model.midiEngine.networkPortAvailable ? abletonMint : .white)
                            Text("Check connected participants in Audio MIDI Setup. A local port being available does not confirm delivery to the audio Mac or WING.")
                                .font(.caption)
                                .foregroundStyle(Color(white: 0.65))
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(abletonCard)
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(abletonBorder, lineWidth: 1))

                    Text("CoreMIDI accepted messages: \(model.midiEngine.sentMessageCount). This confirms local sending, not receipt by the WING.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let err = model.midiEngine.lastError {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(abletonAmber)
                            Text(err)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(abletonAmber)
                        }
                        .padding(10)
                        .background(abletonAmber.opacity(0.12))
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(abletonAmber.opacity(0.3), lineWidth: 1))
                    }

                    // Destinations List
                    VStack(alignment: .leading, spacing: 10) {
                        Text("DISCOVERED & SAVED NETWORK HOSTS")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundStyle(Color(white: 0.6))

                        if model.midiEngine.destinations.isEmpty {
                            VStack(spacing: 8) {
                                Text("Scanning local network for Bonjour Apple-MIDI hosts (_apple-midi._udp)…")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color(white: 0.7))
                                Text("Add or connect a remote host in Audio MIDI Setup’s Network window.")
                                    .font(.caption)
                                    .foregroundStyle(Color(white: 0.5))
                            }
                            .padding(20)
                            .frame(maxWidth: .infinity)
                            .background(abletonCard.opacity(0.6))
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(abletonBorder, lineWidth: 1))
                        } else {
                            Text("Host discovery does not establish a connection. Connect the required participant in Audio MIDI Setup.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            VStack(spacing: 8) {
                                ForEach(model.midiEngine.destinations) { dest in
                                    destinationRow(dest)
                                }
                            }
                        }
                    }

                    Divider().background(abletonBorder)

                    // Quick Test Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("QUICK MIDI TEST (CUE CONTROL)")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundStyle(Color(white: 0.6))

                        HStack(spacing: 12) {
                            Button("SEND NOTE ON (C4 / 60)") {
                                model.midiEngine.sendNoteOn(channel: UInt8(testChannel - 1), note: 60, velocity: 127)
                            }
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(abletonCard)
                            .cornerRadius(4)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(abletonBorder, lineWidth: 1))

                            Button("SEND NOTE OFF (C4 / 60)") {
                                model.midiEngine.sendNoteOff(channel: UInt8(testChannel - 1), note: 60, velocity: 0)
                            }
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(white: 0.8))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(abletonCard)
                            .cornerRadius(4)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(abletonBorder, lineWidth: 1))

                            Button("SEND MSC GO (CUE 1)") {
                                model.midiEngine.sendMSC(deviceID: 1, commandFormat: 0x01, command: 0x01, cueNumber: "1")
                            }
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(abletonMint)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(abletonCard)
                            .cornerRadius(4)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(abletonMint.opacity(0.6), lineWidth: 1))
                        }
                    }
                }
                .padding(16)
            }
        }
        .background(abletonBg)
    }

    private func destinationRow(_ dest: MIDIDestination) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(dest.name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)

                    if dest.isManual {
                        Text("MANUAL")
                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.blue)
                            .cornerRadius(3)
                    } else {
                        Text("BONJOUR")
                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(abletonMint)
                            .cornerRadius(3)
                    }

                }

                Text("\(dest.address):\(dest.port)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color(white: 0.6))
            }

            Spacer()

        }
        .padding(12)
        .background(abletonCard)
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(abletonBorder, lineWidth: 1))
    }
}
