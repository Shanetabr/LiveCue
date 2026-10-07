# ProdCom Competitive Analysis

> **Purpose:** Reference document for any agent or developer working on Talkback.
> This is a complete feature inventory of ProdCom (prodcom.io), the commercial product
> Talkback aims to be an open-source alternative to.
>
> **Last updated:** 2026-10-07

---

## What ProdCom Is

ProdCom is a real-time, multi-channel voice intelligence and speech-to-text platform for
live production (theatre, broadcast, concert touring, corporate events). It bridges
comms/talkback audio and show control automation — letting FOH engineers, monitor engineers,
and show callers "read" chatter in loud environments and trigger automated production cues
via spoken keywords.

- **Developer:** ProdCom, LLC (co-founded by touring live sound engineers Justin Tyre and Stephen Bailey)
- **Platforms:** macOS (native), iOS/iPadOS (native), visionOS (compatibility mode)
- **No Windows support** — this is the #1 user complaint
- **Pricing:** $69.99/year or $9.99/month per device (subscription-gated, 1-week free trial)
- **App size:** ~38.4 MB (lightweight — leverages Apple's built-in speech frameworks)
- **Min requirements:** macOS 14 (Sonoma), iOS 17; Apple Silicon strongly recommended
- **Bundle ID:** `com.prodcom.prodcom`

---

## Complete Feature Inventory

### 1. Multi-Channel Transcription

| Feature | Details |
|---------|---------|
| Simultaneous channels | Multiple audio channels transcribed in parallel |
| Channel naming | Custom names per channel (e.g., "FOH", "MON", "SM", "LD") |
| Channel colors | User-defined color palette per channel |
| Channel icons | Custom icons per channel |
| Channel groups | Organize channels into logical groups (e.g., "Audio Dept") |
| Text-only channels | Channels without audio input — pure text chat |
| Per-channel language | Language selectable per channel |
| Per-channel pause/resume | Global and per-channel transcription controls |
| Live level meters | Per-channel audio level indicators |
| Matrix audio patching | Routing grid to map hardware inputs → transcription channels (v2.3+) |
| Inspector panel | Dedicated config panel for channel parameters |

### 2. Audio Interface Support

| Standard | How it works |
|----------|-------------|
| DANTE | Via Dante Virtual Soundcard (DVS) or PCIe Dante cards |
| MADI | Via CoreAudio drivers |
| AVB | Via CoreAudio drivers |
| Waves SoundGrid | Via SoundGrid driver |
| USB / Thunderbolt | Any class-compliant interface |
| Device reconnect | Handles interface disconnect/reconnect gracefully during shows |

### 3. Speech Recognition

- Uses Apple's on-device speech framework + Neural Engine on Apple Silicon
- Fully offline for transcription (no internet needed during shows)
- Translation features require internet
- Accuracy estimated ~85% under ideal talkback conditions, degrades with stage bleed/noise
- "AI Personas" (v2.3.1): on-device LLM rewrites transcripts in styles (Pirate, Yoda, etc.)

### 4. Keyword Detection & Automation

| Feature | Details |
|---------|---------|
| Keyword triggers | Define specific words/phrases that fire actions |
| Create from transcript | Select text in transcript → convert to keyword trigger |
| MIDI output | Send Note On/Off, CC messages on configurable channel/note/value |
| OSC output | Send OSC messages (UDP or TCP) with custom address patterns + args |
| Visual alerts | Highlight banners, "Flash Window Until Acknowledged" mode |
| Webhooks | Trigger HTTP endpoints |
| MIDI hardware input | Hardware MIDI controllers can trigger in-app macros |

### 5. MIDI Integration Details

- **Message types:** Note On/Off, Control Change (CC)
- **Parameters:** Configurable MIDI channel (1–16), note number, CC number, velocity/value
- **Destinations:** Routes to IAC virtual buses or physical MIDI interfaces
- **Inbound MIDI:** Hardware controllers can trigger pause/resume, switch channels, fire macros

### 6. OSC Integration Details

- **Protocols:** UDP and TCP
- **Network binding:** Selectable interface for dedicated show networks / VLANs
- **Outbound:** Custom address patterns and arguments → QLab, ETC Eos, grandMA, Resolume, Disguise
- **Configurable:** Per-command destination IP and port
- **Inbound:** Exposes `/prodcom/...` namespace for external control (Stream Deck via Companion, QLab, lighting consoles)
- **Known bug (fixed v2.3.2):** Trailing spaces in OSC address patterns caused strict receivers to reject

### 7. Application API (v2.3+)

- **Base URL:** `http://<ip>:24480/api/v1/` (port configurable)
- **Documentation:** Built-in Swagger at `http://localhost:24480/docs`
- **WebSocket:** `GET /api/v1/ws` — live transcript events, channel updates, automation states
- **SSE:** `GET /api/v1/transcript/stream` — lightweight transcript stream for browsers
- **REST:** `POST /api/v1/automations/:id/trigger` — trigger automations by ID
- **Security:** Default open for trusted LANs; optional Bearer token auth

### 8. Network Sharing

- **Bonjour (mDNS):** Zero-config discovery on LAN
- **Manual IP fallback:** For VLANs blocking multicast
- **Network interface selection:** Bind to specific adapters (Dante network vs Wi-Fi)
- **Channel/group sharing:** Share channels or groups across Macs and iOS devices
- **Password protection:** Per-group passwords

### 9. UI & Display

- Dark-mode, production-oriented interface
- Chat-style color-coded bubbles per channel
- Floating window support (detached per-channel windows)
- Hybrid text input: type into any channel alongside transcribed audio (keyboard icon indicator)
- Optional timestamps on transcript entries
- Search/filter within transcripts
- Unread badges for off-screen messages
- Profanity filtering toggle for corporate/broadcast

### 10. Export

- **Transcript export:** Time-stamped TXT/log files
- **Config export/import:** Full JSON of channels, groups, keywords, automations
- **Diagnostic logs:** System/connection logs for troubleshooting

---

## User Sentiment & Pain Points

### What Users Love
1. **Silent talkback** — eliminates loud shout speakers, no need for continuous headset wear
2. **Accountability** — scroll back through transcript to see what was requested
3. **Digital call-light** — keyword flashing when someone calls your name
4. **Show control integration** — speech → OSC/MIDI triggers for console snapshots, QLab cues
5. **Affordable** — $70/year is easily reimbursable for touring engineers

### Top Complaints
1. **No Windows support** — #1 complaint. Many touring rigs run Windows.
2. **Accuracy in loud environments** — degrades with stage bleed, mumbling, noisy dynamic mics
3. **Setup friction** — macOS permissions and DANTE routing setup is confusing
4. **Per-device licensing** — inconvenient when bouncing between primary Mac, backup, and iPad

### Alternatives Users Mention
- Physical intercom systems (Clear-Com, Riedel Bolero, Green-GO)
- MacWhisper / local Whisper wrappers (better accuracy, no multi-channel or show control)
- Meeting tools (Otter.ai, Teams captions) — clunky for multi-channel talkback

---

## What Talkback Can Do Better (Open-Source Advantages)

1. **Free and open-source** — no per-device subscription
2. **Community-driven** — features driven by actual production users
3. **Extensible** — plugin/scripting architecture for custom integrations
4. **Transparent** — users can verify audio never leaves the machine
5. **Customizable** — modify UI, add protocol support, integrate with any system
6. **MIDI Show Control (MSC)** — ProdCom only does Note On/Off and CC; Talkback can add full MSC support for direct QLab/Eos/grandMA integration
