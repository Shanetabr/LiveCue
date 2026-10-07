import SwiftUI

// Ableton Live Theme Colors
private let abletonBg = Color(red: 0.11, green: 0.11, blue: 0.11)
private let abletonSurface = Color(red: 0.16, green: 0.16, blue: 0.16)
private let abletonCard = Color(red: 0.20, green: 0.20, blue: 0.20)
private let abletonBorder = Color(red: 0.28, green: 0.28, blue: 0.28)
private let abletonMint = Color(red: 0.0, green: 0.90, blue: 0.46)     // #00E575
private let abletonAmber = Color(red: 1.0, green: 0.65, blue: 0.10)    // #FFA71A
private let abletonYellow = Color(red: 1.0, green: 0.84, blue: 0.0)    // #FFD600
private let abletonCyan = Color(red: 0.0, green: 0.82, blue: 1.0)      // #00D2FF

struct ChannelsManagerView: View {
    var model: Model
    @State private var showingAddSheet = false
    @State private var editingChannel: ChannelConfig?

    private var availableInputsCount: Int {
        model.device?.inputChannels ?? 16
    }

    var body: some View {
        VStack(spacing: 0) {
            // Ableton Hardware Device Inspector Header
            deviceBanner

            // Channels List
            if model.channels.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(Array(model.channels.enumerated()), id: \.element.id) { index, ch in
                            abletonTrackStrip(index: index, channel: ch)
                        }

                        if model.channels.count < model.maxChannelsLimit {
                            Button {
                                showingAddSheet = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 14, weight: .bold))
                                    Text("ADD CHANNEL (\(model.channels.count)/\(model.maxChannelsLimit))")
                                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                                }
                                .foregroundStyle(abletonMint)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(abletonCard)
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(abletonBorder, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(model.running)
                            .padding(.top, 4)
                        } else {
                            HStack {
                                Image(systemName: "lock.shield.fill")
                                    .foregroundStyle(abletonAmber)
                                Text("MAXIMUM 6 CHANNELS CONFIGURED (Optimized for Real-Time On-Device AI)")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(abletonAmber)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity)
                            .background(abletonCard.opacity(0.8))
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(abletonAmber.opacity(0.4), lineWidth: 1))
                            .padding(.top, 4)
                        }
                    }
                    .padding(14)
                }
            }
        }
        .background(abletonBg)
        .sheet(isPresented: $showingAddSheet) {
            ChannelEditSheet(
                maxChannels: availableInputsCount,
                onSave: { newCh in
                    if model.channels.count < model.maxChannelsLimit {
                        model.channels.append(newCh)
                        model.syncChannelStates()
                        model.saveConfig()
                    }
                    showingAddSheet = false
                },
                onCancel: {
                    showingAddSheet = false
                }
            )
        }
        .sheet(item: $editingChannel) { ch in
            ChannelEditSheet(
                initialChannel: ch,
                maxChannels: availableInputsCount,
                onSave: { updated in
                    if let idx = model.channels.firstIndex(where: { $0.id == updated.id }) {
                        model.channels[idx] = updated
                        model.syncChannelStates()
                        model.saveConfig()
                    }
                    editingChannel = nil
                },
                onCancel: {
                    editingChannel = nil
                }
            )
        }
    }

    // MARK: - Device Info Banner

    private var deviceBanner: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(model.device != nil ? abletonMint : .red)
                        .frame(width: 8, height: 8)
                    Text(model.device?.name ?? "No Audio Device Connected")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                }

                if let dev = model.device {
                    Text(dev.channelSummary)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color(white: 0.65))
                } else {
                    Text("Select a device in the top transport bar")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Channels Capacity Indicator
            HStack(spacing: 8) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("SLOTS USED")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(white: 0.55))
                    Text("\(model.channels.count) / \(model.maxChannelsLimit)")
                        .font(.system(size: 14, weight: .heavy, design: .monospaced))
                        .foregroundStyle(model.channels.count >= model.maxChannelsLimit ? abletonAmber : abletonMint)
                }

                if model.channels.count < model.maxChannelsLimit {
                    Button {
                        showingAddSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text("ADD")
                        }
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(abletonMint)
                        .foregroundStyle(.black)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.running)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(abletonSurface)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(abletonBorder), alignment: .bottom)
    }

    // MARK: - Track Strip

    private func abletonTrackStrip(index: Int, channel: ChannelConfig) -> some View {
        let state = model.channelStates.first(where: { $0.id == channel.id })
        let color = Color(hex: channel.colorHex) ?? abletonMint
        let isSpeaking = !(state?.partial.isEmpty ?? true)

        return HStack(spacing: 0) {
            // Ableton Track Number & Color Bar
            ZStack {
                Rectangle()
                    .fill(color)
                    .frame(width: 38)

                VStack(spacing: 2) {
                    Text(String(format: "%02d", index + 1))
                        .font(.system(size: 13, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.black)

                    if isSpeaking {
                        Circle()
                            .fill(.white)
                            .frame(width: 5, height: 5)
                    }
                }
            }

            HStack(spacing: 12) {
                // Ableton Track Activator Button (Mute / Enable toggle)
                Button {
                    if !model.running, let idx = model.channels.firstIndex(where: { $0.id == channel.id }) {
                        model.channels[idx].isEnabled.toggle()
                        model.syncChannelStates()
                        model.saveConfig()
                    }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(channel.isEnabled ? abletonYellow : Color(white: 0.15))
                            .frame(width: 28, height: 26)
                        Text("\(index + 1)")
                            .font(.system(size: 12, weight: .heavy, design: .monospaced))
                            .foregroundStyle(channel.isEnabled ? .black : Color(white: 0.45))
                    }
                }
                .buttonStyle(.plain)
                .disabled(model.running)
                .help(channel.isEnabled ? "Click to mute/disable track" : "Click to unmute/enable track")

                // Channel Info
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(channel.name)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(channel.isEnabled ? .white : Color(white: 0.45))

                        if isSpeaking {
                            Text("SPEAKING")
                                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(color)
                                .cornerRadius(3)
                        }
                    }

                    HStack(spacing: 6) {
                        Text("ROUTING: INPUT \(channel.channelIndex + 1)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(white: 0.6))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(white: 0.14))
                            .cornerRadius(3)

                        if channel.channelIndex >= availableInputsCount {
                            Text("INPUT EXCEEDS DEVICE")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.red)
                        }
                    }
                }

                Spacer()

                // Ableton LED Segmented VU Meter (always visible, active when running)
                if channel.isEnabled {
                    AbletonVULevelMeter(level: model.running ? (state?.level ?? 0) : 0)
                        .frame(width: 100, height: 16)
                }

                // Edit Button
                Button {
                    editingChannel = channel
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(white: 0.7))
                        .frame(width: 30, height: 30)
                        .background(Color(white: 0.16))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .disabled(model.running)
                .help("Configure track settings")

                // Delete Button
                Button {
                    if !model.running, let idx = model.channels.firstIndex(where: { $0.id == channel.id }) {
                        model.channels.remove(at: idx)
                        model.syncChannelStates()
                        model.saveConfig()
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.red.opacity(0.85))
                        .frame(width: 30, height: 30)
                        .background(Color(white: 0.16))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .disabled(model.running)
                .help("Delete track")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(abletonCard)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSpeaking ? color : abletonBorder, lineWidth: isSpeaking ? 1.5 : 1)
        )
        .opacity(channel.isEnabled ? 1.0 : 0.5)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.badge.plus")
                .font(.system(size: 42))
                .foregroundStyle(abletonMint)

            Text("NO CHANNELS CONFIGURED")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)

            Text("Add up to 6 audio channels from your interface or Dante Virtual Soundcard to transcribe multiple comms feeds concurrently.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            Button("LOAD PRESET COMMS CHANNELS") {
                model.channels = AppConfig.default.channels
                model.syncChannelStates()
                model.saveConfig()
            }
            .buttonStyle(.borderedProminent)
            .tint(abletonMint)
            .foregroundStyle(.black)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Ableton Segmented VU Level Meter
 
