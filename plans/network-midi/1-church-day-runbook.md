# Church-day runbook

Expect about 45–60 minutes. **Don't run any of this during a service.**
Step 4 restarts MIDI on the audio MacBook.

Who does what:

- **Stage Mac:** Claude runs the commands from the Claude Code session.
- **Audio MacBook:** you, in Terminal and Audio MIDI Setup (AMS).

Do the steps in order. After each test, write the result in the sheet at the bottom.

## Before you start (5 min)

### 0a. Build the probe (stage Mac, Claude)

From the repo:

```bash
mkdir -p /tmp/probe-share
swiftc -swift-version 5 -O plans/network-midi/midiprobe.swift -o /tmp/midiprobe
swiftc -swift-version 5 -O -target x86_64-apple-macos12.0 plans/network-midi/midiprobe.swift -o /tmp/probe-share/midiprobe
python3 -m http.server 8765 --bind <stage-mac-ip> --directory /tmp/probe-share
```

The second build is the Intel version for the audio MacBook.

### 0b. Copy the probe to the audio MacBook

In Terminal:

```bash
curl -o ~/Desktop/midiprobe http://<stage-mac-ip>:8765/midiprobe && chmod +x ~/Desktop/midiprobe
```

`curl` copies it straight over the Ethernet cable and avoids the "unidentified
developer" block. If you use AirDrop instead, run
`xattr -d com.apple.quarantine ~/Desktop/midiprobe` afterwards.

### A1. Quit the helper on the audio MacBook

**Quit** the WING Lamp Receiver app (⌘Q), don't just stop it. Two forwarders at
once would confuse the results.

### A2. Clock check

On both Macs: System Settings → General → Date & Time → **Set time
automatically = On**. Later steps compare send and arrival times between the two
Macs.

### A3. Take inventory (audio MacBook)

```bash
~/Desktop/midiprobe list
```

Take a photo. Look for:

- More than one WING device, or a WING marked **OFFLINE**. This points to cause #1.
- More than one "Network …" source, meaning more than one session.
- The exact name of the network source. It was "Network Session 1" before. Use the name `list` shows in the steps below.

## Test 1: What arrives from the network, and with what timestamp? (5 min)

1. On the audio MacBook, set **both** Live routing menus to blank. Then run:

   ```bash
   ~/Desktop/midiprobe listen "Network Session 1"
   ```

2. On the stage Mac, Claude runs:

   ```bash
   /tmp/midiprobe flash "Network RTP Session 1"
   ```

| What you see on the audio MacBook | Meaning |
| --- | --- |
| 13 lines of `B5 10 7F` / `B5 10 00` with timestamps near 0 or a few ms negative | Normal. Timestamps aren't the problem; cause #3 is unlikely |
| Timestamps **+100 ms or more** ("from now"), or lines arriving noticeably after the stage Mac printed them | **Cause #3.** Messages are stamped in the future. Go to Fix T in [the fixes plan](2-fixes-and-fallbacks.md), then still do Test 2 |
| Nothing | Wrong source name, or the session dropped. Check `list` and the AMS participant list, then retry |

Press Ctrl-C to stop the listener.

## Test 2: Does Live routing forward anything at all? (10 min)

This is the key test. It takes the WING out of the picture.

1. On the audio MacBook:

   ```bash
   ~/Desktop/midiprobe dest
   ```

   This creates a destination called **LiveCue Probe**.

2. In AMS → Window → Show MIDI Studio → Network (globe icon):
   1. Under **My Sessions**, select the session whose **Participants** list shows the stage Mac as connected.
   2. Set the top Live routing to blank. Set the bottom one to **LiveCue Probe**.
3. On the stage Mac, Claude runs the flash again. Note the time it prints.

