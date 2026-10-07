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

struct KeywordRulesView: View {
    var model: Model
    @State private var showingAddSheet = false
    @State private var editingRule: KeywordRule?

    var body: some View {
        VStack(spacing: 0) {
            // Ableton Header bar
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("KEYWORD & SHOW CONTROL RULES")
                        .font(.system(size: 15, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white)
                    Text("Fire Network MIDI cues and visual alerts when spoken words are recognized")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showingAddSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("NEW RULE")
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

            if model.keywordMatcher.rules.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "bolt.slash.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(abletonAmber)
                    Text("NO KEYWORD RULES DEFINED")
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                    Text("Add rules to trigger network MIDI cues (Note, CC, Program Change, MSC) or screen flashes when specific cues are spoken on stage or comms.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                    Button("LOAD DEFAULT SHOW RULES") {
                        model.keywordMatcher.rules = AppConfig.default.rules
                        model.saveConfig()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(abletonMint)
                    .foregroundStyle(.black)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(model.keywordMatcher.rules) { rule in
                            ruleRow(rule)
                        }
                    }
                    .padding(14)
                }
            }
        }
        .background(abletonBg)
        .sheet(isPresented: $showingAddSheet) {
            RuleEditSheet(channels: model.channels, onSave: { newRule in
                model.keywordMatcher.rules.append(newRule)
                model.saveConfig()
                showingAddSheet = false
            }, onCancel: {
                showingAddSheet = false
            })
        }
        .sheet(item: $editingRule) { rule in
            RuleEditSheet(initialRule: rule, channels: model.channels, onSave: { updated in
                if let idx = model.keywordMatcher.rules.firstIndex(where: { $0.id == updated.id }) {
                    model.keywordMatcher.rules[idx] = updated
                    model.saveConfig()
                }
                editingRule = nil
            }, onCancel: {
                editingRule = nil
            })
        }
    }

    private func ruleRow(_ rule: KeywordRule) -> some View {
        HStack(spacing: 14) {
            // Ableton-style Toggle Button
            Button {
                if let idx = model.keywordMatcher.rules.firstIndex(where: { $0.id == rule.id }) {
                    model.keywordMatcher.rules[idx].enabled.toggle()
                    model.saveConfig()
                }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(rule.enabled ? abletonYellow : Color(white: 0.15))
                        .frame(width: 26, height: 26)
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(rule.enabled ? .black : Color(white: 0.45))
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("\"\(rule.keyword)\"")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(rule.enabled ? .white : Color(white: 0.45))

                    Text(rule.matchMode.rawValue.uppercased())
                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.35))
                        .cornerRadius(3)

                    // Channel Filter Tag
                    if let filterID = rule.channelFilter,
                       let ch = model.channels.first(where: { $0.id == filterID }) {
                        let chColor = Color(hex: ch.colorHex) ?? .gray
                        Text(ch.name.uppercased())
                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(chColor)
                            .cornerRadius(3)
                    } else {
                        Text("ALL TRACKS")
                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .foregroundStyle(Color(white: 0.75))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color(white: 0.16))
                            .cornerRadius(3)
                    }

                    if rule.followAudioChannel {
                        Text("DYNAMIC MIDI CH")
                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(abletonMint)
                            .cornerRadius(3)
                    }

                    if rule.caseSensitive {
                        Text("Aa")
                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.35))
                            .cornerRadius(3)
                    }

                    Text("\(String(format: "%.1fs", rule.cooldownSeconds)) cd")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color(white: 0.55))
                }

                Text(actionDescription(rule.action, followAudioCh: rule.followAudioChannel))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(abletonAmber)
            }

            Spacer()

            // Ableton Test Button
            Button {
                model.testRule(rule)
            } label: {
                Text("TEST")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(white: 0.22))
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)

            // Edit
            Button {
                editingRule = rule
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(white: 0.7))
                    .frame(width: 28, height: 28)
                    .background(Color(white: 0.16))
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)

            // Delete
            Button {
                if let idx = model.keywordMatcher.rules.firstIndex(where: { $0.id == rule.id }) {
                    model.keywordMatcher.rules.remove(at: idx)
                    model.saveConfig()
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.red.opacity(0.85))
                    .frame(width: 28, height: 28)
                    .background(Color(white: 0.16))
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(abletonCard)
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(abletonBorder, lineWidth: 1))
        .opacity(rule.enabled ? 1.0 : 0.5)
    }

    private func actionDescription(_ action: TriggerAction, followAudioCh: Bool) -> String {
        let chSuffix = followAudioCh ? " [MIDI Ch follows spoken audio input]" : ""
        switch action {
        case .midiNoteOn(let ch, let note, let vel):
            return "MIDI Note On: Ch \(ch + 1), Note \(note), Vel \(vel)\(chSuffix)"
        case .midiNoteOff(let ch, let note, let vel):
            return "MIDI Note Off: Ch \(ch + 1), Note \(note), Vel \(vel)\(chSuffix)"
        case .midiCC(let ch, let ctrl, let val):
            return "MIDI CC: Ch \(ch + 1), CC \(ctrl), Val \(val)\(chSuffix)"
        case .midiProgramChange(let ch, let prog):
            return "MIDI Program Change: Ch \(ch + 1), Prog \(prog)\(chSuffix)"
        case .midiMSC(let dev, let fmt, let cmd, let cue, let list):
            let c = cue ?? "-"
            let l = list.map { "/\($0)" } ?? ""
            return "MSC: Dev \(dev), Fmt \(fmt), Cmd \(cmd), Cue \(c)\(l)"
        case .flashWindow:
            return "Visual Alert (Flash Screen)"
        }
    }
}

