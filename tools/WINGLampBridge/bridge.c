// WING Lamp Bridge: headless version of tools/WINGLampReceiver for the audio MacBook.
// Listens on every CoreMIDI source whose name matches --source (default "Network"),
// forwards ONLY channel 6 CC16 (B5 10 xx) to the destination whose name contains every
// comma-separated part of --dest (default "WING,Port 4"). No window, no Dock icon.
// Rescans when MIDI setup changes and every 5 s, so a replugged WING or a reconnected
// network session is picked up. Sends lamp OFF when it exits.
//
// Connection test (v1.1): LiveCue sends a ping SysEx  F0 7D 4C 43 01 <nonce> F7
// over the network session. The bridge answers on every network destination with
//   F0 7D 4C 43 02 <nonce> <wing 0/1> <major> <minor> F7
// (0x7D = non-commercial ID, 4C 43 = "LC"). Pings are never forwarded to the WING.
//
// Usage: wing-lamp-bridge [--source TEXT] [--dest A,B] [--flash] [--list] [--version]
//   --flash  send a 3 s flash directly to the WING and exit (local USB test)
//   --list   print MIDI sources and destinations and exit

#include <CoreFoundation/CoreFoundation.h>
#include <CoreMIDI/CoreMIDI.h>
#include <pthread.h>
#include <signal.h>
#include <stdarg.h>
#include <stdatomic.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define MAX_SRC 16
#define VERSION_MAJOR 1
#define VERSION_MINOR 1

static const char *srcMatch = "Network";
static const char *destMatch = "WING,Port 4";
static MIDIClientRef client;
static MIDIPortRef inPort, outPort;
static _Atomic MIDIEndpointRef dest;
static MIDIEndpointRef connected[MAX_SRC];
static int nConnected;
static MIDIEndpointRef replyTo[MAX_SRC];   // network destinations, for ping replies
static int nReplyTo;
static pthread_mutex_t replyLock = PTHREAD_MUTEX_INITIALIZER;
static atomic_ulong received, lampCmds, sendsOK, pings;

typedef struct {
    unsigned char status, data0; int count;
    int inSysex; unsigned char sx[16]; int sxLen;
} Parser;
static Parser parsers[MAX_SRC];

static void logf_(const char *fmt, ...) {
    char ts[32]; time_t t = time(NULL);
    strftime(ts, sizeof ts, "%Y-%m-%d %H:%M:%S", localtime(&t));
    printf("%s ", ts);
    va_list ap; va_start(ap, fmt); vprintf(fmt, ap); va_end(ap);
    printf("\n"); fflush(stdout);
}

static void name(MIDIObjectRef o, char *buf, size_t n) {
    CFStringRef s = NULL; buf[0] = 0;
    if (MIDIObjectGetStringProperty(o, kMIDIPropertyDisplayName, &s) == noErr && s) {
        CFStringGetCString(s, buf, (CFIndex)n, kCFStringEncodingUTF8); CFRelease(s);
    }
}

static int containsCI(const char *hay, const char *needle) { return strcasestr(hay, needle) != NULL; }

static int matchesAll(const char *hay, const char *list) {
    char copy[256]; strlcpy(copy, list, sizeof copy);
    for (char *tok = strtok(copy, ","); tok; tok = strtok(NULL, ","))
        if (!containsCI(hay, tok)) return 0;
    return 1;
}

static OSStatus sendLamp(unsigned char value) {
    MIDIEndpointRef d = atomic_load(&dest);
    if (!d) return kMIDIInvalidClient;
    MIDIPacketList list; MIDIPacket *p = MIDIPacketListInit(&list);
    unsigned char bytes[3] = {0xB5, 0x10, value};
    MIDIPacketListAdd(&list, sizeof list, p, 0, 3, bytes);
    return MIDISend(outPort, d, &list);
}

static void sendBytes(MIDIEndpointRef d, const unsigned char *bytes, int n) {
    MIDIPacketList list; MIDIPacket *p = MIDIPacketListInit(&list);
    MIDIPacketListAdd(&list, sizeof list, p, 0, n, bytes);
    MIDISend(outPort, d, &list);
}

