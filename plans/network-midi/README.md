# Network MIDI plans: WING lamp without the helper

These plans are separate from the LiveCue code. The goal: the stage Mac
flashes the WING lamp through the audio MacBook using **only Audio MIDI
Setup's Live routing**, with no helper app running.

> **Nov 21:** the lamp now flashes from the stage Mac through
> [WING Lamp Bridge](../../tools/WINGLampBridge/README.md) (Fix B) on the audio
> MacBook. That's the working setup. The tests below are only needed to try
> dropping the bridge for Live routing alone.

| File | What it's for |
| --- | --- |
| [1-church-day-runbook.md](1-church-day-runbook.md) | Step-by-step tests for the next visit, in order, with what each result means |
| [2-fixes-and-fallbacks.md](2-fixes-and-fallbacks.md) | What to do once the tests show the cause, including fallbacks if Live routing can't work on that Mac |
| [midiprobe.swift](midiprobe.swift) | Small command-line test tool used by the runbook |
| [midithru.c](midithru.c) | Creates a route inside the system MIDI server, with no app running (runbook Test 2b, Fix P) |
| [rtppeer.py](rtppeer.py) | A stand-in network MIDI participant for testing one Mac on its own. Used for the Nov 15 results below |

Earlier results are in [docs/dev-notes/NETWORK_MIDI_FINDINGS.md](../../docs/dev-notes/NETWORK_MIDI_FINDINGS.md).

## What we know

- Stage Mac → network → audio MacBook works. The helper received 13 of 13 messages.
- Audio MacBook → USB → WING Port 4 → lamp works. The helper's USB test flashed.
- With the helper bridging those two hops, the lamp flashes.
- With Live routing (bottom menu = WING Port 4) instead of the helper, **nothing flashes**.

So the only broken piece is Live routing on the audio MacBook (2016 MacBook Pro, macOS Monterey 12.7.6).

## Why the helper works and Live routing doesn't: three differences

The helper ([tools/WINGLampReceiver/main.m](../../tools/WINGLampReceiver/main.m))
and Live routing do the same job, but differ in three ways. Each one points to a
possible cause:

| # | The helper… | Live routing… | Possible cause | Settled by |
| --- | --- | --- | --- | --- |
| 1 | finds "WING Port 4" fresh when you click Start | stores the port it was set to, which can go stale after the WING is replugged or re-enumerated, even though the menu still shows the same name | Routing points at an old, dead copy of WING Port 4 | Runbook steps A3, 2 and 3 |
| 2 | reads the network source directly | relies on Apple's routing inside the network driver, which has reported bugs: it sometimes doesn't engage until reselected, and some MIDI gets filtered ([Apple forum](https://discussions.apple.com/thread/254007424), [better-live-routings](https://github.com/coffeeshopped/better-live-routings)) | Live routing isn't forwarding at all on this Mac | Runbook step 2, then the resets in step 4 |
| 3 | rebuilds each message with timestamp 0 ("play now") | passes the network packet through with its timestamp | Packets are stamped in the future, so CoreMIDI holds them back (or drops them) before they reach USB | Runbook steps 1 and 2 |

About #3: CoreMIDI holding back future-stamped messages is **confirmed** on the
stage Mac. A packet stamped 1.5 s ahead arrived 1.5 s late, and one whose sender
quit first never arrived. Apple's network MIDI protocol does allow future
timestamps ([Apple: MIDI Network Driver Protocol](https://developer.apple.com/library/archive/documentation/Audio/Conceptual/MIDINetworkDriverProtocol/MIDI/MIDI.html)).
Whether this is happening between these two Macs is **not yet known**.

There are two more causes, both less likely:

- **Monterey itself.** The macOS version could have a bug. Step 5 tests this by swapping roles with the stage Mac (macOS 26).
- **Wrong session.** The routing could be set on a different session than the one the stage Mac joined. The runbook checks this in step 2.

Already ruled out: the WING settings, the cable, the lamp mapping, the network
and the message bytes. The helper's test path covered all of these.

## Nov 15: what the stage Mac showed on its own

Nobody was at the audio MacBook, so none of this says anything about that Mac
or the lamp. It narrows the causes from the stage Mac's side.

| Check | Result | What it means |
| --- | --- | --- |
| Sessions advertised on the network | The audio MacBook advertises **one** session, on port 5004 | "Wrong session" is less likely |
| What the stage Mac puts on the wire (`rtppeer.py capture`) | Every packet is a complete `B5 10 xx`, stamped 0.2–0.5 ms **before** the send time | The stage Mac doesn't send future timestamps or shortened (running status) messages. If cause #3 is real, it comes from the clock sync between the two Macs, not from the sender |
| How Apple's receiving side treats timestamps (`rtppeer.py send`, stage Mac as receiver) | A packet stamped 500 ms in the past arrives at once. One stamped 1.5 s ahead is held for 1.5 s | The network driver trusts the sender's timestamp, so cause #3 is possible. Tested on macOS 26 only |
| A MIDI server route instead of Live routing (`midithru`, network source → LiveCue Probe) | Forwards, with nothing running. It keeps the same timestamps | A second way to route without a helper app. It won't fix cause #3, but it sidesteps causes #1 and #2. Tested on macOS 26 only |

## Note on the stage Mac

macOS 26 also has a **UMP Network** (Network MIDI 2.0) driver. Monterey doesn't
support it. Keep using the RTP session ("Network RTP Session 1"), which is MIDI
1.0 and the one that already works with the helper.
