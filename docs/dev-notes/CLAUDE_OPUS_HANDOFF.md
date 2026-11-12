# Claude Opus handoff — LiveCue / WING lamp

Updated October 31, 2026 (America/New_York).

**Nov 2026 update:** network MIDI reaches the audio MacBook and flashes the lamp through the helper bridge, but not through Audio MIDI Setup Live routing. See [NETWORK_MIDI_FINDINGS.md](NETWORK_MIDI_FINDINGS.md).

## Goal and current result

Saying **“Front of House”** on the stage Mac must flash the Behringer WING
console lamp for three seconds, then leave it off. MIDI transport is priority 1;
Dante audio capture is secondary.

**Direct USB from the stage Mac worked physically. Network-to-WING flashing
still does not work. Do not describe this as fixed.**

The intended connection is:

```text
Stage Mac / LiveCue
  -> Apple RTP-MIDI over Ethernet
  -> audio MacBook
  -> WING USB Port 4
  -> console lamp brightness
```

This commit includes the previously local MIDI changes, standalone diagnostics,
and virtual CoreMIDI tests. A fresh checkout contains the code; do not apply an
old `pending-midi.patch`. Older handoffs describe earlier states and are historical.

## Confirmed evidence and important corrections

- WING Custom Controls Layer 2 encoder 1 is assigned OTHER -> LAMP BRIGHTNESS.
  Its mapping is MIDI channel **6**, CC **16** (zero-based channel index 5).
- Exact bytes: ON **`B5 10 7F`**, OFF **`B5 10 00`**.
- The stage Mac was connected directly to WING USB and sent alternating ON/OFF
  through **WING Port 4**. The user confirmed “It's flashing,” then confirmed it
  stopped after the final OFF. Preserve this working mapping.
- After returning to Ethernet, the user repeatedly reported no physical flash.
- Stage Ethernet packet captures showed the exact ON/OFF RTP-MIDI messages and
  matching **RS receiver-feedback sequence numbers from the audio Mac**. This
  establishes transport receipt by that Mac's network MIDI driver. It does not
  establish CoreMIDI application input, USB forwarding, or console receipt.
- A runner compiled from the updated `MIDIEngine.swift` completed the actual
  three-second `flashWINGLamp()` operation: 13 accepted sends, final `B5 10 00`,
  no engine error. Packet capture also showed matching remote feedback.
- **Receiver helper counters have NOT been verified.** The user accidentally
  selected “Counters increase; lamp stays off,” then immediately retracted that
  answer. Do not treat it as evidence. Their next photo showed Audio MIDI Setup,
  rather than the WING Lamp Receiver diagnostic app.
- The audio Mac photo showed an enabled session, the stage participant, and
  WING Port 4 in the bottom Live routing menu. The top menu was at one point
  Network Session 1; setting it to blank still did not produce flashing.
- The audio Mac's own direct USB lamp test has **not** been confirmed. Earlier
  direct USB success was from the stage Mac.
- The stage repeating sender was stopped with a final OFF before this handoff.
  Do not assume any old temporary process or endpoint reference still exists.

## Next hardware test — resume here

The last request to the user was to perform a direct USB test **on the audio
MacBook connected to WING**, using the standalone receiver helper:

1. Open WING Lamp Receiver on that Mac; select **WING Port 4** output.
2. Keep the bridge stopped and the stage network loop stopped.
3. Click **Test USB flashing**. Ask whether the physical lamp flashes and inspect
   the helper's direct USB send status. Use **Lamp OFF / Stop USB test** afterwards.
4. If direct USB from this Mac fails, diagnose its actual USB endpoint/console
   connection before doing further network retries. Avoid unrelated console
   fader or mute tests.
5. If it works, retain the network participant connection, set **both Audio MIDI
   Setup Live routings blank**, select helper input **Network Session 1** and output
   **WING Port 4**, then **Start bridge**. Restart the stage sender deliberately.
6. Read all three helper counters and last received hex. Zero received packets
   means the selected CoreMIDI input is not delivering. Received packets with no
   lamp commands require inspecting bytes. Lamp commands and accepted USB sends
   with no flash require checking the USB path against the successful direct test.
7. Once manual network flashing works physically, verify the three-second flash
   and then the speech rule with actual microphone/Dante audio.

Use one receiving bridge at a time:

| Method | Audio MIDI Setup top route | Bottom route | Additional bridge |
| --- | --- | --- | --- |
| Native macOS Live routing | Blank (`–`) | WING Port 4 | Off |
| WING Lamp Receiver helper | Blank | Blank | Network Session 1 -> WING Port 4, started |
| Updated LiveCue bridge | Blank | Blank | Select network input and WING USB output, enable bridge |

The top route sends a local MIDI source to the network; the bottom route sends
received network MIDI to a local destination. Port 4 is WING remote control;
do not substitute a DAW port merely because it appears first.

## Code included

- `Sources/Talkback/MIDIEngine.swift`: enumerates real CoreMIDI network inputs
  and outputs, selects them by unique ID, subscribes to the selected source,
  and sends through the selected destination. It replaces the old reliance on
  `MIDINetworkSession.default()`, whose accessors returned empty/zero on this
  Mac despite the connected session visible in Audio MIDI Setup.
