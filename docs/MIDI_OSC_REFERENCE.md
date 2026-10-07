# MIDI & OSC Technical Reference

> **Purpose:** Implementation reference for any agent building MIDI/OSC features in Talkback.
> Contains byte-level protocol specs, CoreMIDI Swift examples, and integration details
> for QLab, ETC Eos, and grandMA.
>
> **Last updated:** 2026-10-07

---

## 1. MIDI Show Control (MSC)

MSC is standardized by the MIDI Manufacturers Association under RP-002/RP-014 as an
extension of Universal Real-Time System Exclusive (SysEx).

### 1.1 Message Format

```
0xF0  0x7F  <device_ID>  0x02  <command_format>  <command>  [<data>]  0xF7
```

| Byte | Field | Description |
|------|-------|-------------|
| 0 | SysEx Header | `0xF0` (start of SysEx) |
| 1 | Real-Time Universal | `0x7F` |
| 2 | `device_ID` | Target device (see below) |
| 3 | Sub-ID #1 | `0x02` (constant — identifies MSC) |
| 4 | `command_format` | Equipment type (see below) |
| 5 | `command` | Action code (see below) |
| 6..N-1 | `data` | ASCII-encoded cue numbers, delimited by `0x00` |
| N | EOX | `0xF7` (end of SysEx) |

### 1.2 Device IDs

| Range | Meaning |
|-------|---------|
| `0x00`–`0x6F` (0–111) | Individual device |
| `0x70`–`0x7E` (112–126) | Group (1–15) |
| `0x7F` (127) | All-Call / Broadcast |

### 1.3 Command Format Categories

| Hex | Category |
|-----|----------|
| `0x01` | Lighting (General) |
| `0x02` | Moving Lights |
| `0x03` | Color Changers |
| `0x10` | Sound (General) |
| `0x11` | Music |
| `0x12` | CD Players |
| `0x20` | Machinery (General) |
| `0x21` | Rigging |
| `0x30` | Video (General) |
| `0x40` | Projection (General) |
| `0x50` | Process Control (General) |
| `0x60` | Pyrotechnics (General) |
| `0x7F` | **All-Types** (every device must parse) |

### 1.4 Command Codes

| Hex | Command | Description |
|-----|---------|-------------|
| `0x01` | **GO** | Fire designated cue (or next standby if unspecified) |
| `0x02` | **STOP** | Halt/pause active cue |
| `0x03` | **RESUME** | Resume paused cue |
| `0x04` | **TIMED_GO** | Fire with explicit fade time (H:M:S:F:FF) |
| `0x05` | **LOAD** | Place cue into standby without firing |
| `0x06` | **SET** | Set a fader/parameter level |
| `0x07` | **FIRE** | Trigger a macro/preset |
| `0x08` | **ALL_OFF** | Panic / Blackout |
| `0x09` | **RESTORE** | Restore pre-ALL_OFF state |
| `0x0A` | **RESET** | Stop all sequences, return to top of show |
| `0x0B` | **GO_OFF** | Fade out a running cue |

### 1.5 Cue Data Format

Cue numbers are **ASCII character codes**, NOT raw integers!

```
[Q_number ASCII bytes] 0x00 [Q_list ASCII bytes] 0x00 [Q_path ASCII bytes]
```

- Characters `'0'`–`'9'` → `0x30`–`0x39`
- Decimal point `'.'` → `0x2E`
- Fields delimited by `0x00` (null byte)
- Omit trailing `0x00` if Q_list or Q_path is absent

### 1.6 Concrete Examples (Hex Bytes)

**Unqualified GO (press GO button — all devices):**
```
F0 7F 7F 02 7F 01 F7
```

**GO Cue 10.5 on Lighting Desk (Device ID 1):**
```
F0 7F 01 02 01 01 31 30 2E 35 F7
```
*(Cue string "10.5" → ASCII 0x31 0x30 0x2E 0x35)*

**GO Cue 10.5 in Cue List 2 (Device ID 1):**
```
F0 7F 01 02 01 01 31 30 2E 35 00 32 F7
```
*(0x00 delimiter, then List "2" → ASCII 0x32)*

**FIRE Macro 42 on All Devices:**
```
F0 7F 7F 02 7F 07 34 32 F7
```

**STOP All on Sound System (Device ID 5):**
```
F0 7F 05 02 10 02 F7
```

---

## 2. Standard MIDI Messages for Show Control

