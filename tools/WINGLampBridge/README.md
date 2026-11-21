# WING Lamp Bridge

Invisible background version of the WING Lamp Receiver helper, for the
**audio MacBook** (the one plugged into the WING by USB). It has no window
and no Dock icon. It starts at login and restarts itself if it stops.

It listens on the network MIDI session from the stage Mac and forwards
**only** channel 6 CC16 (the lamp, `B5 10 xx`) to **WING Port 4**. If the
WING is unplugged or the network session drops, it waits and reconnects
by itself. When it stops, it sends lamp OFF.

This is the fallback from `docs/dev-notes/NETWORK_MIDI_FINDINGS.md`: Audio MIDI
Setup Live routing didn't flash the lamp, but the helper's approach did.

**Separate from LiveCue.** The bridge doesn't need LiveCue, Swift or Xcode on
the audio MacBook. It's one small program (`bridge.c`, Apple's CoreMIDI only),
and this folder builds on its own. LiveCue keeps running on the stage Mac as
usual. Works on macOS 11 and later, Intel and Apple Silicon.

## Get the zip

**Download:** [WINGLampBridge.zip](https://github.com/Shanetabr/LiveCue/releases/download/wing-lamp-bridge-v1.1.0/WINGLampBridge.zip)
([release page](https://github.com/Shanetabr/LiveCue/releases/tag/wing-lamp-bridge-v1.1.0)).
It's ready to install, with nothing to build.

Or download it in Terminal on the audio MacBook. That way macOS doesn't ask
about it when you open it:

    curl -L -o ~/Desktop/WINGLampBridge.zip https://github.com/Shanetabr/LiveCue/releases/download/wing-lamp-bridge-v1.1.0/WINGLampBridge.zip
    cd ~/Desktop && unzip -o WINGLampBridge.zip

To build it yourself instead, use any Mac with Xcode's command line tools:

    sh tools/WINGLampBridge/build.sh     # -> tools/WINGLampBridge/dist/WINGLampBridge.zip

Then copy `WINGLampBridge.zip` to the audio MacBook with a USB stick, AirDrop,
or over the Ethernet cable:

    # stage Mac
    python3 -m http.server 8765 --bind <stage-mac-ip> --directory tools/WINGLampBridge/dist
    # audio MacBook (Terminal)
    curl -o ~/Desktop/WINGLampBridge.zip http://<stage-mac-ip>:8765/WINGLampBridge.zip

`curl` doesn't mark the file as downloaded, so macOS won't ask about it.

## Install on the audio MacBook

1. Unzip `WINGLampBridge.zip`.
2. Right-click **Install WING Lamp Bridge.command** and choose **Open**.
   If the zip came from a browser, AirDrop or a USB stick, macOS asks if
   you're sure the first time, so click **Open** again.
3. In Audio MIDI Setup → Network, set **both** Live routings to blank.
   Otherwise the lamp could be sent twice.
4. Quit the WING Lamp Receiver window app if it's open.

## So it starts on boot with nobody there

A background helper like this one starts when a user logs in. To make it
start when the Mac powers on, turn on automatic login for that user in
System Preferences → Users & Groups → Login Options → Automatic login.
FileVault must be off for automatic login to be available.

## Connection test (version 1.1)

LiveCue 1.3's **Test Connection** button and Status window ask the bridge
"are you there?" over the network. Version 1.1 answers with whether it can
see WING Port 4. The question is never sent to the WING. Version 1.0 still
flashes the lamp but can't answer, so LiveCue shows "bridge not answering"
until you install 1.1. Installing over 1.0 replaces it. Run
`wing-lamp-bridge --version` to see which one is installed.

LiveCue carries this installer inside it: **Connection → Get Bridge Installer
for the Audio MacBook** saves the zip to Downloads.

## Check it

- **Test Lamp Flash.command**: lists the MIDI ports, then flashes the lamp for
  3 s straight over USB from this Mac.
- Log: `~/Library/Logs/WINGLampBridge.log`. It shows which ports it is
  using, every lamp ON/OFF it forwards, and an hourly count.
- Is it running: `launchctl list | grep winglampbridge`

## Remove

Open **Uninstall WING Lamp Bridge.command**.

## Options

The defaults match "Network Session 1" and "WING Port 4". The installed
command can take `--source TEXT` (part of the network input name) and
`--dest A,B` (every part must appear in the output name). To use them, edit
`ProgramArguments` in `~/Library/LaunchAgents/com.livecue.winglampbridge.plist`.

## Test

With virtual MIDI ports (no console needed):

    sh tools/WINGLampBridge/test.sh