struct AbletonVULevelMeter: View {
    let level: Float
    var segments: Int = 18

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            // Ableton pro-audio dynamic range: -60 dB to 0 dB with +12dB meter sensitivity boost for laptop/USB inputs
            let boosted = level * 4.0
            let db = 20 * log10(max(boosted, 0.00001))
            let norm = max(0, min(1, (db + 60) / 60))
            let activeSegments: Int = {
                if level < 0.0001 { return 0 }
                let raw = Int(round(Double(segments) * Double(norm)))
                return max(1, min(segments, raw))
            }()

            Canvas { context, size in
                let segCount = max(1, segments)
                let gap: CGFloat = size.width < 50 ? 1 : 2
                let totalGaps = gap * CGFloat(segCount - 1)
                let segWidth = max(1, (size.width - totalGaps) / CGFloat(segCount))

                for i in 0..<segCount {
                    let isLit = i < activeSegments
                    let color: Color = {
                        if i >= segCount - 2 { return Color(red: 1.0, green: 0.25, blue: 0.25) }     // Peak Red
                        if i >= segCount - 5 { return Color(red: 1.0, green: 0.70, blue: 0.15) }     // Amber
                        return Color(red: 0.0, green: 0.90, blue: 0.46)                             // Mint Green
                    }()

                    let x = CGFloat(i) * (segWidth + gap)
                    let rect = CGRect(x: x, y: 0, width: segWidth, height: size.height)
                    let fill = isLit ? color : color.opacity(0.12)
                    context.fill(Path(rect), with: .color(fill))
                }
            }
            .padding(1.5)
            .frame(width: max(0, w), height: max(0, h))
            .background(Color.black.opacity(0.9))
            .cornerRadius(3)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color(white: 0.25), lineWidth: 1))
        }
    }
}