- A single network endpoint auto-selects; multiple endpoints require selection.
  Missing selections stay missing, preventing accidental redirection. Missing
  USB output does not silently fall back to network. CoreMIDI callbacks are
  explicitly `@Sendable`; stale queued source callbacks are ignored.
- Direct WING USB selection, lamp ON/OFF/three-second flash, network receive
  and forward counters, last sent/received hex, and opt-in network-to-USB bridge.
- `MIDIWire.swift`: shared MIDI 1.0 byte packet sending/parsing, bounded to 256
  bytes per send. Changing from UMP was a diagnostic simplification, not proof
  that the earlier UMP serialization caused the failure.
- `MIDISettingsView.swift` and `ContentView.swift`: actual port selectors,
  diagnostics, and truthful “port available” status. Availability and accepted
  sends do not imply a remote connection or successful physical operation.
  Peer connections are managed in Audio MIDI Setup; discovered/saved hosts
  are informational. Old configuration fields remain compatible.
- `tools/WINGLampReceiver/main.m`: standalone Cocoa/CoreMIDI helper for the audio
  Mac, supporting macOS 11+. It parses incoming MIDI, forwards **only channel 6
  CC16**, and has a separate direct USB flashing test. Source and test are included.
- `scripts/NetworkMIDITest.swift`: actual virtual CoreMIDI send/receive tests,
  rename stability, and missing network/USB output checks. No real console is
  addressed by this test.
- `scripts/WINGLampTest.swift`: packet self-test plus deliberately invoked,
  indefinitely repeating hardware diagnostic. Its network endpoint display name
  is specific to the tested stage session; inspect current names before running.

Review limitations before calling this production ready: network selections
are runtime selections, the main LiveCue bridge forwards arbitrary received
packets (unlike the lamp-only helper), large SysEx exceeds the 256-byte sender
limit, and the full speech-to-network-to-lamp flow has not been verified.

## Build and test

Main LiveCue requires macOS 26+ and Swift 6. No third-party dependencies.

```sh
swift build -Xswiftc -strict-concurrency=complete

swiftc -parse-as-library -swift-version 6 -strict-concurrency=complete \
  Sources/Talkback/MIDIEngine.swift Sources/Talkback/MIDIWire.swift \
  scripts/NetworkMIDITest.swift -o /tmp/livecue-network-regression
/tmp/livecue-network-regression

clang -fobjc-arc -framework Cocoa -framework CoreMIDI \
  tools/WINGLampReceiver/test.m -o /tmp/wing-receiver-integration-test
/tmp/wing-receiver-integration-test

sh scripts/test-memory.sh
sh build.sh
codesign --verify --deep --strict dist/LiveCue.app
```

Prior checks passed: strict-concurrency build, release build/signature, virtual
network regression, helper input/parser/output integration (including running
status and filtering unrelated messages), and memory checks. Virtual endpoint
tests require access to the macOS MIDI server; a sandbox denial is not evidence
of a MIDI protocol bug. Hardware evidence is limited to the observations above.

For the packet self-test (no hardware output):

```sh
swiftc -parse-as-library -swift-version 6 Sources/Talkback/MIDIWire.swift \
  scripts/WINGLampTest.swift -o /tmp/livecue-wing-lamp-test
/tmp/livecue-wing-lamp-test --self-test
```

Hardware loops require deliberate `--run` or `--run --network`. Stop the supplied
loop by creating `/private/tmp/livecue-wing-lamp.stop`; verify its printed final
OFF status and exit before starting a separate USB test.

## Packaging and repository

- Public repository: https://github.com/danielshaji1/LiveCue-Talkback
- Published baseline before this push: `18002af`; release v1.1.1.
- This is a **source push**, not a new release. `Info.plist` still says 1.1.1.
  Published LiveCue v1.1.1 does not contain these new selectors/bridge fixes.
- A local corrected `dist/LiveCue.app` was built and ad-hoc signed. The running
  app was not confirmed restarted; an earlier attempt to access its window was
  blocked by automatic approval review without a detailed reason.
- Universal Intel/Apple Silicon helper download previously attached to v1.1.1:
  https://github.com/danielshaji1/LiveCue-Talkback/releases/download/v1.1.1/WING-Lamp-Receiver-Diagnostic.zip
- `dist/` and `.build/` are ignored. Build products are not committed here.
- Increment version metadata and produce fresh assets for any subsequent release.

## Secondary issue: Dante and memory

The mic is on Dante receive channel 1. The user reported no LiveCue meter
movement with Dante Virtual Soundcard. AudioUnit device/format and callback
diagnostics were added in the published baseline; hardware recovery remains
unconfirmed. Check DVS running state, selected input channel, microphone
permission, callback count, and another recorder receiving the same input.

Existing memory work caps live audio queues, reuses conversion scratch buffers,
uses Accelerate metering, and archives older transcript lines to disk while
keeping roughly 500–600 recent lines visible. Full export/save/open can still
materialize the complete history. Avoid regressing these bounds while fixing MIDI.
