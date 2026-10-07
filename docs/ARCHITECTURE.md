# Talkback — Architecture & Agent Handoff Document

> **Purpose:** This is the primary context document for any AI agent (Gemini, Claude, etc.)
> picking up work on Talkback. It describes the current codebase, what's been decided,
> what needs to be built, and how to proceed.
>
> **Last updated:** 2026-10-07 (after initial assessment, v0.1.0)

---

## Project Overview

**Talkback** is an open-source macOS application that provides real-time, multi-channel
speech-to-text transcription with MIDI/OSC show control output — an open-source alternative
to [ProdCom](https://prodcom.io).

**Target users:** Live sound engineers (FOH/MON), show callers, tour managers, stage managers,
lighting/video operators — anyone in live production who needs to read talkback/comms
visually and trigger automated cues from spoken keywords.

**Repository:** https://github.com/Shanetabr/talkback

---

## Key Architectural Decisions (Already Made)

1. **macOS 26+ only** — Uses Apple's new `SpeechTranscriber` / `SpeechAnalyzer` APIs
   (not the legacy `SFSpeechRecognizer`). This was a deliberate choice because:
   - Multi-channel requires multiple simultaneous transcriber instances — the legacy API crashes
   - 3–4× better accuracy and lower latency
   - 100% on-device (privacy, no internet dependency during shows)
   - Target users run current hardware with DANTE infrastructure

2. **Swift Package Manager** — No Xcode project, just `Package.swift`. Build with `swift build`
   or `./build.sh` for the `.app` bundle.

3. **Swift 6 toolchain, Swift 5 language mode** — Avoids strict concurrency for now but
   will need migration eventually.

4. **English only** — Single locale (`en-US`). No plans for multi-language.

5. **No external dependencies** — Pure Apple frameworks (AVFoundation, Speech, CoreAudio, CoreMIDI).

---

## Current Codebase (v0.1.0)

```
talkback/
├── Package.swift              # SPM manifest (macOS 26.0, Swift 6, language mode v5)
├── build.sh                   # Builds dist/Talkback.app, ad-hoc signed
├── Info.plist                 # Bundle config (mic, speech, network permissions)
├── README.md                  # Complete project documentation and guide
├── .gitignore
├── docs/                      # Reference documents
│   ├── ARCHITECTURE.md        # This file
│   ├── PRODCOM_ANALYSIS.md    # Full ProdCom feature inventory
│   └── MIDI_OSC_REFERENCE.md  # Protocol specs & implementation guide
└── Sources/Talkback/
    ├── main.swift             # Entry point — SwiftUI app or CLI file-check mode
    ├── ContentView.swift      # Main UI container — segmented tabs, banner, flash alert
    ├── Model.swift            # Core orchestrator — audio capture, transcribers, MIDI, rules
    ├── Transcriber.swift      # Apple SpeechTranscriber wrapper
    ├── AudioCapture.swift     # Multi-channel AVAudioEngine audio tap & ChannelFeeder
    ├── AudioDevices.swift     # CoreAudio input device enumeration
    ├── Line.swift             # Transcript line model with channel metadata
    ├── ChannelState.swift     # Real-time channel runtime state model
    ├── ChannelsManagerView.swift # UI for multi-channel input management
    ├── MIDIEngine.swift       # CoreMIDI network session, Bonjour discovery, UMP & SysEx send
    ├── MIDISettingsView.swift # UI for network MIDI host management and testing
    ├── KeywordRule.swift      # Keyword trigger rules & TriggerAction model
    ├── KeywordMatcher.swift   # Real-time keyword scanning with cooldown
    ├── KeywordRulesView.swift # UI for adding, editing, toggling, and testing rules
    ├── TriggerLogItem.swift   # Activity log entry model
    ├── TriggerLogView.swift   # UI for reviewing past fired triggers
    ├── TranscriptExporter.swift # Exporter for TXT, CSV, and SRT
    ├── ExportSheet.swift      # UI for previewing, copying, and saving transcripts
    └── ConfigManager.swift    # JSON persistence in Application Support
```

### How the Current Code Works

```
┌─────────────┐    ┌──────────────┐    ┌──────────────┐    ┌───────────┐
│ AudioDevices│───▶│ AudioCapture │───▶│ ChannelFeeder│───▶│Transcriber│
│ (enumerate) │    │ (AVAudioEngine)   │ (mono extract│    │ (Speech   │
│             │    │              │    │  + resample) │    │  Analyzer)│
└─────────────┘    └──────────────┘    └──────────────┘    └─────┬─────┘
                                                                  │
                                                          partial/final text
                                                                  │
                                                           ┌──────▼──────┐
                                                           │    Model    │
                                                           │ (ViewModel) │
                                                           └──────┬──────┘
                                                                  │
                                                           ┌──────▼──────┐
                                                           │ ContentView │
                                                           │ (SwiftUI)   │
                                                           └─────────────┘
```

### Known Bugs in Current Code

| Bug | File | Line(s) | Description |
|-----|------|---------|-------------|
| Old observation pattern | Model.swift | All | Uses `ObservableObject`/`@StateObject` instead of `@Observable`/`@State` |
| Channel clamp race | Model.swift | 39 | Doesn't stop running capture if selected channel becomes invalid |
| No device hot-plug | Model.swift | 30-31 | Only scans on init or manual refresh, no CoreAudio property listener |
| Excessive main thread hops | Model.swift | 81 | `Task { @MainActor in ... }` from audio callbacks creates many micro-tasks |
| Missing Sendable | AudioCapture.swift | All | Not `Sendable`-safe (ok in Swift 5 mode, problematic in Swift 6) |
| Missing network plist keys | Info.plist | — | No `NSLocalNetworkUsageDescription` or `NSBonjourServices` |

---

## Feature Roadmap

### Phase 1: Multi-Channel Transcription Engine
**Goal:** Transcribe N audio channels simultaneously, each with its own `SpeechTranscriber`.

- [x] Create a `ChannelConfig` model (id, name, color, channel index, isEnabled)
- [x] Create multi-channel tap in `AudioCapture.swift` feeding N `ChannelFeeder` instances from single `AVAudioEngine` tap
- [x] Each `Channel` gets its own independent `Transcriber` instance
- [x] Interleaved transcript tagging each `Line` with channel ID, name, and color
- [x] Update `Model.swift` to manage multi-channel state and per-channel level meters
- [x] DANTE Virtual Soundcard and multi-channel hardware interface support

### Phase 2: Multi-Channel UI
**Goal:** Chat-style interleaved transcript view with color-coded channels.

- [x] Channel Strip in transcript view with name, input number, color dot, and live level meters
- [x] `ChannelsManagerView`: Add/remove/edit/recolor channels and assign hardware input numbers (1..64)
- [x] Main area: interleaved transcript with color-coded channel pills
- [x] Live partial transcription tracking for each channel speaking
- [x] Channel filter scoping for keyword rules
- [x] "Jump to live" auto-scroll

### Phase 3: MIDI Output Engine
**Goal:** Send MIDI messages over the network via CoreMIDI.

- [x] Create `MIDIEngine` class wrapping `MIDINetworkSession`
- [x] Support message types: Note On/Off, CC, Program Change, MSC (SysEx)
- [x] Bonjour discovery of MIDI destinations (`_apple-midi._udp`)
- [x] UI: MIDI destination picker (discovered + manual IP entry)
- [x] UI: Test button to send a test message
- [x] Add `NSLocalNetworkUsageDescription` and `NSBonjourServices` to Info.plist
- [x] See `docs/MIDI_OSC_REFERENCE.md` for byte-level specs and Swift code

### Phase 4: Keyword Detection & Trigger System
**Goal:** Define keyword rules that fire MIDI/OSC when spoken.

- [x] Create `KeywordRule` model (id, keyword/phrase, channel filter, action)
- [x] Create `KeywordMatcher` that scans incoming transcript text
- [x] Matching modes: exact match, substring/contains, case-insensitive
- [x] Actions: send MIDI message (Note, CC, Program Change, MSC), visual alert (flash window)
- [x] Cooldown timer to prevent repeated triggers from transcription jitter

### Phase 5: Keyword Rule Editor UI
**Goal:** Visual editor for keyword→action mappings.

- [x] List of rules with enable/disable toggle
- [x] Rule editor: keyword field, channel filter, action type picker
- [x] MIDI action config: message type, channel, note/CC, velocity/value
- [x] MSC action config: device ID, command format, command, cue number, cue list
- [x] Visual alert action config (flash window)
- [x] Test button per rule

### Phase 6: Transcript Export
**Goal:** Save transcripts to file.

- [x] Export as plain text (.txt) with timestamps and channel labels
- [x] Export as CSV (timestamp, channel, text)
- [x] Export as SRT (subtitle format)
- [x] Copy to clipboard and Save File dialog

### Phase 7: Persistent Configuration
**Goal:** Save and load all settings.

- [x] Channel configuration (names, colors, device mappings)
- [x] Keyword rules and MIDI destinations
- [x] Save as JSON file (`~/Library/Application Support/Talkback/config.json`)
- [x] Auto-save on change, load on launch

### Phase 8: Polish & Error Recovery
**Goal:** Production-ready reliability.

- [x] CoreAudio property listener for device hot-plug/unplug (`AudioDeviceMonitor`)
- [x] Auto-reconnect transcriber on failure and sample rate / clock shift (`onConfigurationChange`)
- [x] Graceful handling of DANTE Virtual Soundcard start/stop (auto disconnect pause and auto-resume)
- [x] Migrate to `@Observable` / `@State` (modern Observation framework)
- [x] Swift 6 strict concurrency compliance (`.swiftLanguageMode(.v6)`, zero warnings)
- [x] README with build instructions, screenshots, DANTE setup guide

---

## Implementation Notes for Agents

### Building the Project
```bash
cd /path/to/talkback
swift build           # Debug build
swift build -c release  # Release build
./build.sh            # Build .app bundle in dist/
```

**Requires:** Xcode 26+ (macOS 26 SDK), Apple Silicon Mac recommended.

### Testing Audio
- The `--file` CLI flag transcribes audio files: `./Talkback --file speech.wav [channel]`
- Use this for testing transcription without a live mic
- DANTE Virtual Soundcard appears as a standard CoreAudio device — enumerate with `AudioDevices.inputs()`

### Key APIs to Know
- **SpeechTranscriber** / **SpeechAnalyzer** — macOS 26+ on-device speech (see `Transcriber.swift`)
- **AVAudioEngine** — Audio capture with taps (see `AudioCapture.swift`)
- **CoreAudio** — Device enumeration, property listeners (see `AudioDevices.swift`)
- **CoreMIDI** — `MIDINetworkSession`, `MIDINetworkHost`, `MIDISend` (see `docs/MIDI_OSC_REFERENCE.md`)
- **Network.framework** — `NWBrowser` for Bonjour discovery

### Related Documents
- [PRODCOM_ANALYSIS.md](PRODCOM_ANALYSIS.md) — Full ProdCom feature inventory and competitive analysis
- [MIDI_OSC_REFERENCE.md](MIDI_OSC_REFERENCE.md) — Byte-level MIDI/OSC specs, CoreMIDI Swift code, QLab/Eos/grandMA integration

### Questions Still Open (Need User Input)
1. **Channel count target** — How many simultaneous channels? (ProdCom handles 4–8+)
2. **MIDI message types needed** — Note On/Off? CC? MSC? All of the above?
3. **Keyword matching complexity** — Exact only? Substring? Fuzzy/phonetic?
4. **Priority order** — Multi-channel first or MIDI output first?
5. **OSC support** — Needed alongside MIDI, or MIDI sufficient?
6. **Config format** — JSON file vs macOS UserDefaults vs plist?

---

## Git Conventions

- **Branch:** `main`
- **Current tag:** `v0.1.0`
- **Commit style:** Descriptive messages prefixed with phase (e.g., "Phase 1: multi-channel transcription engine")
- **No CI/CD yet** — manual builds only
