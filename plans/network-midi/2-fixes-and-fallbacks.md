# Fixes and fallbacks

Pick the section that matches what the [runbook](1-church-day-runbook.md) showed.

## Fix S: Stale WING port (Test 2 passed, Test 3 fixed it)

Live routing was pointing at an old copy of WING Port 4.

- **Fix:** keep only one WING device in MIDI Studio, and keep the WING on the same USB port every week.
- **If it goes stale again** after a WING power-cycle or replug, the fix is the same: blank the bottom menu, close and reopen the window, then pick WING Port 4 again. Add this to the Sunday checklist.

## Fix R: A reset fixed it (Test 4)

Note which reset fixed it, then run "Lock it in". If it breaks again after a
restart, the stored routing is likely being corrupted. Repeat the reset that
worked and tell Claude, so we can decide whether Fix B below is the safer
long-term option.

## Fix T: Timestamps in the future (Test 1 or 2 showed delay)

Live routing keeps the network timestamp. CoreMIDI then holds each message until
that time, and drops it if anything disconnects first. The helper "worked"
because it always sends with timestamp 0.

Try these in order, re-running Test 1 after each:

1. In AMS Network, select the stage Mac in the participant list. If the session shows a **Latency** value above 0, set it to 0, on both Macs.
2. Have the stage Mac disconnect and reconnect. Clock sync is redone when a session connects.
3. Restart both Macs, then reconnect.
4. Remaining delay can't be fixed on the sender side. LiveCue already sends with timestamp 0; the timestamp is added by the network link between macOS 26 and Monterey. If the delay doesn't go away, that link is the problem, so use Fix B or C.

## Live routing doesn't work on this Mac at all (Test 4 failed, 5a worked)

Audio MIDI Setup can't do the job on this MacBook. These are the realistic
options, best first:

### Fix B: Invisible bridge, no window (free, can be done the same day)

Turn the helper into a background service that starts at login and has no window
or menu, so nothing needs to be opened. It's still technically a helper, but
there's nothing to run or click on a Sunday. It would:

- forward only ch 6 CC 16, the same as today
- reconnect automatically when the WING or network session comes back
- start automatically through a LaunchAgent

Effort: about an hour. Lowest cost, and uses the part that's already proven.

### Fix C: Newer Mac at the WING

A Mac whose Live routing works in Test 5 (for example any Apple Silicon Mac) does
the routing natively. It also lets LiveCue itself (macOS 26+) run at the console
if that's ever wanted.

### Fix D: Network-MIDI hardware into the WING's MIDI IN

A box that speaks Apple network MIDI (RTP-MIDI) on Ethernet and outputs 5-pin
MIDI into the WING's rear MIDI IN. This takes the audio MacBook out of the chain
entirely. iConnectivity's mio range is one example.

**Check before buying:**

- Can the WING's Custom Controls receive from MIDI DIN instead of USB?
- Does the specific model support RTP-MIDI?

### Not recommended

- **OpenCore Legacy Patcher** (to put a newer macOS on the 2016 MacBook Pro). Unsupported, and risky on the church's main audio machine.
- **OSC straight to the WING over the network.** The WING supports OSC, but this means the stage Mac talks to the WING directly, which goes against the setup goal.

## Order of decisions

```text
Test 2 forwards? ── yes ─> Test 3 fixes WING Port 4? ── yes ─> Fix S, lock it in
                │                                    └─ no ──> MIDI Monitor spy, Fix T if delayed
                └─ no ──> Test 4 resets ── one works ─> Fix R, lock it in
                                        └─ none ──> Test 5a ── stage Mac works ─> Monterey: Fix B now, C or D later
                                                            └─ also fails ────> session/network setup, tell Claude
```
