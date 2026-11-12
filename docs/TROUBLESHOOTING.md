# WING setup and troubleshooting

Operator notes for the WING lamp preset, network MIDI and Dante input.

## WING “Front of House” lamp test

In Keyword Rules, click **WING FOH PRESET**. This adds a case-insensitive
contains-phrase rule with a 3.2-second cooldown. Its Test button and spoken
“Front of House” send MIDI channel **6**, CC **16**, alternating **127 / 0**
every 250 ms for three seconds, ending at **0** (off). Retriggering restarts
the three-second sequence. The mapping matches Layer 2, encoder 1 assigned
to OTHER → LAMP BRIGHTNESS in the supplied console photos.

Connect this app's Network MIDI destination to the receiving Mac's enabled
Network MIDI session. On that Mac, bridge the network session input to the
WING USB **remote-control** MIDI destination (not its DAW control port).
Enable **Custom Controls (RX Only) → USB** in WING Setup → MIDI.
Keep Layer 2 encoder 1 assigned to Lamp Brightness. First use the rule's
**Test** button, then start transcription and say “Front of House”.
The app sends through the selected network destinations; select only the
intended bridge for this test. Physical lamp response needs verification
on the connected console.

## Troubleshooting MIDI and Dante input (v1.1.1)

LiveCue preserves participants connected in Audio MIDI Setup and imports them
into its Network MIDI list. Explicitly switching a destination off still
removes that participant. The session broadcasts to its connected participants.
The accepted-message counter confirms a successful local CoreMIDI send, not
receipt by the other Mac or the WING. On the USB bridge Mac, route incoming
network MIDI (bottom Live routings selector) to WING Port 4 / MIDI Control.

With recording running, the transcript tab reports the opened audio format and
whether the selected device is delivering callbacks, silent buffers, or signal
on a particular input. Select Dante Virtual Soundcard and enable a track mapped
to Input 1 when the mic is subscribed to Dante receive channel 1. Device selection
is verified against the opened AudioUnit. Inactive formats fail explicitly.
Hardware behavior still requires checking on the actual Dante/WING system.

## Memory and long sessions

Live audio input is bounded to 32 queued buffers per channel. If recognition
cannot keep up, capture stops with a visible error; lower the enabled channel
count before restarting. File transcription waits for queue capacity instead
of dropping audio. Mono conversion scratch buffers are reused, while buffers
queued for recognition remain independently owned. Peak metering uses Accelerate.

The live transcript keeps 500–600 recent lines. Older lines are archived in
atomic batches in the system temporary directory and included in session saves
and exports. Clear/New Session removes that session's temporary history. If an
archive write fails, lines stay in memory and a status message reports the error.
Save sessions normally to keep them permanently. Opening, saving, and exporting
large sessions still temporarily materializes the full transcript in memory.
Export previews are snapshots and are generated once per selected format.

Regression checks (no microphone or speech model download required):

```sh
sh scripts/test-memory.sh
```

These check a 20,000-line transcript round trip, archive write failure,
bounded audio overload behavior, and queued audio ownership during buffer reuse.
They do not measure Apple's speech-engine RAM consumption; live multi-channel
memory and latency still depend on hardware, audio format, and enabled channels.