// A complete SysEx body (without F0/F7). Answers LiveCue's connection-test ping.
static void handleSysex(const unsigned char *sx, int n) {
    if (n != 5 || sx[0] != 0x7D || sx[1] != 0x4C || sx[2] != 0x43 || sx[3] != 0x01) return;
    unsigned char reply[10] = {0xF0, 0x7D, 0x4C, 0x43, 0x02, sx[4] & 0x7F,
                               atomic_load(&dest) ? 1 : 0, VERSION_MAJOR, VERSION_MINOR, 0xF7};
    pthread_mutex_lock(&replyLock);
    for (int i = 0; i < nReplyTo; i++) sendBytes(replyTo[i], reply, sizeof reply);
    pthread_mutex_unlock(&replyLock);
    atomic_fetch_add(&pings, 1);
}

// Same parser as WINGLampReceiver: handles running status, skips realtime.
// SysEx is collected only to answer pings; it is never forwarded.
static void readProc(const MIDIPacketList *list, void *portRef, void *srcRef) {
    Parser *ps = &parsers[(long)srcRef % MAX_SRC];
    const MIDIPacket *pk = &list->packet[0];
    for (UInt32 i = 0; i < list->numPackets; i++) {
        atomic_fetch_add(&received, 1);
        for (UInt16 j = 0; j < pk->length; j++) {
            unsigned char b = pk->data[j];
            if (b >= 0xF8) continue;
            if (b == 0xF0) { ps->inSysex = 1; ps->sxLen = 0; ps->status = 0; ps->count = 0; continue; }
            if (b == 0xF7) { if (ps->inSysex) handleSysex(ps->sx, ps->sxLen); ps->inSysex = 0; continue; }
            if (ps->inSysex) {
                if (!(b & 0x80)) { if (ps->sxLen < (int)sizeof ps->sx) ps->sx[ps->sxLen] = b; ps->sxLen++; continue; }
                ps->inSysex = 0;  // a status byte ends a broken SysEx
            }
            if (b & 0x80) { ps->status = b < 0xF0 ? b : 0; ps->count = 0; continue; }
            if (!ps->status) continue;
            if (ps->count == 0) {
                ps->data0 = b; ps->count = 1;
                if ((ps->status & 0xF0) == 0xC0 || (ps->status & 0xF0) == 0xD0) ps->count = 0;
            } else {
                if (ps->status == 0xB5 && ps->data0 == 0x10) {
                    atomic_fetch_add(&lampCmds, 1);
                    OSStatus r = sendLamp(b);
                    if (r == noErr) atomic_fetch_add(&sendsOK, 1);
                    logf_("lamp %s (B5 10 %02X) -> %s", b ? "ON" : "OFF", b, r == noErr ? "sent" : "SEND FAILED");
                }
                ps->count = 0;
            }
        }
        pk = MIDIPacketNext(pk);
    }
}

static void rescan(void) {
    char buf[256];
    MIDIEndpointRef found = 0; char foundName[256] = "";
    for (ItemCount i = 0; i < MIDIGetNumberOfDestinations(); i++) {
        MIDIEndpointRef e = MIDIGetDestination(i); name(e, buf, sizeof buf);
        if (matchesAll(buf, destMatch)) { found = e; strlcpy(foundName, buf, sizeof foundName); break; }
    }
    if (found != atomic_load(&dest)) {
        atomic_store(&dest, found);
        if (found) logf_("WING output: %s", foundName); else logf_("WING output missing (looking for \"%s\")", destMatch);
    }

    pthread_mutex_lock(&replyLock);
    nReplyTo = 0;
    for (ItemCount i = 0; i < MIDIGetNumberOfDestinations() && nReplyTo < MAX_SRC; i++) {
        MIDIEndpointRef e = MIDIGetDestination(i); name(e, buf, sizeof buf);
        if (containsCI(buf, srcMatch)) replyTo[nReplyTo++] = e;
    }
    pthread_mutex_unlock(&replyLock);

    MIDIEndpointRef want[MAX_SRC]; int nWant = 0;
    for (ItemCount i = 0; i < MIDIGetNumberOfSources() && nWant < MAX_SRC; i++) {
        MIDIEndpointRef e = MIDIGetSource(i); name(e, buf, sizeof buf);
        if (containsCI(buf, srcMatch)) want[nWant++] = e;
    }
    int same = nWant == nConnected;
    for (int i = 0; same && i < nWant; i++) same = want[i] == connected[i];
    if (same) return;
    for (int i = 0; i < nConnected; i++) MIDIPortDisconnectSource(inPort, connected[i]);
    nConnected = 0;
    for (int i = 0; i < nWant; i++) {
        memset(&parsers[i], 0, sizeof parsers[i]);
        name(want[i], buf, sizeof buf);
        if (MIDIPortConnectSource(inPort, want[i], (void *)(long)i) == noErr) {
            connected[nConnected++] = want[i]; logf_("listening on: %s", buf);
        } else logf_("cannot open input: %s", buf);
    }
    if (!nWant) logf_("network input missing (looking for \"%s\")", srcMatch);
}

