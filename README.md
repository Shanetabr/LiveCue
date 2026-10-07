# LiveCue

**An open-source ProdCom alternative for macOS.**

LiveCue is a real-time speech-to-text transcription and show-control automation application designed for live entertainment production, broadcast, theater, and corporate events. It listens to multi-channel audio feeds (from USB/Thunderbolt interfaces or **Dante Virtual Soundcard**) and triggers network MIDI cues (to QLab, ETC Eos, grandMA, etc.) based on spoken keywords and phrases.

---

## Features

- 🎙️ **On-Device Live Speech Transcription**
  - Powered by Apple's macOS 26+ `SpeechTranscriber` and `SpeechAnalyzer` framework.
  - 100% on-device processing — no cloud dependencies, zero audio leaves the machine, zero internet required during showtime.
  - Low-latency streaming recognition with instant volatile partials and settled final lines.

- 🎛️ **Simultaneous Multi-Channel Transcription**
  - Transcribe multiple comms feeds simultaneously (e.g., FOH Comms, Stage Manager, Lighting Director).
  - Single CoreAudio tap feeds independent `ChannelFeeder` and `SpeechTranscriber` instances with zero driver contention.
  - Chat-style interleaved transcript view with custom color-coded speaker badges and per-channel live meters.
  - Channel filter scoping on keyword rules (rules can trigger universally or only on specific comms channels).

- 🎚️ **Pro Audio & Dante Virtual Soundcard Support**
  - Direct CoreAudio device enumeration with channel assignment (supports interfaces with 2 to 64+ channels).
  - Works out of the box with **Dante Virtual Soundcard (DVS)**, AVB, USB, and virtual audio loopbacks.
  - Real-time dB peak level meters per channel.

- 🌐 **Network MIDI (Apple-MIDI / RTP-MIDI)**
  - Native CoreMIDI `MIDINetworkSession` support transmitting over standard UDP port `5004`.
  - Automatic **Bonjour discovery** (`_apple-midi._udp`) of show control machines on the local network.
  - Manual IP/host destination entry for fixed infrastructure (e.g., `192.168.1.50:5004`).
  - Sends Universal MIDI Packet (UMP) format over `MIDISendEventList` and native SysEx.

- ⚡️ **Keyword → Show Control Trigger Engine**
  - **Match Modes:** Contains phrase, Exact line match, or Prefix matching.
  - **Trigger Actions:**
    - **MIDI Note On / Note Off** (channels 1–16, notes 0–127, velocities 0–127) — *Standard for QLab cue triggers*.
    - **MIDI Control Change (CC)** (controllers 0–127, values 0–127).
    - **MIDI Program Change** (programs 0–127).
    - **MIDI Show Control (MSC)** (RP-002 SysEx: Device ID, Command Format, Command `GO`/`STOP`/`FIRE`, Cue Number & List) — *Standard for ETC Eos and grandMA*.
    - **Visual Alert** (flashes the Talkback screen border to silently alert operators).
  - **Cooldown Protection:** Configurable per-rule trigger cooldown (0.2s – 10.0s) to prevent transcription jitter from multi-firing cues.
  - **Rule Testing:** Dedicated "Test" buttons to test triggers instantly without speaking.

- 💾 **Session File Management (Word-style Save / Save As / Open / Recent)**
  - Full show session persistence in native `.livecue` format.
  - Save (`⌘S`), Save As (`⇧⌘S`), Open (`⌘O`), and Open Recent submenu.
  - Includes session transcripts, channel names & color configurations, keyword rules, audio device references, and trigger activity logs.
  - Double-click `.livecue` files in Finder to launch and restore sessions directly.

- ⚙️ **Automatic Configuration Persistence**
  - App preferences, default channel setup, rules, and MIDI destinations persist to `~/Library/Application Support/LiveCue/config.json`.

