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
static unsigned char reply[64]; static int nReply;

static void replyRead(const MIDIPacketList *l, void *a, void *b) {
    const MIDIPacket *p = &l->packet[0];
    pthread_mutex_lock(&mu);
    for (UInt32 i = 0; i < l->numPackets; i++) {
        for (int j = 0; j < p->length && nReply < 64; j++) reply[nReply++] = p->data[j];
        p = MIDIPacketNext(p);
    }
    pthread_mutex_unlock(&mu);
}

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

    MIDIClientRef c; MIDIEndpointRef src, dst, back;
    MIDIClientCreate(CFSTR("bridge test"), NULL, NULL, &c);
    MIDISourceCreate(c, CFSTR("LCBTEST-SRC"), &src);
    MIDIDestinationCreate(c, CFSTR("LCBTEST DST"), destRead, NULL, &dst);
    MIDIDestinationCreate(c, CFSTR("LCBTEST-SRC reply"), replyRead, NULL, &back);  // the "network" side
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

    // Connection-test ping: answered on the network side, never forwarded to the WING.
    unsigned char ping[] = {0xF0, 0x7D, 0x4C, 0x43, 0x01, 0x2A, 0xF7};
    p = MIDIPacketListInit(&pl);
    MIDIPacketListAdd(&pl, sizeof pl, p, 0, sizeof ping, ping);
    MIDIReceived(src, &pl);
    for (double t = 0; t < 3; t += 0.05) {
        pthread_mutex_lock(&mu); int k = nReply; pthread_mutex_unlock(&mu);
        if (k >= 10) break;
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, false);
    }
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.3, false);
    pthread_mutex_lock(&mu);
    unsigned char wantReply[] = {0xF0, 0x7D, 0x4C, 0x43, 0x02, 0x2A, 0x01, 0x01, 0x01, 0xF7};
    int pong = nReply == 10 && !memcmp(reply, wantReply, 10) && nGot == 0;
    pthread_mutex_unlock(&mu);

    kill(pid, SIGTERM);
    int ok2 = waitFor(3, 2);
    pthread_mutex_lock(&mu);
    int off = ok2 && got[0] == 0xB5 && got[1] == 0x10 && got[2] == 0x00;
    pthread_mutex_unlock(&mu);
    int st; waitpid(pid, &st, 0);

    printf("%s: picked up ports added after start, forwarded only lamp ON/OFF (running status, other CCs and realtime filtered)\n", exact ? "PASS" : "FAIL");
    printf("%s: answered the connection-test ping (WING seen, v1.1) and sent nothing to the WING\n", pong ? "PASS" : "FAIL");
    printf("%s: sent lamp OFF on stop\n", off ? "PASS" : "FAIL");
    MIDIEndpointDispose(src); MIDIEndpointDispose(dst); MIDIEndpointDispose(back); MIDIClientDispose(c);
    return exact && pong && off ? 0 : 1;
}