// MARK: - Rule Edit Sheet

struct RuleEditSheet: View {
    var initialRule: KeywordRule?
    var channels: [ChannelConfig]
    var onSave: (KeywordRule) -> Void
    var onCancel: () -> Void

    @State private var keyword: String = ""
    @State private var matchMode: MatchMode = .contains
    @State private var caseSensitive: Bool = false
    @State private var cooldownSeconds: Double = 1.0
    @State private var selectedChannelFilter: UUID? = nil
    @State private var followAudioChannel: Bool = false

    enum ActionType: String, CaseIterable, Identifiable {
        case noteOn = "MIDI Note On"
        case noteOff = "MIDI Note Off"
        case cc = "MIDI Control Change"
        case programChange = "MIDI Program Change"
        case msc = "MIDI Show Control (MSC)"
        case flash = "Visual Alert"

        var id: String { rawValue }
    }

    @State private var selectedActionType: ActionType = .noteOn
    @State private var midiChannel: Int = 1
    @State private var noteNumber: Int = 60
    @State private var velocity: Int = 127
    @State private var controllerNumber: Int = 1
    @State private var ccValue: Int = 127
    @State private var programNumber: Int = 1
    @State private var mscDeviceID: Int = 1
    @State private var mscCommandFormat: Int = 1
    @State private var mscCommand: Int = 1
    @State private var mscCueNumber: String = "1"
    @State private var mscCueList: String = ""

