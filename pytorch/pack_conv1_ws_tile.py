"""Packt das conv1-Tap-Tile (16x16) als 2048-bit-Tile-Wort fuer die geteilte N=16 WS-Weight-BRAM."""
import os
import numpy as np

from conv_ws_sim import route_stream, reference_conv1
# Reuse the VERIFIED conv2 packer helpers so byte-order + model load cannot drift.
from pack_conv2_ws_tiles import (load_quantized_model, tile_to_line, line_to_tile,
                                 N, HEX_PT)

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DST = os.path.join(SCRIPT_DIR, "..", "src", "rtl", "student", "conv1_ws_tile.mem")


def build_conv1_tile(W1):
    """W1: (8,1,3,3) int -> ONE (16,16) int64 stationary tile (rows 8..15, cols 9..15 = 0)."""
    Wt = np.zeros((N, N), dtype=np.int64)
    for oc in range(8):
        for tap in range(9):
            Wt[oc][tap] = int(W1[oc, 0, tap // 3, tap % 3])
    return Wt


def main():
    m = load_quantized_model()
    W1 = m.conv1.weight().int_repr().numpy().astype(np.int8)   # (8,1,3,3)
    assert W1.shape == (8, 1, 3, 3), W1.shape

    Wt = build_conv1_tile(W1)
    line = tile_to_line(Wt)
    assert len(line) == HEX_PT, len(line)

    # -- self-check A: readmemh roundtrip == signed tile content (byte order) --
    rec = line_to_tile(line)                              # exactly how the BRAM reads it
    exp = np.where(Wt >= 128, Wt - 256, Wt)               # golden already signed; normalize
    assert np.array_equal(rec, exp), "conv1 byte-order self-check FAILED"

    # -- self-check B: RTL-read tile reproduces reference_conv1 (spacing=1, 1 tile) --
    #    Feeds the tile EXACTLY as line_to_tile() decodes it (i.e. the HW multiplicand)
    #    through the cycle-accurate route_stream and compares to the plain conv1 reference.
    rng = np.random.RandomState(11)
    Xc1 = rng.randint(-8, 8, size=(12, 12, 1))            # any HxWx1 (OH=OW=10 here)
    ref = reference_conv1(Xc1, W1.astype(np.int64))       # (OH,OW,8)
    OH, OW = Xc1.shape[0] - 2, Xc1.shape[1] - 2
    positions = [(oh, ow) for oh in range(OH) for ow in range(OW)]
    Wt_rtl = line_to_tile(line)
    acts = []
    for (oh, ow) in positions:
        v = np.zeros(16, dtype=np.int64)                 # cols 0..8 = patch, 9..15 = 0
        for tap in range(9):
            v[tap] = int(Xc1[oh + tap // 3, ow + tap % 3, 0])
        acts.append(v)
    cap = route_stream(Wt_rtl, acts, N=16, spacing=1)     # single tile -> overwrite, no RMW
    Y = np.zeros((OH, OW, 8), dtype=np.int64)
    for p, (oh, ow) in enumerate(positions):
        for r in range(8):                                # 1 readout group (rows 0..7)
            Y[oh, ow, r] = cap[p][r]
    assert np.array_equal(Y, ref), "conv1 WS-tile self-check FAILED"

    with open(DST, "w") as f:
        f.write(line + "\n")

    print("self-check A (byte order) PASS; self-check B (WS conv1 == reference) PASS")
    print(f"wrote 1 tile line ({HEX_PT} hex chars) to {os.path.abspath(DST)}")
    print("engine: student_ws_weight_bram; conv1 tile_addr_i = CONV1_BASE(5) + 0; 1-cyc sync read.")


if __name__ == "__main__":
    main()