// MARK: - Channel Edit Sheet (Ableton Track Inspector)

struct ChannelEditSheet: View {
    var initialChannel: ChannelConfig?
    var maxChannels: Int
    var onSave: (ChannelConfig) -> Void
    var onCancel: () -> Void

    @State private var name: String = "Comms Line"
    @State private var channelIndex: Int = 0
    @State private var selectedColorHex: String = "#00E575"

    private let abletonPalette = [
        ("#00E575", "Mint"),
        ("#FF7640", "Orange"),
        ("#00D2FF", "Cyan"),
        ("#FFD600", "Yellow"),
        ("#FF2A85", "Pink"),
        ("#A259FF", "Purple"),
        ("#FF4D4D", "Coral"),
        ("#A4E804", "Lime"),
        ("#3498DB", "Blue"),
        ("#8E9297", "Slate")
    ]

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(initialChannel == nil ? "NEW TRACK INPUT" : "EDIT TRACK INPUT")
                        .font(.system(size: 15, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white)
                    Text("Assign hardware input channel and track color")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.bottom, 4)

            VStack(alignment: .leading, spacing: 14) {
                // Track Name
                VStack(alignment: .leading, spacing: 6) {
                    Text("TRACK NAME")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(white: 0.6))
                    TextField("e.g. FOH Comms, Director Call, Stage Manager", text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                // Hardware Audio Input Selector
                VStack(alignment: .leading, spacing: 6) {
                    Text("HARDWARE AUDIO INPUT")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(white: 0.6))

                    Picker("", selection: $channelIndex) {
                        ForEach(0..<max(1, maxChannels), id: \.self) { idx in
                            Text("Input \(idx + 1)").tag(idx)
                        }
                    }
                    .labelsHidden()
                }

                // Track Color Swatches
                VStack(alignment: .leading, spacing: 8) {
                    Text("TRACK COLOR")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(white: 0.6))

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                        ForEach(abletonPalette, id: \.0) { hex, label in
                            let isSelected = selectedColorHex.caseInsensitiveCompare(hex) == .orderedSame
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color(hex: hex) ?? .gray)
                                    .frame(width: 16, height: 16)
                                Text(label)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(isSelected ? .white : Color(white: 0.6))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(isSelected ? Color(white: 0.28) : Color(white: 0.16))
                            .cornerRadius(4)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(isSelected ? .white : Color.clear, lineWidth: 1.5)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedColorHex = hex
                            }
                        }
                    }
                }
            }

            Spacer()

            // Buttons
            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save Track") {
                    let ch = ChannelConfig(
                        id: initialChannel?.id ?? UUID(),
                        name: name.trimmingCharacters(in: .whitespaces),
                        colorHex: selectedColorHex,
                        channelIndex: channelIndex,
                        isEnabled: initialChannel?.isEnabled ?? true
                    )
                    onSave(ch)
                }
                .buttonStyle(.borderedProminent)
                .tint(abletonMint)
                .foregroundStyle(.black)
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 460, minHeight: 380)
        .background(abletonBg)
        .onAppear {
            if let initial = initialChannel {
                name = initial.name
                channelIndex = initial.channelIndex
                selectedColorHex = initial.colorHex
            }
        }
    }
}

// Helper extension for Color from hex
extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}