| What you see in the probe window | Meaning | Next |
| --- | --- | --- |
| 13 lines, arriving at the same time the stage Mac sent them | **Live routing works.** The problem is only the hop to WING Port 4 (cause #1) | Test 3 |
| Lines arrive, but seconds later | **Cause #3.** Timestamps delay the messages | Fix T |
| Nothing | **Live routing isn't forwarding** (cause #2, or Monterey) | Test 4, then repeat Test 2 after each reset |

## Test 3: Live routing to the WING, with a freshly picked port (10 min)

Only do this if Test 2 showed Live routing works.

1. Press Ctrl-C to stop `midiprobe dest`. Set the bottom menu to blank, close the Network window, reopen it, and pick **WING Port 4** from the bottom menu again.
2. Stage Mac flashes.
   - Lamp flashes → **fixed**. Go to "Lock it in" below.
3. If the lamp didn't flash, clean up the WING entries:
   1. In MIDI Studio, delete any greyed-out WING icons.
   2. Unplug the WING USB, wait 10 s, then plug it into a **different** USB port.
   3. Repeat step 1 of this test, then flash again.
4. Optional, if it still doesn't flash: install [MIDI Monitor](https://www.snoize.com/midimonitor/) (free, works on Monterey). Under Sources, tick **Spy on output to destinations → WING Port 4**, then flash.
   - Messages show up → Live routing is sending to the WING, but the WING ignores them. Note their timestamps.
   - Nothing shows up → Live routing never reaches the port.

## Test 4: Resets (only if Test 2 got nothing)

Repeat **Test 2** after each reset. Stop at the first one that works.

| # | Reset | How |
| --- | --- | --- |
| 4a | Apple forum workaround | Pick LiveCue Probe in **both** Live routing menus, close the Network window, reopen it, set the top menu back to blank and the bottom to LiveCue Probe |
| 4b | Wi-Fi off | Turn Wi-Fi off on the audio MacBook, so it only has Ethernet. Have the stage Mac disconnect and reconnect to the session |
| 4c | New session | Under My Sessions, remove (−) all sessions, add (+) one new one, tick it, set "Who may connect to me" to Anyone. Stage Mac reconnects. Set the bottom menu to LiveCue Probe |
| 4d | Restart CoreMIDI | Quit AMS and the probe. Run `sudo killall MIDIServer` (it restarts automatically). Reopen AMS, run `midiprobe dest`, redo the bottom menu |
| 4e | Full MIDI settings reset (undo-able) | See below |

**4e steps:**

1. Quit AMS.
2. Move the MIDI settings aside. These are the commonly reset files; if one doesn't exist, `mv` just reports it. Nothing is deleted:

   ```bash
   mkdir ~/Desktop/MIDI-backup
   mv ~/Library/Preferences/ByHost/com.apple.MIDI.* ~/Desktop/MIDI-backup/
   mv ~/Library/Audio/"MIDI Configurations" ~/Desktop/MIDI-backup/
   ```

3. Restart the Mac.
4. Rebuild the session and redo Test 2.

To undo, move the files back and restart. This clears any other MIDI setup on
that Mac, so check with whoever else uses it.

## Test 5: Is it Monterey? (optional, 15 min)

Do this if nothing in Test 4 worked. Swap roles so macOS 26 does the Live routing.

### 5a. No cables

1. On the audio MacBook, run `~/Desktop/midiprobe flash "Network Session 1" --loop`.
2. On the stage Mac, Claude runs `/tmp/midiprobe dest`.
3. In the stage Mac's AMS, set the session's bottom Live routing to **LiveCue Probe**.

If lines arrive on the stage Mac, macOS 26's Live routing works and Monterey's
doesn't. That points to the Mac or OS, not the setup.

### 5b. Full swap

Only do this if you want physical proof:

1. Plug the stage Mac into the WING's USB.
2. On the stage Mac, set the bottom menu to WING Port 4.
3. On the audio MacBook, run the flash loop.

Unplug afterwards. The final setup still never connects the stage Mac to the WING.

Press Ctrl-C to stop the loop. It sends OFF on the way out.

## Lock it in (once the lamp flashes through Live routing)

Make sure it survives a normal Sunday morning:

1. Take photos of the AMS Network window, both menus and the participants list.
2. Restart the audio MacBook. Check the session is still ticked and the bottom routing is still WING Port 4. Reconnect the stage Mac and flash.
3. Power-cycle the WING. Flash again.
4. Test from LiveCue's **FLASH 3 SECONDS** button, not just the probe.

If step 2 or 3 breaks it, note which. That tells us what needs redoing on startup.

## Results sheet

| Step | Result (what you saw) |
| --- | --- |
| A3 `list`: WING devices / offline / sessions | |
| 1 `listen`: lines? timestamps? | |
| 2 Live routing → LiveCue Probe | |
| 3 Live routing → WING Port 4 (fresh) | |
| 3 MIDI Monitor spy (optional) | |
| 4a / 4b / 4c / 4d / 4e | |
| 5a / 5b | |
| Lock it in: after restart / after WING power-cycle | |
