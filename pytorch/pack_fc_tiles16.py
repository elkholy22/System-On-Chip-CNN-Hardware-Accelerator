"""Baut weights_tiles16.mem (16x16-Tile-Woerter) fuer die N=16 fc-Engine aus weights.mem."""
import os
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
def _abs(p): return os.path.join(SCRIPT_DIR, p)

wmem = []
for line in open(_abs("../src/rtl/student/weights.mem")):
    s = line.strip()
    if s: wmem.append(int(s, 16) & 0xFF)
def s8(b): return b - 256 if b >= 128 else b
def oldbyte(T, r, c): return wmem[T*64 + r*8 + c]

N = 16
tiles = []

def fc1_tile(G, S):                          # volle 16x16 (16 Ausgaenge)
    t = [[0]*N for _ in range(N)]
    for r16 in range(16):
        g_old = 2*G + (r16 // 8); r_old = r16 % 8
        for c16 in range(16):
            s_old = S if c16 < 8 else S + 25
            c_old = c16 if c16 < 8 else c16 - 8
            t[r16][c16] = oldbyte(20 + g_old*50 + s_old, r_old, c_old)
    return t

def fc2_tile(g, S):                          # 8 Ausgaenge (Zeilen 8..15 = 0)
    t = [[0]*N for _ in range(N)]
    for r in range(8):
        for c16 in range(16):
            t[r][c16] = oldbyte(420 + g*8 + (2*S + c16//8), r, c16 % 8)
    return t

for G in range(4):
    for S in range(25):
        tiles.append(fc1_tile(G, S))         # index G*25 + S  (0..99)
for g in range(2):
    for S in range(4):
        tiles.append(fc2_tile(g, S))         # index 100 + g*4 + S (100..107)

DST = _abs("../src/rtl/student/weights_tiles16.mem")
with open(DST, "w") as f:
    for t in tiles:
        b = [t[r][c] for r in range(N) for c in range(N)]
        f.write("".join(f"{x:02x}" for x in reversed(b)) + "\n")
print(f"wrote {len(tiles)} 16x16 tiles ({N*N*2} hex chars) -> {DST}")

# --- SELBSTTEST: fc1 Gruppe 0 ALLE 16 Ausgaben ---
inp = []
for line in open(_abs("../src/rtl/student/fc1_input.mem")):
    s = line.strip()
    if s: inp.append(s8(int(s, 16) & 0xFF))
exp8 = []
for line in open(_abs("../src/rtl/student/fc1_expected.mem")):
    s = line.strip()
    if s:
        v = int(s, 16); exp8.append(v - (1 << 32) if v >= (1 << 31) else v)
def words(s, c): return inp[s*8 + c]
# Referenz Ausgaenge 8..15 aus alten 8x8-Tiles (alte Gruppe 1 = tiles 20+50+s):
ref_hi = [sum(s8(oldbyte(20 + 50 + s, r, c)) * words(s, c) for s in range(50) for c in range(8)) for r in range(8)]
ref = exp8 + ref_hi                          # erwartete 16 Ausgaben von Gruppe 0
def act16(S, c): return words(S, c) if c < 8 else words(S+25, c-8)
mac = []
for r16 in range(16):
    acc = 0
    for S in range(25):
        t = tiles[0*25 + S]
        for c in range(16):
            acc += s8(t[r16][c]) * act16(S, c)
    mac.append(acc)
print("fc1 G0 (16) from tiles:", mac)
print("fc1 G0 (16) reference :", ref)
print("SELFTEST:", "PASS (bit-exact, all 16)" if mac == ref else "FAIL")
