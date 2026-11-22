# Update log

## 1.4.2 (Nov 21, 2026)

**Input gain per channel.**
- A **GAIN** slider on every channel in the Channels tab, from −24 dB to +24 dB with a **0** reset button. Turn it down when a mic is too hot, or up when it's too quiet. It works while LiveCue is listening and is saved with the channel.
- The gain changes what the speech engine hears, and the level meters show the level after gain.

**Honest level meters.**
- The meters used to add +12 dB on purpose, so normal speech at −12 dB already showed red. They now show the real level: green for normal, amber from −12 dB, red only above −3 dB.
- A red **CLIP** badge appears when the level after gain hits full scale. Turn the gain down.
- A red **INPUT CLIPPING** badge appears when the signal is already clipped before it reaches LiveCue. Turn it down at the source, on the WING or Dante send. LiveCue's gain can't undo distortion that happened earlier.
- The transcript screen's channel strip shows the CLIP badge and the gain setting too.

## 1.4.1 (Nov 21, 2026)

- **Adjustable WING lamp flash:** presets (Quick blink, Pulse, Slow blink, Long flash), or your own time on, time off, number of flashes (1–20) and brightness, with a preview. Used by the Front of House rule, the FLASH button and Test Connection. The lamp always ends off.
- **Cleaner Network MIDI tab:** "Send to" and "WING Lamp" up front, the technical settings under **Advanced**.

## 1.3.0 (Nov 21, 2026)

- **Test Connection** checks every step from this Mac to the WING lamp and explains each problem in plain words.
- **Status window** showing what's working right now, plus a **BRIDGE ONLINE** light in the status bar.
- **WING Lamp Bridge 1.1** answers LiveCue's connection check. Its installer is built into the app.
- **Fixes:**
  - Whole-word keyword matching ("cue 1" no longer fires on "cue 10").
  - An honest "nothing was sent" banner when a cue fails.
  - The last words before Stop are no longer lost.
  - The audio device is remembered.
  - A save prompt on quit, new session and open.
  - The MSC FIRE command is fixed.

## WING Lamp Bridge 1.1.0 (Nov 21, 2026)

- Answers LiveCue 1.3+'s connection check. Forwards only the lamp control, starts at login, and has no window.

## Earlier

See the [releases page](https://github.com/Shanetabr/LiveCue/releases) for 1.2.0 and before.
