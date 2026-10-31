# WING Lamp Receiver diagnostic

Run this on the Mac connected to the WING by USB. This standalone macOS 11+
app supports Intel and Apple Silicon and forwards ONLY MIDI channel 6 CC16.

1. Keep the existing Network MIDI session connected between the two Macs.
2. On the receiving Mac, leave both Audio MIDI Setup Live routings blank while
   testing this explicit bridge, to avoid two simultaneous forwarding paths.
3. Open WING Lamp Receiver, choose Network Session 1 as input and WING Port 4
   as output, and click Start bridge.
4. With the stage Mac sending the lamp loop, the network packet count, lamp
   command count and accepted USB send count should increase. Report these
   counts and the Last received hex text if the lamp remains dark.
5. Stop bridge ends the input subscription. Lamp OFF / Stop USB test stops
   the helper's own direct-USB test and sends OFF; it does not stop a separate
   stage sender, which can turn the lamp on again.

The Test USB flashing button is a separate local diagnostic, independent of
network input. It alternates 127/0 on channel 6 CC16 at half-second intervals.
Stop the stage sender or stop bridge first to avoid concurrent lamp sources.
Closing the app stops its local test, sends lamp OFF, and disposes its MIDI client.

CoreMIDI send success is not proof of console receipt. Physical response must
be observed. This helper does not change console settings, faders, mutes or
network routing. Build, GUI launch and virtual MIDI input-to-output integration
checks have passed. Physical flashing through the audio Mac remains unverified.

The stage Ethernet capture on 2026-10-30 confirmed outgoing channel 6 CC16
ON/OFF packets and matching receiver feedback from the audio Mac. This verifies
network transport to that Mac; the counters above isolate the remaining
CoreMIDI input-to-USB path.

Build:

    clang -fobjc-arc -arch arm64 -arch x86_64 -mmacosx-version-min=11.0 \
      -framework Cocoa -framework CoreMIDI main.m -o WINGLampReceiver

Integration check (no real console is addressed):

    clang -fobjc-arc -framework Cocoa -framework CoreMIDI test.m -o /tmp/wing-receiver-test
    /tmp/wing-receiver-test
