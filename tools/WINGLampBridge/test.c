// Integration test with virtual CoreMIDI ports; no console is addressed.
// Starts the bridge BEFORE the ports exist (checks hot-plug pickup), injects lamp ON/OFF
// with running status plus an unrelated CC, then stops the bridge and expects a final OFF.
#include <CoreFoundation/CoreFoundation.h>
#include <CoreMIDI/CoreMIDI.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <pthread.h>
#include <sys/wait.h>

extern char **environ;
static unsigned char got[64]; static int nGot; static pthread_mutex_t mu = PTHREAD_MUTEX_INITIALIZER;

static void destRead(const MIDIPacketList *l, void *a, void *b) {
    const MIDIPacket *p = &l->packet[0];
    pthread_mutex_lock(&mu);
    for (UInt32 i = 0; i < l->numPackets; i++) {
        for (int j = 0; j < p->length && nGot < 64; j++) got[nGot++] = p->data[j];
        p = MIDIPacketNext(p);
    }
    pthread_mutex_unlock(&mu);
}

static int waitFor(int n, double secs) {
    for (double t = 0; t < secs; t += 0.05) {
        pthread_mutex_lock(&mu); int k = nGot; pthread_mutex_unlock(&mu);
        if (k >= n) return 1;
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, false);
    }
    return 0;
}

int main(int argc, char **argv) {
    pid_t pid; char *args[] = {argv[1], "--source", "LCBTEST-SRC", "--dest", "LCBTEST,DST", NULL};
    if (posix_spawn(&pid, argv[1], NULL, NULL, args, environ)) { puts("FAIL: cannot start bridge"); return 1; }
    sleep(1);

    MIDIClientRef c; MIDIEndpointRef src, dst;
    MIDIClientCreate(CFSTR("bridge test"), NULL, NULL, &c);
    MIDISourceCreate(c, CFSTR("LCBTEST-SRC"), &src);
    MIDIDestinationCreate(c, CFSTR("LCBTEST DST"), destRead, NULL, &dst);
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 2.0, false);  // let the bridge see the new ports

    unsigned char bytes[] = {0xB5, 0x10, 0x7F, 0x10, 0x00, 0xB0, 0x11, 0x7F, 0xF8, 0xB5, 0x11, 0x7F};
    MIDIPacketList pl; MIDIPacket *p = MIDIPacketListInit(&pl);
    MIDIPacketListAdd(&pl, sizeof pl, p, 0, sizeof bytes, bytes);
    MIDIReceived(src, &pl);
    int ok1 = waitFor(6, 3);
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.3, false);  // catch anything extra
    pthread_mutex_lock(&mu);
    unsigned char want[] = {0xB5, 0x10, 0x7F, 0xB5, 0x10, 0x00};
    int exact = ok1 && nGot == 6 && !memcmp(got, want, 6);
    nGot = 0;
    pthread_mutex_unlock(&mu);

    kill(pid, SIGTERM);
    int ok2 = waitFor(3, 2);
    pthread_mutex_lock(&mu);
    int off = ok2 && got[0] == 0xB5 && got[1] == 0x10 && got[2] == 0x00;
    pthread_mutex_unlock(&mu);
    int st; waitpid(pid, &st, 0);

    printf("%s: picked up ports added after start, forwarded only lamp ON/OFF (running status, other CCs and realtime filtered)\n", exact ? "PASS" : "FAIL");
    printf("%s: sent lamp OFF on stop\n", off ? "PASS" : "FAIL");
    MIDIEndpointDispose(src); MIDIEndpointDispose(dst); MIDIClientDispose(c);
    return exact && off ? 0 : 1;
}