```
Message Type         Status Byte            Data 1           Data 2
─────────────────────────────────────────────────────────────────────
Note Off             0x80 | ch (0-F)        Note (0-127)     Velocity (0-127)
Note On              0x90 | ch (0-F)        Note (0-127)     Velocity (0-127)
Control Change       0xB0 | ch (0-F)        Controller       Value (0-127)
Program Change       0xC0 | ch (0-F)        Program (0-127)  [None]
```

### Usage in Show Control

| Message | Use Case | Who Uses It |
|---------|----------|-------------|
| **Note On/Off** | Momentary cue triggers (fire/release) | QLab, Ableton, lighting desks |
| **Program Change** | Snapshot/scene recall | Digital consoles (Yamaha, DiGiCo, X32) |
| **Control Change** | Continuous faders, mutes, submasters | Everything |

**Important:** Ableton Live does NOT support MSC — it only understands Note On/Off, CC, and PC.

### Limitations of Standard MIDI vs MSC

- Only 128 notes per channel (2,048 across 16 channels)
- Cannot represent arbitrary string cue numbers like "10.5" without a lookup table
- No concept of cue lists or paths

---

## 3. Network MIDI on macOS (CoreMIDI)

### 3.1 MIDINetworkSession

```swift
import CoreMIDI

// Get/enable the default session
let session = MIDINetworkSession.default()
session.isEnabled = true
session.connectionPolicy = .anyone  // .noOne, .contactsOnly, .anyone

// Endpoints for sending/receiving
let source = session.sourceEndpoint()       // incoming network MIDI
let destination = session.destinationEndpoint()  // outgoing network MIDI
```

### 3.2 Connecting to Remote Hosts

```swift
// Define remote device
let host = MIDINetworkHost(name: "Lighting Desk", address: "192.168.1.50", port: 5004)

// Add contact and establish connection
session.addContact(host)
let connection = MIDINetworkConnection(host: host)
session.addConnection(connection)
```

### 3.3 Sending MIDI Messages

```swift
import CoreMIDI

// Create MIDI client and output port
var client = MIDIClientRef()
MIDIClientCreate("Talkback" as CFString, nil, nil, &client)

var outputPort = MIDIPortRef()
MIDIOutputPortCreate(client, "Output" as CFString, &outputPort)

// Send a Note On to the network destination
let destination = MIDINetworkSession.default().destinationEndpoint()

// Build MIDI event list
var eventList = MIDIEventList()
let packet = MIDIEventListInit(&eventList, .upb)

// Note On: channel 1, note 60 (C4), velocity 127
let noteOn: [UInt32] = [0x20900000 | (60 << 8) | 127]  // UMP format
MIDIEventListAdd(&eventList, MIDIEventList.sizeInBytes, packet, 0, 3, noteOn)

MIDISendEventList(outputPort, destination, &eventList)
```

### 3.4 Bonjour Discovery

```swift
import Network

let descriptor = NWBrowser.Descriptor.bonjour(type: "_apple-midi._udp", domain: "local.")
let browser = NWBrowser(for: descriptor, using: .udp)

browser.browseResultsChangedHandler = { results, changes in
    for result in results {
        if case let .service(name, type, domain, interface) = result.endpoint {
            print("Found MIDI destination: \(name)")
            // Resolve endpoint → create MIDINetworkHost
        }
    }
}
browser.start(queue: .main)
```

### 3.5 RTP-MIDI Protocol Details

AppleMIDI uses **UDP port pairs**:
- **Control Port** (default `5004`): Session negotiation, keep-alives, clock sync
- **Data Port** (default `5005`): RTP-encapsulated MIDI packets

Session commands on the control port (all start with `0xFFFF`):
- `IN` (0x494E) — Invitation
- `OK` (0x4F4B) — Accepted
- `NO` (0x4E4F) — Rejected
- `BY` (0x4259) — End session
- `CK` (0x434B) — Clock sync (3-way timestamp exchange)
- `RS` (0x5253) — Receiver feedback / sequence ACK

### 3.6 Required Info.plist Keys

```xml
<!-- Required for macOS 15+ Sequoia — without these, network MIDI silently fails -->
<key>NSLocalNetworkUsageDescription</key>
<string>Talkback needs local network access to discover and send MIDI to show control devices.</string>
<key>NSBonjourServices</key>
<array>
    <string>_apple-midi._udp</string>
    <string>_osc._udp</string>
</array>
```

### 3.7 App Sandbox Entitlements (if sandboxed)

```xml
<key>com.apple.security.network.client</key>
<true/>
<key>com.apple.security.network.server</key>
<true/>
```

---

## 4. Open Sound Control (OSC)

### 4.1 OSC vs MIDI Comparison

