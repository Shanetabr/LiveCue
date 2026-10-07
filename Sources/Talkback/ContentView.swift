import SwiftUI

// Ableton Live 11/12 Theme Palette
private let abletonBg = Color(red: 0.11, green: 0.11, blue: 0.11)         // #1C1C1C
private let abletonSurface = Color(red: 0.15, green: 0.15, blue: 0.15)    // #262626
private let abletonCard = Color(red: 0.19, green: 0.19, blue: 0.19)       // #303030
private let abletonBorder = Color(red: 0.28, green: 0.28, blue: 0.28)     // #474747
private let abletonMint = Color(red: 0.0, green: 0.90, blue: 0.46)        // #00E575 (Play / Signal OK)
private let abletonAmber = Color(red: 1.0, green: 0.65, blue: 0.10)       // #FFA71A (Trigger / Standby)
private let abletonRed = Color(red: 1.0, green: 0.25, blue: 0.25)         // #FF4040 (Stop / Clip / Alert)
private let abletonYellow = Color(red: 1.0, green: 0.84, blue: 0.0)       // #FFD600 (Track Activator)
private let abletonCyan = Color(red: 0.0, green: 0.82, blue: 1.0)         // #00D2FF (Routing)

enum ViewTab: String, CaseIterable, Identifiable {
    case transcript = "Live Transcript"
    case channels = "Channels"
    case rules = "Keyword Rules"
    case midi = "Network MIDI"
    case logs = "Activity Log"

    var id: String { rawValue }
}

struct ContentView: View {
    @Bindable var model: Model

    init(model: Model = Model()) {
        self.model = model
    }
    @State private var selectedTab: ViewTab = .transcript
    @State private var atLive = true
    @State private var showingExportSheet = false

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Ableton Transport Bar (Device Menu, Meters, Start/Stop)
                transportBar

                // Ableton Mode Selector Bar
                segmentedBar

