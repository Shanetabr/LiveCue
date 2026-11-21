# Handoff for Claude Fable 5.2 (Nov 15, 2026)

This picks up from a Claude Opus 5.5 session that ran from Oct 31 to Nov 15,
2026. It covers everything that session did and decided. Read it first, then
the files listed in "Read next".

> **Nov 21 update: the network lamp works.** At Shane's request, a session
> built **Fix B**: [WING Lamp Bridge](../../tools/WINGLampBridge/README.md),
> a no-window LaunchAgent version of the helper. It forwards only ch 6 CC 16,
> reconnects when ports come back, and sends OFF on exit. It's released
> separately as
> [`wing-lamp-bridge-v1.0.0`](https://github.com/Shanetabr/LiveCue/releases/tag/wing-lamp-bridge-v1.0.0),
> and LiveCue v1.2.0 stays Latest. Shane installed it on the audio MacBook. A
> `midiprobe flash` from the stage Mac **flashed the lamp** (Shane watched it),
> then ended OFF. Details: [NETWORK_MIDI_FINDINGS.md](NETWORK_MIDI_FINDINGS.md).
>
> Still open, in this order:
> 1. The bridge comes back by itself after the audio MacBook restarts (needs automatic login).
> 2. LiveCue's own FLASH 3 SECONDS button, then the rule's Test button, then the spoken rule (see "The verify plan" below).
> 3. The app issues below, which waited on the lamp.
>
> Ground rule 2 still stands: the runbook's Live-routing-only tests are now
> optional, for whenever Shane wants to try dropping the bridge.

## The project in one paragraph

LiveCue is a macOS 26+ SwiftUI app. Swift 6, built with SwiftPM and
[build.sh](../../build.sh), Apple Silicon only. It listens to live audio
channels with Apple's SpeechAnalyzer and SpeechTranscriber, then matches
spoken keywords against rules. A matching rule fires MIDI cues over network
MIDI (Apple RTP-MIDI) or USB. It's used at a church. The first real cue is
flashing the lamp on a Behringer WING console when someone says "Front of
House".

## People and repos

| | |
| --- | --- |
| **Shane** (GitHub `Shanetabr`) | Owner of this repo and the person you work with. Runs Claude Code on the stage Mac |
| **Dan** (GitHub `danielshaji1`) | Wrote LiveCue v1.0 to v1.1. Collaborator with write access here |
| **This repo** | [Shanetabr/LiveCue](https://github.com/Shanetabr/LiveCue) (formerly LiveCue-alpha-V2), `main`. **Public.** All work goes here |
| **Dan's original** | [danielshaji1/LiveCue-Talkback](https://github.com/danielshaji1/LiveCue-Talkback). Shane has no push access. Its v1.1.1 release has the WING Lamp Receiver helper zip |

Releases: v1.2.0 (Nov 12) is the latest. It added the network MIDI endpoint
rework, the lamp bridge, the Dante capture fix and new docs.

## Ground rules from Shane (keep these)

1. **The stage Mac never connects to the WING.** Everything goes stage Mac →
   Ethernet → audio MacBook → USB → WING. A test that temporarily plugs the
   stage Mac into the WING (runbook step 5b) is optional and only for
   diagnosis.
2. **The goal is Audio MIDI Setup Live routing alone, with no helper app.**
   The helper bridge works, but Shane explicitly doesn't want it as the
   answer. Only offer a bridge (Fix B in the plans) once the runbook proves
   Live routing can't work on that Mac.
3. **Fix the network lamp step before working on LiveCue itself.** Shane
   said so directly. The app bugs below wait.
4. **Keep plans separate from the code.** Plans go in [plans/](../../plans/),
   not mixed into `Sources/` or the docs.
5. **The repo is public.** Don't commit LAN IP addresses, emails, machine
   owner names or church details. The Nov 12 session removed the real
   addresses; use placeholders such as `<stage-mac-ip>`.
6. **Only the physical lamp counts as a pass.** A CoreMIDI send status of 0
   only means the message was accepted, not that the console reacted.
7. **Never test during a service.** Every flash test ends with lamp OFF.
8. **You can't see the audio MacBook.** Claude runs only on the stage Mac.
   Don't assume anything about the audio MacBook's state; ask Shane.
   (The previous session wrongly assumed the helper was installed there,
   drew conclusions from that, and had to retract them.)

## Hardware setup

```text
Stage Mac: MacBook Pro, Apple Silicon, macOS 26. Ethernet only. Runs Claude Code and LiveCue.
  │  Network MIDI session "Network RTP Session 1" (RTP-MIDI, MIDI 1.0)
  ▼
Audio MacBook: MacBook Pro 15" 2016, Intel, macOS Monterey 12.7.6. Likely can't upgrade.
  │  Its network source/destination is named "Network Session 1"
  │  It shows two network addresses, probably Ethernet + Wi-Fi
  │  USB
  ▼
Behringer WING: USB MIDI port "WING Port 4". Setup → MIDI → Custom Controls = USB
  └─ Layer 2, encoder 1 = Lamp Brightness = MIDI channel 6, CC 16
       ON  = B5 10 7F
       OFF = B5 10 00
```

## Network MIDI: where it stands

### Proven

| Test | Result |
| --- | --- |
| Turn Layer 2 encoder 1 by hand | Lamp responds |
| Audio MacBook → USB → WING Port 4 (helper's "Test USB flashing") | Flashes, send status 0 |
| Stage Mac → network → helper bridge on the audio MacBook → WING Port 4 | **Flashes.** The helper counted 13 received, 13 lamp commands, 13 USB sends |
| Stage Mac → network → **Live routing** (top menu blank, bottom = WING Port 4), helper quit | **No flash.** Repeated many times, including a nonstop flash. A restart didn't help |

**Isolated failure:** Live routing in Audio MIDI Setup on the Monterey
MacBook. Every other hop works.

### Why the helper works and Live routing doesn't

The helper ([tools/WINGLampReceiver/main.m](../../tools/WINGLampReceiver/main.m))
differs from Live routing in three ways. Each one is a hypothesis:

1. **Stale port.** The helper finds "WING Port 4" fresh when Start is clicked.
   Live routing stores the port it was set to, which can go stale after a
   replug even though the menu still shows the same name.
2. **Live routing doesn't engage.** There are reported bugs where it doesn't
   start until it's reselected, or filters some MIDI
   ([Apple forum](https://discussions.apple.com/thread/254007424),
   [better-live-routings](https://github.com/coffeeshopped/better-live-routings)).
3. **Timestamps.** The helper rebuilds each message with timestamp 0 ("now").
   Live routing passes the network packet's timestamp through. Verified on the
   stage Mac: CoreMIDI holds a future-stamped packet until its time (a packet
   stamped +1500 ms arrived 1.5 s late), and drops it if the sender
   disconnects first. Whether these two Macs actually produce future
   timestamps is **not yet known**.

There are two more possibilities: a Monterey bug, or the routing being set on
a different session than the one the stage Mac joined. Already ruled out: the
WING settings, the cable, the lamp mapping, the network and the message bytes.

The stage Mac also has a **UMP Network** (Network MIDI 2.0) driver, which
Monterey doesn't support. Keep using the RTP session.

### Next action

Shane runs the church-day runbook on his next visit, with you running the
stage Mac side.

- [plans/network-midi/README.md](../../plans/network-midi/README.md): the hypotheses above, with evidence.
- [plans/network-midi/1-church-day-runbook.md](../../plans/network-midi/1-church-day-runbook.md): ordered tests with a result table for each, about 45–60 min. **Test 2** is the key one: route Live routing to the probe's virtual destination. If nothing arrives, Live routing isn't forwarding at all.
- [plans/network-midi/2-fixes-and-fallbacks.md](../../plans/network-midi/2-fixes-and-fallbacks.md): the fix for each outcome.
  - Fix S: stale port.
  - Fix R: a reset worked.
  - Fix T: timestamps.
  - If Live routing is dead on Monterey: Fix B (invisible LaunchAgent bridge, same day), Fix C (newer Mac at the WING) or Fix D (RTP-MIDI hardware into the WING's MIDI IN).
  - The plan ends with a decision tree.

When Shane comes back with results, fill in the runbook's results sheet, pick
the fix, and update [NETWORK_MIDI_FINDINGS.md](NETWORK_MIDI_FINDINGS.md).

## Test tools

### `plans/network-midi/midiprobe.swift`

Written by the previous session; self-tested on the stage Mac. It sends only
ch 6 CC 16 and always ends with OFF.

| Command | What it does |
| --- | --- |
| `midiprobe list` | Every device, including offline ones, plus sources and destinations with unique IDs |
| `midiprobe listen "<source>"` | Prints the bytes and the timestamp offset ("+X ms from now") of each packet |
| `midiprobe dest` | Creates a virtual destination called "LiveCue Probe" and prints what arrives |
| `midiprobe flash "<dest>" [--loop]` | ON/OFF every 250 ms ×12, or every 0.5 s until Ctrl-C |

Build it for the stage Mac:

```bash
swiftc -swift-version 5 -O plans/network-midi/midiprobe.swift -o /tmp/midiprobe
```

Build it for the Intel audio MacBook:

```bash
swiftc -swift-version 5 -O -target x86_64-apple-macos12.0 plans/network-midi/midiprobe.swift -o /tmp/probe-share/midiprobe
```

Copy it over by serving it from the stage Mac with `python3 -m http.server`
and running `curl` on the audio MacBook. `curl` doesn't set the quarantine
flag, so Gatekeeper won't block it. Exact commands are in the runbook.

### Other tools

- [scripts/NetworkLampFlash.swift](../../scripts/NetworkLampFlash.swift): the earlier flash script, `NetworkLampFlash "<dest>" [--loop <stop file>]`. `midiprobe flash` replaces it.
- [tools/WINGLampReceiver](../../tools/WINGLampReceiver/): Dan's Objective-C helper (macOS 11+, universal). It forwards only ch 6 CC 16 from the network to USB, sends with timestamp 0, and parses running status. It's the proven bridge and the basis for Fix B.
- [tools/WINGLampBridge](../../tools/WINGLampBridge/README.md): Fix B, built Nov 21. Plain C, no window, starts at login. Install it from its release zip, then use `wing-lamp-bridge --list` and `--flash` on the audio MacBook for diagnosis. The log is `~/Library/Logs/WINGLampBridge.log`.
- [MIDI Monitor](https://www.snoize.com/midimonitor/): free, works on Monterey. Runbook step 3 uses its "Spy on output to destinations" to see whether Live routing reaches WING Port 4.

## LiveCue app: known issues (not started, they wait on the lamp)

From the previous session's full review. Each one was re-checked against
`main` on Nov 15.

| Issue | Where | Status |
| --- | --- | --- |
| `AVAudioFormat(commonFormat:sampleRate:channels:interleaved:)` returns nil above 2 channels, so START failed on Dante and other multi-input devices | [AudioCapture.swift](../../Sources/Talkback/AudioCapture.swift) | **Fixed** in `c6d211e` with a discrete channel layout. Typechecks clean in Swift 6 mode; **not yet run with real Dante hardware** |
| MSC "FIRE (0x0B)" option actually sends MSC GO_OFF (0x0B); FIRE is 0x07 | [KeywordRulesView.swift:410](../../Sources/Talkback/KeywordRulesView.swift:410) | Open |
| Substring matching has no word boundaries ("cue 1" fires on "cue 10") | [KeywordMatcher.swift:54](../../Sources/Talkback/KeywordMatcher.swift:54) | Open |
| The banner says "Fired" even when the MIDI send failed | [Model.swift:519](../../Sources/Talkback/Model.swift:519) | Open. Reuse `midiEngine.lastError` |
| `finish()` cancels the reading task before finalizing, so the last result is dropped | [Transcriber.swift:116](../../Sources/Talkback/Transcriber.swift:116) | Open. Finalize first, then await |
| The channel clamp overwrites saved channel inputs when a smaller device is selected | [Model.swift:230](../../Sources/Talkback/Model.swift:230) | Open |
| The audio device isn't saved between launches | Model.swift (only recent documents use UserDefaults) | Open |
| Auto-reconnect matches by name, so it can pick the wrong device when two have the same name | [Model.swift:160](../../Sources/Talkback/Model.swift:160) | Open |
| No unsaved-changes prompt on quit or close | Model / app | Open |
| No LICENSE; stale docs | | **Fixed** Nov 12 (LICENSE added, README reworked, notes moved to `docs/dev-notes/`) |

Not yet verified end to end:

- Sending from LiveCue itself. All the lamp tests used scripts.
- The spoken "Front of House" rule.

The verify plan:

1. Use the FLASH 3 SECONDS button and check that the lamp ends OFF.
2. Use the rule's Test button.
3. Say the phrase live and check for one 3 s flash.
4. Restart both apps and repeat.

## Working notes

- **Checks.** Typecheck the whole app (passes as of Nov 15):

  ```bash
  swiftc -typecheck -swift-version 6 -target arm64-apple-macos26.0 Sources/Talkback/*.swift
  ```

  The repo also has `scripts/test-memory.sh` and the `scripts/*Test.swift` regressions (virtual CoreMIDI endpoints only).

- **Permissions.** In the previous session, auto mode blocked building and running the repo's code ("code from external"). Typechecking and the session's own scripts were allowed. If a build is blocked, ask Shane.
- **graphify.** Shane's global CLAUDE.md asks for graphify in code projects: run `graphify query` before exploring, and `graphify update .` after code changes. `graphify-out/` is local and isn't committed.
- **Commits.** Push to `main` on this repo. Shane has been committing straight to `main`; PR #1 was the exception.
- **Workspace.** The previous session worked in a temporary folder the app created. Clone this repo fresh.

## Timeline

| Date | What happened |
| --- | --- |
| Oct 7–31 | Dan builds v1.0 to v1.1.1: multi-channel capture, keyword rules, network MIDI, the lamp preset, the helper, the Opus handoff ([CLAUDE_OPUS_HANDOFF.md](CLAUDE_OPUS_HANDOFF.md)) |
| Oct 31 – Nov 2 | Opus 5.5 session: full repo review, then hands-on lamp tests with Shane at church. Proven: the helper bridge flashes. Failed: Live routing |
| Nov 2 | V2 repo created; findings, test script, plans and midiprobe pushed. Dan invited, and has since accepted |
| Nov 12 | A separate session (PR #1): README and LICENSE, notes moved to `docs/dev-notes/`, the Dante fix, LAN addresses removed, v1.2.0 released. The repo is now public |
| Nov 15 | This handoff. Nothing has been tested on the hardware since early November; the runbook is still untried |
| Nov 21 | WING Lamp Bridge (Fix B) built, released separately and installed on the audio MacBook. A network flash from the stage Mac lit the lamp |

## Read next

1. [plans/network-midi/README.md](../../plans/network-midi/README.md), the runbook and the fixes plan.
2. [NETWORK_MIDI_FINDINGS.md](NETWORK_MIDI_FINDINGS.md): raw results.
3. [CLAUDE_OPUS_HANDOFF.md](CLAUDE_OPUS_HANDOFF.md): Dan's endpoint rework and the packet-capture evidence.
4. [README.md](../../README.md) and [docs/TROUBLESHOOTING.md](../TROUBLESHOOTING.md): the app as users see it.
