# LiveCue — Agent Handoff for Claude

> **Target Audience:** Claude (or any subsequent AI agent picking up LiveCue development).  
> **Last Updated:** 2026-10-07  
> **Current Version:** v0.4.0  
> **Build Status:** Clean compile (`swift build -Xswiftc -strict-concurrency=complete` ✅ [Swift 6 Mode, complete strict concurrency], `./build.sh` release bundle `dist/LiveCue.app` ✅)

---

## 1. Project Context & Objectives

**LiveCue** (formerly Talkback) is an open-source macOS alternative to **[ProdCom](https://prodcom.io)**, designed for live entertainment production, broadcast, theater, and corporate events.

### Primary Purpose:
1. Capture multi-channel audio from hardware interfaces or **Dante Virtual Soundcard (DVS)** (up to 6 concurrent channels).
2. Transcribe spoken speech in real-time (100% on-device, English only).
3. Detect spoken keywords/phrases (e.g., "standby", "go", "cue 5") and fire automated show control triggers (**Network MIDI**, **MIDI Show Control / MSC**, or visual alerts) over the LAN to consoles (QLab, ETC Eos, grandMA), with dynamic MIDI channel routing based on the audio channel origin.
4. Professional Ableton Live-inspired user interface with large high-contrast stage typography, Ableton dark palette, and segmented LED VU meters.
5. Session document management (Save, Save As, Open, Open Recent) in native `.livecue` format (JSON-based, interoperable with `.json`).

### Core Decisions Already Established:
- **macOS 26+ only:** Deliberately uses Apple's new `SpeechTranscriber` & `SpeechAnalyzer` (not legacy `SFSpeechRecognizer`). The new API is 3–4× more accurate, supports simultaneous multi-instance transcription, runs entirely on-device, and requires no internet during a show.
- **Pure Swift / SPM:** No Xcode project wrapper. Build via `swift build` or `./build.sh` (which generates `dist/LiveCue.app`).
- **No external third-party dependencies:** Uses native Apple frameworks (`AVFoundation`, `Speech`, `CoreAudio`, `CoreMIDI`, `Network`, `SwiftUI`, `UniformTypeIdentifiers`).

---

## 2. What Has Been Completed & Verified

| Component | Files | Description & Status |
|---|---|---|
| **Audio Capture & Hardware Query** | `AudioCapture.swift`, `AudioDevices.swift` | Enumerates CoreAudio devices displaying exact input & output channel counts and sample rates (e.g. `Scarlett 18i20 (8 In / 20 Out • 48.0 kHz)`). Multi-channel tap feeds up to 6 `ChannelFeeder` instances concurrently. Includes `AudioDeviceMonitor` for hot-plug/unplug auto-reconnect and clock recovery. |
| **Speech Engine** | `Transcriber.swift` | Feeds audio into Apple's `SpeechAnalyzer` / `SpeechTranscriber`. Streams volatile partial transcriptions and settled final lines. Uses thread-safe `AudioSink` crossing realtime audio taps into `AsyncStream`. |
| **Network MIDI Engine** | `MIDIEngine.swift` | Manages `MIDINetworkSession` over standard UDP port 5004 (RTP-MIDI / Apple-MIDI). Auto-discovers Bonjour devices (`_apple-midi._udp`). Supports manual IP host:port entries. Sends Universal MIDI Packets (UMP) for Note On/Off, CC, Program Change, and SysEx for MSC (`GO`, `STOP`, `RESUME`, `FIRE`). |
| **Keyword Trigger System** | `KeywordRule.swift`, `KeywordMatcher.swift` | Match modes: `.exact`, `.contains`, `.prefix`. Case-insensitive/sensitive. Per-rule cooldown timer. **Dynamic MIDI channel routing**: outgoing MIDI channel can dynamically follow the spoken audio channel input (Input 1 -> MIDI Ch 1, Input 2 -> MIDI Ch 2, etc.) or use a static MIDI channel. |
| **Session Document System** | `LiveCueSession.swift`, `Model.swift`, `Info.plist` | Microsoft Word style document management. Save (`⌘S`), Save As (`⇧⌘S`), Open (`⌘O`), and Open Recent submenu. Tracks dirty state (`hasUnsavedChanges`), registered `.livecue` document type (`local.livecue.session`), Finder file double-click `.onOpenURL` handler. |
| **App ViewModel & Wiring** | `Model.swift` | Orchestrates capture, transcribers, MIDI engine, rule matching, trigger dispatch, hot-plug recovery, session persistence, and export. Enforces maximum 6 concurrent channels limit. |
| **Ableton Live UI Suite** | `ContentView.swift`, `ChannelsManagerView.swift`, `KeywordRulesView.swift`, `MIDISettingsView.swift`, `TriggerLogView.swift`, `ExportSheet.swift` | Complete Ableton Live 11/12 dark graphite styling. Ableton transport bar with session menu & quick Save button, audio device menu showing In/Out channels, segmented LED VU meters, large 16pt stage transcript typography, Ableton Session-view track strips, track activator buttons, and 10 Ableton track color swatches. |
| **Persistence** | `ConfigManager.swift` | Auto-saves and loads user preferences, manual destinations, selected connections, and channel setups to `~/Library/Application Support/LiveCue/config.json`. |
| **Transcript Export** | `TranscriptExporter.swift`, `ExportSheet.swift` | Exports live transcript to **Plain Text (.txt)**, **CSV (.csv)**, or **SubRip Subtitles (.srt)** with copy-to-clipboard and `NSSavePanel` file saving. |
| **Branding & Packaging** | `Info.plist`, `AppIcon.icns`, `build.sh` | LiveCue branding, custom app logo embedded as multi-resolution `AppIcon.icns`, ad-hoc signed into `dist/LiveCue.app`. Obsolete Talkback bundle removed. |
| **Permissions & Config** | `Info.plist` | Entitlements configured for Microphone, Speech Recognition, Local Network access, Bonjour service `_apple-midi._udp`, and `.livecue` document types. |

---

## 3. Codebase File Map

```
talkback/
├── Package.swift                  # Swift package manifest (macOS 26, Swift 6 mode, target: LiveCue)
├── Info.plist                     # Mic, speech, network permissions & .livecue document declarations
├── AppIcon.icns                   # LiveCue multi-resolution app icon (16x16 to 1024x1024)
├── build.sh                       # Production release build script (outputs dist/LiveCue.app)
├── dist/                          # Compiled & ad-hoc signed .app bundle
│   └── LiveCue.app
├── README.md                      # Primary project readme & show-control quickstart
├── docs/
│   ├── ARCHITECTURE.md            # Comprehensive architectural roadmap & notes
│   ├── HANDOFF_FOR_CLAUDE.md      # This file
│   ├── PRODCOM_ANALYSIS.md        # Feature comparison with ProdCom
│   └── MIDI_OSC_REFERENCE.md      # CoreMIDI, RTP-MIDI, UMP, MSC, and OSC technical specs
└── Sources/Talkback/
    ├── main.swift                 # Entry point (SwiftUI App with menu commands or CLI --file mode)
    ├── LiveCueSession.swift       # Document data model (lines, channels, rules, trigger logs)
    ├── ContentView.swift          # Main window layout, transport bar, segmented tabs, status bar
    ├── Model.swift                # Main Observable orchestrator (multi-channel, MIDI, rules, sessions)
    ├── Transcriber.swift          # SpeechTranscriber wrapper
    ├── AudioCapture.swift         # Multi-channel AVAudioEngine tap & ChannelFeeder
    ├── AudioDevices.swift         # CoreAudio input device query
    ├── Line.swift                 # Transcript line model (timestamps, text, channel metadata)
    ├── ChannelState.swift         # Real-time channel runtime state model
    ├── ChannelsManagerView.swift  # Channel configuration & level meters UI
    ├── MIDIEngine.swift           # CoreMIDI MIDINetworkSession, Bonjour discovery, UMP/SysEx
    ├── MIDISettingsView.swift     # Destination manager & MIDI testing UI
    ├── KeywordRule.swift          # Rule model & TriggerAction enum (with channel scoping)
    ├── KeywordMatcher.swift       # Text matching engine with cooldown
    ├── KeywordRulesView.swift     # Rule editor sheet & list UI
    ├── TriggerLogItem.swift       # Activity log entry model
    ├── TriggerLogView.swift       # History of fired triggers
    ├── TranscriptExporter.swift   # Exporter to TXT, CSV, SRT
    ├── ExportSheet.swift          # Export preview & save dialog UI
    └── ConfigManager.swift        # Application Support JSON persistence
```

---

## 4. Development Cheat Sheet

```bash
# 1. Compile with Swift 6 strict concurrency
swift build -Xswiftc -strict-concurrency=complete

# 2. Run the app directly
swift run LiveCue

# 3. Test offline with an audio file (bypasses live mic)
swift run LiveCue --file /path/to/test.wav [channelIndex]

# 4. Build and sign release .app bundle with icon
./build.sh

# 5. Launch the compiled release app
open dist/LiveCue.app
```