| Feature | MIDI / MSC | OSC |
|---------|-----------|-----|
| Addressing | Numeric (ch 1–16, note 0–127) | Hierarchical paths (`/cue/1/start`) |
| Data types | 7-bit integers (0–127) | Float, Int32/64, String, Blob, Bool |
| Transport | 5-pin DIN (31.25 kbps) or RTP-MIDI | Native Ethernet (UDP/TCP) |
| State feedback | Minimal | Rich bidirectional telemetry |
| Overhead | Very small (3 bytes channel voice) | Larger (null-padded strings) |

### 4.2 QLab OSC Paths

**Default port:** 53000 (UDP/TCP)

| Path | Action |
|------|--------|
| `/go` | Fire playhead cue |
| `/stop` | Stop all playback |
| `/pause` | Pause running cues |
| `/resume` | Resume paused cues |
| `/panic` | Smooth fade-out and stop all |
| `/reset` | Stop all, reset playhead to top |
| `/cue/{number}/start` | Start specific cue |
| `/cue/{number}/stop` | Stop specific cue |
| `/cue/{number}/load` | Pre-load cue |
| `/cue/{number}/preWait {seconds}` | Set pre-wait duration |
| `/cue/{number}/level/{in}/{out} {dB}` | Adjust matrix crosspoint |
| `/cue/selected/start` | Start currently selected cue |

### 4.3 ETC Eos Family OSC Paths

**Default ports:**
- TCP 3032 (OSC 1.0 length-prefixed framing)
- TCP 3037 (OSC 1.1 SLIP framing for high-rate telemetry)
- UDP 8000/8001

| Path | Action |
|------|--------|
| `/eos/cue/{number}/fire` | Fire cue on active list |
| `/eos/cue/{list}/{number}/fire` | Fire cue on specific list |
| `/eos/user/{id}/cue/{list}/{number}/fire` | Fire under background user |
| `/eos/key/go_0` | Press GO button |
| `/eos/key/stop` | Press STOP button |
| `/eos/cmd {string}` | Execute command line (e.g., `"Chan 1 At Full Enter"`) |
| `/eos/sub/{number}/fire` | Trigger submaster |
| `/eos/chan/{channel}/at {0-100}` | Set channel intensity |

### 4.4 UDP vs TCP for Show Control

| | UDP | TCP |
|---|-----|-----|
| **Use when** | Continuous telemetry, metering, multi-server broadcast | Mission-critical triggers (GO, E-Stop, panic) |
| **Reliability** | Fire-and-forget, no ACKs | Guaranteed delivery & sequencing |
| **Latency** | Minimum | Connection handshake overhead |
| **Topology** | Unicast, multicast, broadcast | Unicast only |
| **ETC Eos** | Ports 8000/8001 (secondary) | **Port 3032/3037 (recommended)** |

**Note:** ETC strongly recommends TCP for all show control. A dropped GO packet means a missed light cue.

### 4.5 TCP OSC Framing

**OSC 1.0 (length-prefixed, Eos port 3032):**
```
[4-byte Int32 big-endian length] [OSC packet]
```

**OSC 1.1 (SLIP framing, Eos port 3037):**
```
0xC0 [escaped OSC packet bytes] 0xC0
```
Escape rules: literal `0xC0` → `0xDB 0xDC`, literal `0xDB` → `0xDB 0xDD`

---

## 5. Integration Quick Reference

### For QLab

| Method | Setup |
|--------|-------|
| MSC | Workspace Settings → MIDI Controls → "Use MIDI Show Control" → set Device ID |
| OSC | Workspace Settings → Network → OSC → port 53000 |
| Notes | QLab always listens on MSC Device ID 127 (All-Call) in addition to configured ID |

### For ETC Eos

| Method | Setup |
|--------|-------|
| MSC | Browser → Setup → System → Show Control → MIDI → MSC Receive = Enabled |
| OSC | Built-in on ports 3032 (TCP) or 8000 (UDP) |
| Notes | Responds to Command Format 0x01 (Lighting) and 0x7F (All-Types) |

### For grandMA2/3

| Method | Setup |
|--------|-------|
| MSC (MA2) | Setup → Console → MIDI Show Control → In Device ID, In Group, In Command |
| MSC (MA3) | Menu → In & Out → MSC → Enable Input = ON |
| Notes | Supports Exec.Page mode for targeting specific executors |

### For Ableton Live

| Method | Notes |
|--------|-------|
| Note On/Off | Primary mechanism — launches clips, scenes, fires transport |
| CC | Controls faders, knobs, sends, macros, tempo |
| PC | Selects scenes |
| MSC | **NOT SUPPORTED** |