- 📄 **Transcript Export**
  - Export live transcript to:
    - **Plain Text (.txt)** with timestamps.
    - **CSV (.csv)** with ISO8601 timestamps, channel labels, and sanitized text.
    - **SubRip Subtitles (.srt)** with automatic display intervals.
  - Copy directly to clipboard or save to file.

- 💻 **CLI Audio File Check Mode**
  - Headless transcription of audio files for offline testing: `LiveCue --file path/to/file.wav [channel]`.

---

## System Requirements

- **Operating System:** macOS Tahoe 26.0 or later (uses Apple's modern `SpeechTranscriber` engine).
- **Architecture:** Apple Silicon (M1/M2/M3/M4) recommended for hardware-accelerated on-device neural transcription.
- **Xcode:** Xcode 26.0+ command-line tools.

---

## Installation & Building

Build using Swift Package Manager or the bundled release build script:

```bash
# Debug build (with complete strict concurrency)
swift build -Xswiftc -strict-concurrency=complete

# Run directly
swift run LiveCue

# Build release .app bundle with embedded logo (outputs to dist/LiveCue.app)
./build.sh

# Open the compiled app
open dist/LiveCue.app
```

---

## Show Control Quickstart

### 1. Connecting to QLab via Network MIDI
1. On your QLab machine, open **Audio MIDI Setup** > **MIDI Studio** > **Network**.
2. Enable your Session and set "Who may connect to me" to **Anyone**.
3. In Talkback, open the **Network MIDI** tab.
4. Your QLab machine will appear under **Active & Discovered Destinations**. Toggle it on, or add its IP manually (Port `5004`).
5. In Talkback's **Keyword Rules** tab, add a rule:
   - Keyword: `go`
   - Action: `MIDI Note On` -> Channel `1`, Note `60` (C4), Velocity `127`.
6. In QLab, set your cue's MIDI trigger to Note 60 on Channel 1. When the speaker says "go", QLab fires.

### 2. Controlling Lighting Desks (ETC Eos / grandMA) via MSC
1. In Talkback, add a keyword rule with action **MIDI Show Control (MSC)**:
   - Device ID: `1` (or matching console ID)
   - Command: `GO (0x01)`
   - Cue Number: `101`
2. Talkback packages the SysEx bytes (`F0 7F <dev> 02 01 01 31 30 31 F7`) and transmits directly over the network session.

---

## Architecture Overview

```
┌────────────────────────────────────────────────────────┐
│                      Audio Source                      │
│   (Hardware Interface, Mic, or Dante Virtual Soundcard)│
└───────────────────────────┬────────────────────────────┘
                            │
                   AVAudioEngine Tap
                            │
                 ┌──────────▼──────────┐
                 │    ChannelFeeder    │ (Mono extraction & resample to 16kHz)
                 └──────────┬──────────┘
                            │
                 ┌──────────▼──────────┐
                 │     Transcriber     │ (Apple SpeechAnalyzer / SpeechTranscriber)
                 └──────────┬──────────┘
                            │
               Settled Text / Volatile Partials
                            │
                 ┌──────────▼──────────┐
                 │        Model        │ (Orchestrator & State Manager)
                 └───┬───────────────┬─┘
                     │               │
        ┌────────────▼─────┐   ┌─────▼────────────┐
        │  KeywordMatcher  │   │   ContentView    │ (SwiftUI Interface)
        └────────────┬─────┘   └──────────────────┘
                     │
              Matched Action
                     │
        ┌────────────▼─────┐
        │    MIDIEngine    │ (CoreMIDI MIDINetworkSession & RTP-MIDI)
        └──────────────────┘
```

---

## CLI Usage

You can test transcription without hardware inputs by providing an audio file:

```bash
# Transcribe speech.wav (first channel)
swift run LiveCue --file /path/to/speech.wav

# Transcribe channel 2 of a multi-track recording
swift run LiveCue --file /path/to/multitrack.wav 2
```

---

## License

Open-source under the MIT License. See [LICENSE](LICENSE) for details.
