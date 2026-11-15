#!/usr/bin/env python3
"""Minimal Apple network MIDI (RTP-MIDI) peer for diagnostics. Standard library only.

  rtppeer.py capture <host> <seconds>                 join a session, print every MIDI packet it sends us
  rtppeer.py send <host> <offset_ms> [<offset_ms>..]  join, then send lamp ON/OFF pairs stamped now+offset

Clock unit is 100 microseconds, as in the protocol.
"""
import os, select, socket, struct, sys, time

NAME = b"LiveCue rtppeer\0"
SSRC = struct.unpack(">I", os.urandom(4))[0]
TOKEN = struct.unpack(">I", os.urandom(4))[0]
T0 = time.monotonic()


def now():
    return int((time.monotonic() - T0) * 10000) + 1_000_000


def wall():
    t = time.time()
    return time.strftime("%H:%M:%S", time.localtime(t)) + ".%03d" % int(t % 1 * 1000)


host = sys.argv[2]
ctrl = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
data = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
ctrl.bind(("", 6004))
data.bind(("", 6005))
CTRL, DATA = (host, 5004), (host, 5005)


def invite(sock, addr):
    sock.sendto(b"\xff\xffIN" + struct.pack(">III", 2, TOKEN, SSRC) + NAME, addr)
    sock.settimeout(3)
    reply, _ = sock.recvfrom(2048)
    kind = reply[2:4].decode()
    name = reply[16:].split(b"\0")[0].decode(errors="replace")
    print(f"invite {addr[1]}: {kind} from \"{name}\"")
    if kind != "OK":
        sys.exit(1)
    return struct.unpack(">I", reply[12:16])[0]


invite(ctrl, CTRL)
remote_ssrc = invite(data, DATA)

offset = None  # remote clock minus ours


def sync():
    data.sendto(b"\xff\xffCK" + struct.pack(">IB3xQQQ", SSRC, 0, now(), 0, 0), DATA)


def handle(pkt, sock):
    global offset
    if pkt[:4] == b"\xff\xffCK":
        _, count, t1, t2, t3 = struct.unpack(">IB3xQQQ", pkt[4:36])
        if count == 1:
            t3 = now()
            data.sendto(b"\xff\xffCK" + struct.pack(">IB3xQQQ", SSRC, 2, t1, t2, t3), DATA)
            offset = t2 - (t1 + t3) // 2
            print(f"{wall()}  sync: round trip {(t3 - t1) / 10:.1f} ms, remote clock offset {offset}")
        elif count == 0:  # remote started a sync
            data.sendto(b"\xff\xffCK" + struct.pack(">IB3xQQQ", SSRC, 1, t1, now(), 0), DATA)
        return
    if pkt[:4] == b"\xff\xffBY":
        print(f"{wall()}  remote said BY")
        sys.exit(0)
    if pkt[:2] == b"\xff\xff":
        print(f"{wall()}  command {pkt[2:4]!r}")
        return
    if pkt[0] & 0xC0 == 0x80:  # RTP
        seq, stamp, _ = struct.unpack(">HII", pkt[2:12])
        head = pkt[12]
        if head & 0x80:
            length, body = ((head & 0x0F) << 8) | pkt[13], 14
        else:
            length, body = head & 0x0F, 13
        midi = pkt[body:body + length]
        timing = "no sync yet"
        if offset is not None:
            remote_now = (now() + offset) & 0xFFFFFFFF
            diff = (stamp - remote_now + (1 << 31)) % (1 << 32) - (1 << 31)
            timing = f"RTP timestamp {diff / 10:+.1f} ms vs sender's clock on arrival"
        flags = "".join(f for f, bit in zip("BJZP", (0x80, 0x40, 0x20, 0x10)) if head & bit) or "-"
        if os.environ.get("RAW"): print("    raw", pkt.hex(" "))
        print(f"{wall()}  seq {seq}  midi [{midi.hex(' ').upper()}]  flags {flags}  {timing}")
        ctrl.sendto(b"\xff\xffRS" + struct.pack(">IHxx", SSRC, seq), CTRL)


def pump(seconds):
    end = time.monotonic() + seconds
    while True:
        left = end - time.monotonic()
        if left <= 0:
            return
        ready, _, _ = select.select([ctrl, data], [], [], left)
        for sock in ready:
            pkt, _ = sock.recvfrom(2048)
            handle(pkt, sock)


def bye():
    ctrl.sendto(b"\xff\xffBY" + struct.pack(">III", 2, TOKEN, SSRC), CTRL)


for _ in range(3):
    sync()
    pump(0.3)

if sys.argv[1] == "capture":
    seconds = float(sys.argv[3])
    end = time.monotonic() + seconds
    print("READY")
    sys.stdout.flush()
    while time.monotonic() < end:
        sync()
        pump(1.0)
        sys.stdout.flush()
elif sys.argv[1] == "send":
    seq = 1
    for off_ms in [float(a) for a in sys.argv[3:]]:
        for value in (0x7F, 0x00):
            stamp = (now() + int(off_ms * 10)) & 0xFFFFFFFF
            rtp = struct.pack(">BBHII", 0x80, 0x61, seq, stamp, SSRC)
            data.sendto(rtp + bytes([0x03, 0xB5, 0x10, value]), DATA)
            print(f"{wall()}  sent B5 10 {value:02X} stamped {off_ms:+.0f} ms")
            seq += 1
            pump(0.4)
        sync()
        pump(0.3)
    pump(3.0)
bye()
