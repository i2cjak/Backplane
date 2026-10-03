# A raw WebSocket client for test/tools/stall_e2e.ts.
#   wsclient.py PORT QUERY MODE ARG
# MODE slow:  read at most ARG bytes a second; print "done BYTES SECS" when the
#             join's last frame ("boot": false, CBOR 64 'boot' f4) arrives, or
#             "EOF BYTES" / "ERR ..." if the hub hangs up
# MODE stall: connect, sleep ARG seconds without reading, then read: "EOF BYTES"
#             (dropped) or "done BYTES SECS" (the join went on)
# MODE pings: send ARG pings at once, then read for 3 s: "pongs N"
import socket, sys, time, os
port, query, mode, arg = int(sys.argv[1]), sys.argv[2], sys.argv[3], float(sys.argv[4])
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 16384)
s.connect(("127.0.0.1", port))
s.sendall(("GET /ws%s HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n" % query).encode())
print("connected", flush=True)
MARK = b"\x64boot\xf4"
t0 = time.time()
total = 0
tail = b""
def frames(buf):
    # complete frames in buf: (opcode, payload), rest
    out = []
    while len(buf) >= 2:
        op = buf[0] & 15
        n = buf[1] & 127
        at = 2
        if n == 126:
            if len(buf) < 4: break
            n = int.from_bytes(buf[2:4], "big"); at = 4
        elif n == 127:
            if len(buf) < 10: break
            n = int.from_bytes(buf[2:10], "big"); at = 10
        if len(buf) < at + n: break
        out.append((op, buf[at:at + n]))
        buf = buf[at + n:]
    return out, buf
if mode == "stall":
    time.sleep(arg)
if mode == "pings":
    head = s.recv(4096)
    one = bytes([0x89, 0x80 | 4]) + b"\x00\x00\x00\x00" + b"ping"
    s.sendall(one * int(arg))
    s.settimeout(0.5)
    end = time.time() + 3
    buf = b""
    pongs = 0
    while time.time() < end:
        try:
            d = s.recv(65536)
        except socket.timeout:
            continue
        if not d: break
        buf += d
        fs, buf = frames(buf)
        pongs += sum(1 for (op, _) in fs if op == 10)
    print("pongs", pongs, flush=True)
    sys.exit(0)
s.settimeout(20)
try:
    while True:
        want = int(arg) if mode == "slow" else 65536
        d = s.recv(min(want, 65536))
        if not d:
            print("EOF", total, flush=True)
            break
        total += len(d)
        if MARK in tail + d:
            print("done", total, round(time.time() - t0, 1), flush=True)
            break
        tail = (tail + d)[-8:]
        if mode == "slow":
            time.sleep(len(d) / arg)
except Exception as e:
    print("ERR", e, total, flush=True)
