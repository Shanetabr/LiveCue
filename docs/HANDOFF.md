# Talkback — Agent Handoff Document (Cycle 2)

**Date:** 2026-10-07  
**Status:** Build passing (`swift build` ✅, `./build.sh` dist app bundle ✅)  
**Version:** v0.2.0 (Network MIDI, Keyword Trigger Engine, Configuration Persistence, Export & Full UI)

---

## 1. What Was Done in This Cycle

### CoreMIDI & Network MIDI Engine
- **File:** `Sources/Talkback/MIDIEngine.swift`
- Manages native `MIDINetworkSession` over standard UDP port `5004` (RTP-MIDI / Apple-MIDI).
- Auto-discovers local show control machines via Bonjour (`_apple-midi._udp`).
- Supports manual IP destination entry (e.g., `192.168.1.50:5004`).
- Implemented **Universal MIDI Packet (UMP)** transmission (`sendNoteOn`, `sendNoteOff`, `sendControlChange`, `sendProgramChange`).
- Implemented **MIDI Show Control (MSC)** RP-002 SysEx generation (`sendMSC`) supporting `GO`, `STOP`, `RESUME`, and `FIRE` with optional Cue Number and Cue List.
- Updated `Info.plist` with `NSLocalNetworkUsageDescription` and `NSBonjourServices` (`_apple-midi._udp`).

### Keyword Trigger System
- **Files:** `Sources/Talkback/KeywordRule.swift`, `Sources/Talkback/KeywordMatcher.swift`
- Configurable rules with `keyword`, `matchMode` (`.exact`, `.contains`, `.prefix`), `caseSensitive`, and `cooldownSeconds`.
- Trigger Actions: Note On, Note Off, CC, Program Change, MSC SysEx, and `flashWindow` (Visual Alert).
- Integrated into `Model.swift`: automatically scans final speech recognition results and dispatches actions.

### UI Suite & Integration
- **`ContentView.swift`**: Segmented tab control (`Transcript`, `Rules`, `Network MIDI`, `Activity Log`), trigger activity banner, and fullscreen visual alert flash overlay.
- **`KeywordRulesView.swift`**: Full rule management interface (toggle switch, edit sheet, test button, delete, default rule creation).
- **`MIDISettingsView.swift`**: Live connection indicator, discovered Bonjour hosts, manual host addition, test triggers.
- **`TriggerLogView.swift`**: History of fired triggers with timestamps, rule names, and action details.
- **`ExportSheet.swift`**: Preview and export to **Plain Text (.txt)**, **CSV (.csv)**, and **SubRip Subtitles (.srt)** with copy-to-clipboard and file save dialog.

### Persistence & Configuration
- **File:** `Sources/Talkback/ConfigManager.swift`
- Saves and loads rules, manual MIDI endpoints, selected endpoints, and channel setups to `~/Library/Application Support/Talkback/config.json`.

### Documentation
- **`README.md`**: Complete user and developer documentation covering architecture, setup for QLab and lighting desks (ETC Eos, grandMA), CLI usage, and building.
- **`docs/ARCHITECTURE.md`**: Updated with completed milestones and codebase layout.

---

## 2. Current State of the Codebase

All components compile cleanly with both debug (`swift build`) and release (`./build.sh`) targets.

```
Talkback/
├── dist/Talkback.app          # Signed release application bundle
├── README.md                  # Comprehensive documentation
├── docs/
│   ├── ARCHITECTURE.md        # Full architecture & roadmap
│   ├── HANDOFF.md             # This handoff file
│   ├── PRODCOM_ANALYSIS.md    # ProdCom feature comparison
│   └── MIDI_OSC_REFERENCE.md  # Protocol reference
└── Sources/Talkback/
    ├── main.swift
    ├── ContentView.swift
    ├── Model.swift
    ├── Transcriber.swift
    ├── AudioCapture.swift
    ├── AudioDevices.swift
    ├── Line.swift
    ├── MIDIEngine.swift
    ├── MIDISettingsView.swift
    ├── KeywordRule.swift
    ├── KeywordMatcher.swift
    ├── KeywordRulesView.swift
    ├── TriggerLogItem.swift
    ├── TriggerLogView.swift
    ├── TranscriptExporter.swift
    ├── ExportSheet.swift
    └── ConfigManager.swift
```

---

## 3. Next Steps on the Roadmap (For the Next Agent)

1. **Phase 1 & 2: Multi-Channel Transcription**
   - Currently, transcription runs on one chosen audio input channel at a time.
   - To achieve multi-channel parity with ProdCom (e.g. FOH, Monitors, Stage Manager simultaneously):
     - Refactor `AudioCapture.swift` to allow one `AVAudioEngine` tap to feed multiple `ChannelFeeder` instances (one per channel index).
     - Instantiate a `Transcriber` per active channel.
     - Interleave transcripts from multiple channels in `ContentView.swift` using color tags from `ChannelConfig`.

2. **Phase 8: Hardware Polish & Error Recovery**
   - Add CoreAudio property listener for audio device connect/disconnect (`kAudioHardwarePropertyDevices`).
   - Implement transcriber auto-restart on engine stall or device clock changes.
   - Migrate `Model.swift` to modern Swift Observation (`@Observable`) and Swift 6 Sendable conformance.
