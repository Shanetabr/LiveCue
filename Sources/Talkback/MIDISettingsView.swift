import SwiftUI

// Ableton Live Theme Colors
private let abletonBg = Color(red: 0.11, green: 0.11, blue: 0.11)
private let abletonSurface = Color(red: 0.16, green: 0.16, blue: 0.16)
private let abletonCard = Color(red: 0.20, green: 0.20, blue: 0.20)
private let abletonBorder = Color(red: 0.28, green: 0.28, blue: 0.28)
private let abletonMint = Color(red: 0.0, green: 0.90, blue: 0.46)     // #00E575
private let abletonAmber = Color(red: 1.0, green: 0.65, blue: 0.10)    // #FFA71A

struct MIDISettingsView: View {
    var model: Model
    @State private var showingAddManualSheet = false
    @State private var testChannel: Int = 1
    @State private var testNote: Int = 60

    var body: some View {
        VStack(spacing: 0) {
            // Ableton Header bar
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(model.midiEngine.isConnected ? abletonMint : Color.gray)
                        .frame(width: 8, height: 8)
                    Text("NETWORK MIDI SESSION ROUTING")
                        .font(.system(size: 15, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white)
                }

                Spacer()

                Button {
                    showingAddManualSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("MANUAL DESTINATION")
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
                    // Status Banner
                    HStack(spacing: 14) {
                        Image(systemName: model.midiEngine.isConnected ? "network" : "network.slash")
                            .font(.system(size: 26))
                            .foregroundStyle(model.midiEngine.isConnected ? abletonMint : Color(white: 0.5))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.midiEngine.isConnected ? "CONNECTED TO NETWORK MIDI SESSION" : "NO ACTIVE NETWORK DESTINATIONS CONNECTED")
                                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                                .foregroundStyle(model.midiEngine.isConnected ? abletonMint : .white)
                            Text("Apple-MIDI (RTP-MIDI) transmits Universal MIDI Packets (UMP) and MSC SysEx over UDP port 5004 across local network.")
                                .font(.caption)
                                .foregroundStyle(Color(white: 0.65))
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(abletonCard)
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(abletonBorder, lineWidth: 1))

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
                        Text("ACTIVE & BONJOUR DISCOVERED ENDPOINTS")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundStyle(Color(white: 0.6))

                        if model.midiEngine.destinations.isEmpty {
                            VStack(spacing: 8) {
                                Text("Scanning local network for Bonjour Apple-MIDI hosts (_apple-midi._udp)…")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color(white: 0.7))
                                Text("Or click 'MANUAL DESTINATION' to connect directly to QLab, Eos, or grandMA via IP.")
                                    .font(.caption)
                                    .foregroundStyle(Color(white: 0.5))
                            }
                            .padding(20)
                            .frame(maxWidth: .infinity)
                            .background(abletonCard.opacity(0.6))
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(abletonBorder, lineWidth: 1))
                        } else {
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
        .sheet(isPresented: $showingAddManualSheet) {
            AddManualDestinationSheet(onAdd: { name, address, port in
                model.midiEngine.addManualDestination(name: name, address: address, port: port)
                model.midiEngine.selectedDestinationIDs.insert("\(address):\(port)")
                model.saveConfig()
                showingAddManualSheet = false
            }, onCancel: {
                showingAddManualSheet = false
            })
        }
    }

    private func destinationRow(_ dest: MIDIDestination) -> some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { model.midiEngine.selectedDestinationIDs.contains(dest.id) },
                set: { isSelected in
                    if isSelected {
                        model.midiEngine.selectedDestinationIDs.insert(dest.id)
                    } else {
                        model.midiEngine.selectedDestinationIDs.remove(dest.id)
                    }
                    model.saveConfig()
                }
            ))
            .labelsHidden()

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

                    if dest.isConnected {
                        Text("CONNECTED")
                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .foregroundStyle(abletonMint)
                    }
                }

                Text("\(dest.address):\(dest.port)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color(white: 0.6))
            }

            Spacer()

            Button("TEST NOTE") {
                model.midiEngine.sendNoteOn(channel: 0, note: 60, velocity: 127)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    model.midiEngine.sendNoteOff(channel: 0, note: 60, velocity: 0)
                }
            }
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(white: 0.16))
            .cornerRadius(4)
        }
        .padding(12)
        .background(abletonCard)
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(abletonBorder, lineWidth: 1))
    }
}

struct AddManualDestinationSheet: View {
    var onAdd: (String, String, UInt16) -> Void
    var onCancel: () -> Void

    @State private var name: String = "Lighting Console"
    @State private var address: String = "192.168.1.50"
    @State private var portString: String = "5004"

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("ADD NETWORK MIDI HOST")
                    .font(.system(size: 15, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white)
                Spacer()
            }

            Form {
                TextField("Destination Name (e.g. QLab Mac Mini, Eos Ion)", text: $name)
                TextField("IP Address or Hostname", text: $address)
                TextField("Port (standard Apple-MIDI is 5004)", text: $portString)
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add & Connect") {
                    let port = UInt16(portString) ?? 5004
                    onAdd(name, address, port)
                }
                .buttonStyle(.borderedProminent)
                .tint(abletonMint)
                .foregroundStyle(.black)
                .keyboardShortcut(.defaultAction)
                .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .frame(minWidth: 420, minHeight: 270)
        .background(abletonBg)
    }
}