static void notifyProc(const MIDINotification *n, void *ref) {
    if (n->messageID == kMIDIMsgSetupChanged) rescan();
}

static void timerProc(CFRunLoopTimerRef t, void *info) { rescan(); }

static void heartbeat(CFRunLoopTimerRef t, void *info) {
    logf_("alive: received %lu, lamp commands %lu, USB sends accepted %lu, test pings answered %lu",
          atomic_load(&received), atomic_load(&lampCmds), atomic_load(&sendsOK), atomic_load(&pings));
}

static void onSignal(int sig) {
    sendLamp(0); usleep(50000);
    logf_("stopping (signal %d), lamp OFF sent", sig);
    _exit(0);
}

static void listEndpoints(void) {
    char buf[256];
    printf("Sources:\n");
    for (ItemCount i = 0; i < MIDIGetNumberOfSources(); i++) { name(MIDIGetSource(i), buf, sizeof buf); printf("  %s\n", buf); }
    printf("Destinations:\n");
    for (ItemCount i = 0; i < MIDIGetNumberOfDestinations(); i++) { name(MIDIGetDestination(i), buf, sizeof buf); printf("  %s\n", buf); }
}

int main(int argc, char **argv) {
    int flash = 0, list = 0;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--source") && i + 1 < argc) srcMatch = argv[++i];
        else if (!strcmp(argv[i], "--dest") && i + 1 < argc) destMatch = argv[++i];
        else if (!strcmp(argv[i], "--flash")) flash = 1;
        else if (!strcmp(argv[i], "--list")) list = 1;
        else if (!strcmp(argv[i], "--version")) { printf("WING Lamp Bridge %d.%d\n", VERSION_MAJOR, VERSION_MINOR); return 0; }
        else { fprintf(stderr, "usage: %s [--source TEXT] [--dest A,B] [--flash] [--list] [--version]\n", argv[0]); return 2; }
    }

    OSStatus s = MIDIClientCreate(CFSTR("WING Lamp Bridge"), notifyProc, NULL, &client);
    if (s == noErr) s = MIDIOutputPortCreate(client, CFSTR("WING Lamp Output"), &outPort);
    if (s == noErr) s = MIDIInputPortCreate(client, CFSTR("Network Lamp Input"), readProc, NULL, &inPort);
    if (s != noErr) { logf_("MIDI setup failed: %d", (int)s); return 1; }

    if (list) { listEndpoints(); return 0; }

    rescan();
    if (flash) {
        if (!atomic_load(&dest)) { logf_("no WING output found"); return 1; }
        for (int i = 0; i < 12; i++) { logf_("flash %s, status %d", i % 2 ? "OFF" : "ON", (int)sendLamp(i % 2 ? 0 : 127)); usleep(250000); }
        sendLamp(0); usleep(50000); logf_("flash done, lamp OFF");
        return 0;
    }

    signal(SIGTERM, onSignal); signal(SIGINT, onSignal);
    logf_("WING Lamp Bridge %d.%d started (source \"%s\", output \"%s\")", VERSION_MAJOR, VERSION_MINOR, srcMatch, destMatch);
    CFRunLoopAddTimer(CFRunLoopGetCurrent(),
        CFRunLoopTimerCreate(NULL, CFAbsoluteTimeGetCurrent() + 5, 5, 0, 0, timerProc, NULL), kCFRunLoopCommonModes);
    CFRunLoopAddTimer(CFRunLoopGetCurrent(),
        CFRunLoopTimerCreate(NULL, CFAbsoluteTimeGetCurrent() + 3600, 3600, 0, 0, heartbeat, NULL), kCFRunLoopCommonModes);
    CFRunLoopRun();
    return 0;
}
