# Network MIDI findings — WING lamp (Nov 2026)

Continues [CLAUDE_OPUS_HANDOFF.md](CLAUDE_OPUS_HANDOFF.md). These are the
hardware results from testing on the stage Mac.

## Setup

```text
Stage Mac (MacBook Pro, macOS 26, Ethernet only)
  -> Network RTP Session 1 (Apple RTP-MIDI)
  -> Audio MacBook (MacBook Pro 15" 2016, macOS Monterey 12.7.6)
  -> USB, WING Port 4
  -> WING Layer 2 encoder 1 = Lamp Brightness (ch 6, CC 16)
```

The stage Mac will never connect to the WING directly. Everything has to go
through the audio MacBook.

## Results

| Test | Result |
| --- | --- |
| Turn Layer 2 encoder 1 by hand | Lamp responds |
| WING Setup → MIDI, Custom Controls → USB | On |
| WING icon in MIDI Studio on the audio MacBook | Solid, not greyed out |
| Helper **Test USB flashing** on the audio MacBook | **Flashes**, send status 0 |
| Stage Mac → helper bridge → Port 4 | **Flashes**. Helper showed 13 received, 13 lamp commands, 13 USB sends accepted, last received `B5 10 00` |
| Stage Mac → Audio MIDI Setup Live routing (top blank, bottom WING Port 4), helper stopped | **No flash**, repeated several times, and also while sending nonstop |
| Restarting the audio MacBook | Done earlier; didn't fix Live routing |

## Conclusion

- The stage Mac, the network session, WING Port 4, the console settings and
  the lamp all work.
- The failing step is **Live routing in Audio MIDI Setup on the audio MacBook**.
  The same messages arrive at that Mac's network session, and a CoreMIDI app
  that forwards them (the WING Lamp Receiver helper) flashes the lamp.
- The root cause is **unconfirmed**. Monterey 12.7.6 is a suspect, but no
  matching bug report was found. One older developer note reports Live routing
  dropping some MIDI ([better-live-routings](https://github.com/coffeeshopped/better-live-routings)).
- That 2016 MacBook is likely limited to Monterey, so LiveCue (macOS 26+)
  can't run there as the bridge.
- The audio MacBook showed two addresses on the network (Ethernet and
  Wi-Fi, most likely). That probably isn't the cause,
  since the helper received everything, but it hasn't been ruled out.

## Still to try without the helper

The goal is to work with Audio MIDI Setup alone. On the audio MacBook:

1. Quit the helper and turn off Wi-Fi.
2. Remove any extra sessions under My Sessions, or create a fresh session,
   reconnect the stage Mac, then set only the bottom route to WING Port 4.
3. In MIDI Studio, create a new configuration, delete greyed-out WING entries,
   then replug the WING.
4. If possible, repeat the Live routing test on a newer Mac connected to the
   WING by USB, to see whether Monterey is the cause.

If Live routing can't be made to work, the working fallback is a small bridge
that runs automatically on the audio MacBook, using the helper's approach.

## Nov 15: stage Mac only

Nobody was at the audio MacBook or the lamp. Tested from the stage Mac with
[rtppeer.py](../../plans/network-midi/rtppeer.py) and
[midithru.c](../../plans/network-midi/midithru.c):

- The audio MacBook advertises one network MIDI session (port 5004).
- The stage Mac sends each message as a complete `B5 10 xx`, stamped 0.2–0.5 ms before the send. It doesn't send future timestamps.
- Apple's receiving driver (macOS 26) trusts the sender's timestamp: 500 ms in the past arrives at once, 1.5 s ahead is held 1.5 s.
- A MIDI server thru route (network source → virtual destination) forwards on macOS 26 with no app running, and keeps the timestamps.

Details and what they mean: [plans/network-midi/README.md](../../plans/network-midi/README.md).
The runbook's audio MacBook tests are still untried.

## Nov 21: network flash works

From the stage Mac, `midiprobe flash "Network RTP Session 1"` sent one 3 s flash
(12 ON/OFF at 250 ms, then OFF, all accepted). **Shane saw the lamp flash.**
On the audio MacBook, the new [WING Lamp Bridge](../../tools/WINGLampBridge/README.md)
was forwarding (installed from the `wing-lamp-bridge-v1.0.0` release).

This confirms the bridge on real hardware: stage Mac → network → bridge →
WING Port 4 → lamp. Still to check: it comes back by itself after a restart
of the audio MacBook (needs automatic login), sending from LiveCue's own
FLASH 3 SECONDS button, and the spoken "Front of House" rule. Live routing
alone still hasn't worked on that Mac.

## Nov 21, later: LiveCue 1.3.0 Test Connection, all green

Bridge 1.1 is installed on the audio MacBook (from `wing-lamp-bridge-v1.1.0`).
LiveCue 1.3.0's Test Connection on the stage Mac passed every step:

| Step | Result |
| --- | --- |
| Network MIDI on this Mac | Sending on Network RTP Session 1 |
| Audio MacBook on the network | Seen over Bonjour |
| Lamp bridge | WING Lamp Bridge 1.1 answered in 17 ms (7 ms on the status heartbeat) |
| WING | The bridge sees WING Port 4 |
| Lamp | LiveCue's own 3 s flash; **Shane saw it flash** |

So sending from LiveCue itself is now verified, along with the bridge's ping
answer over the real network. Before 1.1 was actually installed (files
copied but the installer not run), no reply reached the stage Mac. Copying
the files isn't enough; run Install WING Lamp Bridge.command.

## Nov 21, later: spoken rule works end to end

LiveCue 1.3.0 listened on Dante Virtual Soundcard input 1 (talkback), with the
WING FOH PRESET rule ("Front of House", contains, 3.2 s cooldown). Shane said it
on talkback:

| Heard | Result |
| --- | --- |
| "Friend of house." | No fire: the speech engine misheard |
| "Check, check." | No fire (correct) |
| "Front of house." | Rule fired, 3 s flash, **Shane saw the lamp flash** |

So the full path is verified on hardware: talkback → Dante → LiveCue speech →
rule → network → WING Lamp Bridge 1.1 → WING Port 4 → lamp. LiveCue reported
"48000 Hz / 16 inputs: signal on input 1", so the multi-input Dante capture fix
(`c6d211e`) also works on real hardware. Watch for
misrecognition ("Friend of house"). If it's common, rules could take alternate
phrasings.

Still to check: the bridge comes back after the audio MacBook restarts
(automatic login).

## Not yet verified

- The bridge restarting by itself after the audio MacBook reboots.

## Test script

`scripts/NetworkLampFlash.swift` sends only `B5 10 xx` to a named network
destination and always ends with OFF. It's built with Apple frameworks only.

```sh
swiftc scripts/NetworkLampFlash.swift -o /tmp/lamp
/tmp/lamp "Network RTP Session 1"                       # one 3 s flash, 250 ms steps
/tmp/lamp "Network RTP Session 1" --loop /tmp/lamp.stop  # 500 ms until the file exists
touch /tmp/lamp.stop                                     # stop the loop, sends OFF
```

That bridge now exists: [tools/WINGLampBridge](../../tools/WINGLampBridge/README.md)
(headless, starts at login, lamp-only). Flashed the lamp on Nov 21 (see above).
