"""Packt weights.mem (Byte/Zeile) zu weights_tiles.mem (512-bit-Tile-Wort/Zeile) fuer $readmemh."""
import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(SCRIPT_DIR, "..", "src", "rtl", "student", "weights.mem")
DST = os.path.join(SCRIPT_DIR, "..", "src", "rtl", "student", "weights_tiles.mem")

NTILES         = 440
BYTES_PER_TILE = 64
NEED           = NTILES * BYTES_PER_TILE

vals = []
with open(SRC) as f:
    for line in f:
        s = line.strip()
        if s:
            vals.append(int(s, 16) & 0xFF)

if len(vals) > NEED:
    vals = vals[:NEED]
else:
    vals += [0] * (NEED - len(vals))

with open(DST, "w") as f:
    for g in range(NTILES):
        tile = vals[g * BYTES_PER_TILE:(g + 1) * BYTES_PER_TILE]  # [byte0..byte63]
        line = "".join(f"{b:02x}" for b in reversed(tile))         # byte63..byte0
        f.write(line + "\n")

print(f"wrote {NTILES} tile lines (each {BYTES_PER_TILE*2} hex chars) to {DST}")