                // Microphone Permission Warning Banner
                if model.isMicrophoneDenied {
                    HStack(spacing: 10) {
                        Image(systemName: "mic.slash.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(abletonRed)
                        Text("Microphone access is not authorized for LiveCue. LiveCue cannot detect audio.")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                        Spacer()
                        Button("Open System Settings") {
                            model.openMicrophonePrivacySettings()
                        }
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(abletonAmber)
                        .cornerRadius(4)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(abletonRed.opacity(0.18))
                    .overlay(Rectangle().frame(height: 1).foregroundStyle(abletonRed.opacity(0.5)), alignment: .bottom)
                }

                // Fired Trigger Alert Banner
                if let banner = model.lastTriggerBanner {
                    triggerBanner(banner)
                }

                // Tab Content
                switch selectedTab {
                case .transcript:
                    transcriptView
                case .channels:
                    ChannelsManagerView(model: model)
                case .rules:
                    KeywordRulesView(model: model)
                case .midi:
                    MIDISettingsView(model: model)
                case .logs:
                    TriggerLogView(model: model)
                }

                // Ableton Status Bar
                statusBar
            }

            // Visual Alert Flash Overlay
            if model.flashTrigger {
                RoundedRectangle(cornerRadius: 0)
                    .strokeBorder(abletonAmber, lineWidth: 10)
                    .background(abletonAmber.opacity(0.18))
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .background(abletonBg)
        .preferredColorScheme(.dark)
        .frame(minWidth: 840, minHeight: 520)
        .navigationTitle(model.documentTitle)
        .sheet(isPresented: $showingExportSheet) {
            ExportSheet(model: model, isPresented: $showingExportSheet)
        }
    }

    // MARK: - Ableton Transport Top Bar

    private var transportBar: some View {
        @Bindable var bindableModel = model

        return HStack(spacing: 12) {
            // Session / Document Quick Menu
            Menu {
                Button {
                    model.newSession()
                } label: {
                    Label("New Session", systemImage: "doc.badge.plus")
                }

                Button {
                    model.openFile()
                } label: {
                    Label("Open…", systemImage: "folder")
                }

                Menu {
                    if model.recentDocumentURLs.isEmpty {
                        Text("No Recent Sessions")
                    } else {
                        ForEach(model.recentDocumentURLs, id: \.self) { url in
                            Button(url.deletingPathExtension().lastPathComponent) {
                                model.openURL(url)
                            }
                        }
                        Divider()
                        Button("Clear Menu") {
                            model.clearRecentDocuments()
                        }
                    }
                } label: {
                    Label("Open Recent", systemImage: "clock")
                }

                Divider()

                Button {
                    model.save()
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }

                Button {
                    model.saveAs()
                } label: {
                    Label("Save As…", systemImage: "square.and.arrow.down.on.square")
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(model.hasUnsavedChanges ? abletonAmber : abletonMint)

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(model.documentDisplayName)
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            if model.hasUnsavedChanges {
                                Circle()
                                    .fill(abletonAmber)
                                    .frame(width: 6, height: 6)
                            }
                        }

                        Text(model.currentDocumentURL == nil ? "Unsaved Session" : "LiveCue Session")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color(white: 0.65))
                    }

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9))
                        .foregroundStyle(Color(white: 0.5))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(abletonCard)
                .cornerRadius(4)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(abletonBorder, lineWidth: 1))
            }
            .menuStyle(.borderlessButton)
            .help("Session File Menu (Save, Save As, Open, Recent)")

            // Audio Device Selector with full In/Out Channel Count
            Menu {
                ForEach(model.devices) { dev in
                    Button {
                        model.selectDevice(dev.id)
                    } label: {
                        HStack {
                            Text(dev.name)
                            Spacer()
                            Text(dev.channelSummary)
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "waveform.path")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(model.running ? abletonMint : abletonAmber)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.device?.name ?? "No Audio Device")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        if let dev = model.device {
                            Text(dev.channelSummary)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color(white: 0.65))
                        }
                    }

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9))
                        .foregroundStyle(Color(white: 0.5))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(abletonCard)
                .cornerRadius(4)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(abletonBorder, lineWidth: 1))
            }
            .menuStyle(.borderlessButton)
            .frame(maxWidth: 340, alignment: .leading)

            // Refresh Device Scan Button
            Button {
                model.refreshDevices()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(white: 0.8))
                    .frame(width: 28, height: 28)
                    .background(abletonCard)
                    .cornerRadius(4)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(abletonBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Rescan CoreAudio devices")

            // Master Peak Meter
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("MASTER")
                        .font(.system(size: 8, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Color(white: 0.5))
                    Spacer()
                }
                AbletonVULevelMeter(level: model.level)
                    .frame(width: 110, height: 14)
            }

            Spacer()

            // Save Session Button
            Button {
                model.save()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 11, weight: .bold))
                    Text("SAVE")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }
            }
            .foregroundStyle(model.hasUnsavedChanges ? abletonAmber : Color(white: 0.8))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(abletonCard)
            .cornerRadius(4)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(model.hasUnsavedChanges ? abletonAmber.opacity(0.8) : abletonBorder, lineWidth: 1))
            .buttonStyle(.plain)
            .help("Save current session (⌘S)")

            // Export Button
            Button("EXPORT") {
                showingExportSheet = true
            }
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(abletonCard)
            .cornerRadius(4)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(abletonBorder, lineWidth: 1))
            .disabled(model.lines.isEmpty)

            // Clear Button
            Button("CLEAR") {
                model.clear()
            }
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(Color(white: 0.75))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(abletonCard)
            .cornerRadius(4)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(abletonBorder, lineWidth: 1))

            // Big Ableton Play/Stop Transport Button
            Button {
                model.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: model.running ? "stop.fill" : "play.fill")
                        .font(.system(size: 13, weight: .heavy))
                    Text(model.running ? "STOP" : "START")
                        .font(.system(size: 13, weight: .heavy, design: .monospaced))
                }
                .foregroundStyle(model.running ? .white : .black)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(model.running ? abletonRed : abletonMint)
                .cornerRadius(4)
                .shadow(color: (model.running ? abletonRed : abletonMint).opacity(0.4), radius: 6, x: 0, y: 0)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [])
            .disabled(model.busy || model.devices.isEmpty)
        }
        .disabled(model.busy)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(abletonSurface)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(abletonBorder), alignment: .bottom)
        .onChange(of: model.running) { _, _ in atLive = true }
    }

    // MARK: - Ableton Mode Selector Bar

    private var segmentedBar: some View {
        HStack {
            Picker("", selection: $selectedTab) {
                Text("TRANSCRIPT").tag(ViewTab.transcript)
                Text("CHANNELS (\(model.channels.count)/\(model.maxChannelsLimit))").tag(ViewTab.channels)
                Text("RULES (\(model.keywordMatcher.rules.count))").tag(ViewTab.rules)
                HStack(spacing: 4) {
                    Circle()
                        .fill(model.midiEngine.isConnected ? abletonMint : Color.gray)
                        .frame(width: 6, height: 6)
                    Text("NETWORK MIDI")
                }.tag(ViewTab.midi)
                Text("LOG (\(model.triggerLogs.count))").tag(ViewTab.logs)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 680)

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color(red: 0.13, green: 0.13, blue: 0.13))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(abletonBorder), alignment: .bottom)
    }

    private func triggerBanner(_ banner: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(abletonAmber)
            Text(banner)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
            Spacer()
            Button {
                model.lastTriggerBanner = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(white: 0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(red: 0.32, green: 0.20, blue: 0.04))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(abletonAmber.opacity(0.6)), alignment: .bottom)
    }

    // MARK: - Ableton Session View Channel Strip

    private var channelStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(model.channelStates.enumerated()), id: \.element.id) { index, state in
                    let color = Color(hex: state.colorHex) ?? abletonMint
                    let isSpeaking = !state.partial.isEmpty

                    HStack(spacing: 8) {
                        // Track Number & Color Bar
                        Rectangle()
                            .fill(color)
                            .frame(width: 6, height: 28)
                            .cornerRadius(1)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(String(format: "%02d", index + 1))
                                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                                    .foregroundStyle(Color(white: 0.6))

                                Text(state.name)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(state.isEnabled ? .white : Color(white: 0.45))
                                    .lineLimit(1)
                            }

                            HStack(spacing: 6) {
                                Text("IN \(state.channelIndex + 1)")
                                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                                    .foregroundStyle(abletonCyan)

                                if isSpeaking {
                                    Text("REC")
                                        .font(.system(size: 8, weight: .heavy, design: .monospaced))
                                        .foregroundStyle(.black)
                                        .padding(.horizontal, 4)
                                        .background(abletonRed)
                                        .cornerRadius(2)
                                }
                            }
                        }

                        if state.isEnabled {
                            AbletonVULevelMeter(level: model.running ? state.level : 0)
                                .frame(width: 44, height: 10)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(isSpeaking ? color.opacity(0.18) : abletonCard)
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(isSpeaking ? color : abletonBorder, lineWidth: isSpeaking ? 1.5 : 1)
                    )
                    .opacity(state.isEnabled ? 1.0 : 0.4)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .background(Color(red: 0.13, green: 0.13, blue: 0.13))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(abletonBorder), alignment: .bottom)
    }

    // MARK: - Live Transcript View

    private var transcriptView: some View {
        VStack(spacing: 0) {
            // Ableton Track Strip across top of transcript
            channelStrip

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(model.lines) { line in
                            transcriptLineRow(line: line)
                        }

                        // Real-Time Streaming Partials for Speaking Channels
                        ForEach(model.channelStates.filter { !$0.partial.isEmpty }) { state in
                            streamingPartialRow(state: state)
                        }

                        Color.clear.frame(height: 1).id("live")
                    }
                    .padding(16)
                }
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentSize.height - geometry.contentOffset.y - geometry.containerSize.height < 40
                } action: { _, near in
                    atLive = near
                }
                .onChange(of: model.lines.count) { _, _ in if atLive { proxy.scrollTo("live", anchor: .bottom) } }
                .overlay(alignment: .bottom) {
                    if !atLive {
                        Button {
                            proxy.scrollTo("live", anchor: .bottom)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.down")
                                Text("JUMP TO LIVE")
                            }
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(abletonMint)
                            .cornerRadius(20)
                            .shadow(color: abletonMint.opacity(0.4), radius: 6, x: 0, y: 2)
                        }
                        .buttonStyle(.plain)
                        .padding(16)
                    }
                }
            }
        }
    }

    private func transcriptLineRow(line: Line) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(Self.clock.string(from: line.time))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(white: 0.5))

            if let ch = line.channelName {
                let badgeColor = line.channelColorHex.flatMap { Color(hex: $0) } ?? abletonMint
                Text(ch.uppercased())
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(badgeColor)
                    .cornerRadius(3)
            }

            Text(line.text)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Color(white: 0.94))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(abletonCard.opacity(0.4))
        .cornerRadius(4)
    }

    private func streamingPartialRow(state: ChannelState) -> some View {
        let badgeColor = Color(hex: state.colorHex) ?? abletonMint

        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(Self.clock.string(from: state.partialTime))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(white: 0.5))

            HStack(spacing: 4) {
                Circle()
                    .fill(badgeColor)
                    .frame(width: 6, height: 6)
                Text(state.name.uppercased())
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(badgeColor)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(badgeColor.opacity(0.2))
            .cornerRadius(3)

            Text(state.partial)
                .font(.system(size: 16, weight: .medium))
                .italic()
                .foregroundStyle(Color(white: 0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(badgeColor.opacity(0.08))
        .cornerRadius(4)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(badgeColor.opacity(0.3), lineWidth: 1))
    }

    // MARK: - Ableton Status Bar

    private var statusBar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                Circle()
                    .fill(model.running ? abletonMint : Color(white: 0.4))
                    .frame(width: 7, height: 7)
                Text(model.status)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(white: 0.7))
                    .lineLimit(1)
            }

            Spacer()

            // Session Document Indicator
            HStack(spacing: 5) {
                Image(systemName: "doc.text")
                    .font(.system(size: 10))
                Text(model.documentDisplayName)
                    .lineLimit(1)
                if model.hasUnsavedChanges {
                    Text("•")
                        .foregroundStyle(abletonAmber)
                        .font(.system(size: 12, weight: .black))
                }
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(Color(white: 0.55))

            if let dev = model.device, dev.sampleRate > 0 {
                Text("\(String(format: "%.1f", dev.sampleRate / 1000.0)) kHz")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(white: 0.5))
            }

            if model.midiEngine.isConnected {
                HStack(spacing: 5) {
                    Circle().fill(abletonMint).frame(width: 6, height: 6)
                    Text("MIDI ONLINE")
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundStyle(abletonMint)
                }
            } else {
                HStack(spacing: 5) {
                    Circle().fill(Color(white: 0.3)).frame(width: 6, height: 6)
                    Text("MIDI OFFLINE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(white: 0.4))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(abletonSurface)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(abletonBorder), alignment: .top)
    }
}