    init(
        initialRule: KeywordRule? = nil,
        channels: [ChannelConfig] = [],
        onSave: @escaping (KeywordRule) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.initialRule = initialRule
        self.channels = channels
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(initialRule == nil ? "NEW KEYWORD RULE" : "EDIT KEYWORD RULE")
                        .font(.system(size: 15, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white)
                    Text("Map spoken cues to network MIDI or visual triggers")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Form {
                Section("Keyword Match Configuration") {
                    TextField("Spoken keyword or phrase (e.g. 'go', 'cue 1', 'standby')", text: $keyword)

                    Picker("Match Mode", selection: $matchMode) {
                        Text("Contains phrase anywhere").tag(MatchMode.contains)
                        Text("Exact line match").tag(MatchMode.exact)
                        Text("Starts with keyword").tag(MatchMode.prefix)
                    }

                    Picker("Channel Filter", selection: $selectedChannelFilter) {
                        Text("All Channels (Universal)").tag(UUID?.none)
                        ForEach(channels) { ch in
                            Text(ch.name).tag(UUID?.some(ch.id))
                        }
                    }

                    Toggle("Case sensitive match", isOn: $caseSensitive)

                    HStack {
                        Text("Cooldown (seconds):")
                        Slider(value: $cooldownSeconds, in: 0.2...10.0, step: 0.1)
                        Text(String(format: "%.1fs", cooldownSeconds))
                            .monospacedDigit()
                            .frame(width: 45)
                    }
                }

                Section("Trigger Action") {
                    Picker("Action Type", selection: $selectedActionType) {
                        ForEach(ActionType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }

                    switch selectedActionType {
                    case .noteOn, .noteOff:
                        Toggle("Dynamic: Outgoing MIDI Channel matches spoken audio track", isOn: $followAudioChannel)
                            .font(.system(size: 12))

                        if !followAudioChannel {
                            Stepper("Static MIDI Channel: \(midiChannel)", value: $midiChannel, in: 1...16)
                        }
                        Stepper("Note Number: \(noteNumber)", value: $noteNumber, in: 0...127)
                        Stepper("Velocity: \(velocity)", value: $velocity, in: 0...127)

                    case .cc:
                        Toggle("Dynamic: Outgoing MIDI Channel matches spoken audio track", isOn: $followAudioChannel)
                            .font(.system(size: 12))

                        if !followAudioChannel {
                            Stepper("Static MIDI Channel: \(midiChannel)", value: $midiChannel, in: 1...16)
                        }
                        Stepper("Controller Number: \(controllerNumber)", value: $controllerNumber, in: 0...127)
                        Stepper("Value: \(ccValue)", value: $ccValue, in: 0...127)

                    case .programChange:
                        Toggle("Dynamic: Outgoing MIDI Channel matches spoken audio track", isOn: $followAudioChannel)
                            .font(.system(size: 12))

                        if !followAudioChannel {
                            Stepper("Static MIDI Channel: \(midiChannel)", value: $midiChannel, in: 1...16)
                        }
                        Stepper("Program Number: \(programNumber)", value: $programNumber, in: 0...127)

                    case .msc:
                        Stepper("Device ID (0-127): \(mscDeviceID)", value: $mscDeviceID, in: 0...127)
                        Picker("Command", selection: $mscCommand) {
                            Text("GO (0x01)").tag(1)
                            Text("STOP (0x02)").tag(2)
                            Text("RESUME (0x03)").tag(3)
                            Text("FIRE (0x0B)").tag(11)
                        }
                        TextField("Cue Number (optional, e.g. '1', '10.5')", text: $mscCueNumber)
                        TextField("Cue List (optional)", text: $mscCueList)

                    case .flash:
                        Text("Flashes a high-visibility alert border across the Talkback window.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save Rule") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .tint(abletonMint)
                .foregroundStyle(.black)
                .keyboardShortcut(.defaultAction)
                .disabled(keyword.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .padding(16)
        .frame(minWidth: 500, minHeight: 520)
        .background(abletonBg)
        .onAppear {
            if let r = initialRule {
                keyword = r.keyword
                matchMode = r.matchMode
                caseSensitive = r.caseSensitive
                cooldownSeconds = r.cooldownSeconds
                selectedChannelFilter = r.channelFilter
                followAudioChannel = r.followAudioChannel
                switch r.action {
                case .midiNoteOn(let ch, let n, let v):
                    selectedActionType = .noteOn
                    midiChannel = Int(ch) + 1
                    noteNumber = Int(n)
                    velocity = Int(v)
                case .midiNoteOff(let ch, let n, let v):
                    selectedActionType = .noteOff
                    midiChannel = Int(ch) + 1
                    noteNumber = Int(n)
                    velocity = Int(v)
                case .midiCC(let ch, let c, let val):
                    selectedActionType = .cc
                    midiChannel = Int(ch) + 1
                    controllerNumber = Int(c)
                    ccValue = Int(val)
                case .midiProgramChange(let ch, let p):
                    selectedActionType = .programChange
                    midiChannel = Int(ch) + 1
                    programNumber = Int(p)
                case .midiMSC(let dev, let fmt, let cmd, let cue, let list):
                    selectedActionType = .msc
                    mscDeviceID = Int(dev)
                    mscCommandFormat = Int(fmt)
                    mscCommand = Int(cmd)
                    mscCueNumber = cue ?? ""
                    mscCueList = list ?? ""
                case .flashWindow:
                    selectedActionType = .flash
                }
            }
        }
    }

    private func save() {
        let action: TriggerAction
        switch selectedActionType {
        case .noteOn:
            action = .midiNoteOn(channel: UInt8(midiChannel - 1), note: UInt8(noteNumber), velocity: UInt8(velocity))
        case .noteOff:
            action = .midiNoteOff(channel: UInt8(midiChannel - 1), note: UInt8(noteNumber), velocity: UInt8(velocity))
        case .cc:
            action = .midiCC(channel: UInt8(midiChannel - 1), controller: UInt8(controllerNumber), value: UInt8(ccValue))
        case .programChange:
            action = .midiProgramChange(channel: UInt8(midiChannel - 1), program: UInt8(programNumber))
        case .msc:
            let cue = mscCueNumber.isEmpty ? nil : mscCueNumber
            let list = mscCueList.isEmpty ? nil : mscCueList
            action = .midiMSC(deviceID: UInt8(mscDeviceID), commandFormat: UInt8(mscCommandFormat), command: UInt8(mscCommand), cueNumber: cue, cueList: list)
        case .flash:
            action = .flashWindow
        }

        let rule = KeywordRule(
            id: initialRule?.id ?? UUID(),
            keyword: keyword.trimmingCharacters(in: .whitespaces),
            enabled: initialRule?.enabled ?? true,
            caseSensitive: caseSensitive,
            matchMode: matchMode,
            action: action,
            cooldownSeconds: cooldownSeconds,
            channelFilter: selectedChannelFilter,
            followAudioChannel: followAudioChannel
        )
        onSave(rule)
    }
}
