"""Packt die 5 conv2-Tap-Tiles (16x16) als 2048-bit-Tile-Woerter fuer die N=16 Weight-BRAM."""
import os
import numpy as np
import torch
import torch.quantization
from model import MeinCNN
from conv_ws_sim import route_stream, reference_conv2

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DST = os.path.join(SCRIPT_DIR, "..", "src", "rtl", "student", "conv2_ws_tiles.mem")

N        = 16
NTILE    = 5
BYTES_PT = N * N          # 256 bytes / tile
HEX_PT   = BYTES_PT * 2   # 512 hex chars / line


def load_quantized_model(path="cnn_mnist_int8.pth"):
    m = MeinCNN()
    m.eval()
    m.fuse_model()
    m.qconfig = torch.quantization.get_default_qconfig("fbgemm")
    torch.quantization.prepare(m, inplace=True)
    torch.quantization.convert(m, inplace=True)
    m.load_state_dict(torch.load(os.path.join(SCRIPT_DIR, path), map_location="cpu"))
    m.eval()
    return m


def build_tiles(W):
    """W: (16,8,3,3) int -> list of 5 (16,16) int64 stationary tiles."""
    taps = [(kh, kw) for kh in range(3) for kw in range(3)]      # 9, row-major
    tap_tiles = [taps[i:i + 2] for i in range(0, 9, 2)]          # 5 (last: 1 tap)
    W_tiles = []
    for tile in tap_tiles:
        Wt = np.zeros((N, N), dtype=np.int64)
        for slot, (kh, kw) in enumerate(tile):
            base = slot * 8
            for r in range(16):
                for c in range(8):
                    Wt[r][base + c] = int(W[r, c, kh, kw])
        W_tiles.append(Wt)
    return W_tiles


def tile_to_line(Wt):
    flat = [int(Wt[r][c]) & 0xFF for r in range(N) for c in range(N)]  # byte0..255
    return "".join(f"{b:02x}" for b in reversed(flat))                 # byte255..0


def line_to_tile(line):
    """Reconstruct wtile_o[r][c] EXACTLY as student_weight_bram reads it (signed)."""
    word = int(line, 16)
    T = np.zeros((N, N), dtype=np.int64)
    for r in range(N):
        for c in range(N):
            b = (word >> ((r * N + c) * 8)) & 0xFF
            T[r][c] = b - 256 if b >= 128 else b
    return T


def main():
    m = load_quantized_model()
    W = m.conv2.weight().int_repr().numpy().astype(np.int8)   # (16,8,3,3)
    assert W.shape == (16, 8, 3, 3), W.shape

    W_tiles = build_tiles(W)
    lines = [tile_to_line(Wt) for Wt in W_tiles]
    assert all(len(l) == HEX_PT for l in lines), [len(l) for l in lines]

    # -- self-check A: readmemh roundtrip == signed tile content (byte order) --
    for t, (Wt, l) in enumerate(zip(W_tiles, lines)):
        rec = line_to_tile(l)
        exp = Wt.copy()
        exp[exp >= 128] -= 256          # golden already signed; normalize just in case
        assert np.array_equal(rec, np.where(Wt >= 128, Wt - 256, Wt)), f"byte-order fail tile {t}"

    # -- self-check B: RTL-read tiles reproduce reference conv2 (13x13x8 -> 11x11x16) --
    rng = np.random.RandomState(7)
    X = rng.randint(-8, 8, size=(13, 13, 8))
    ref = reference_conv2(X, np.moveaxis(W, 1, 1))            # W already (16,8,3,3)
    OH, OW = 11, 11
    positions = [(oh, ow) for oh in range(OH) for ow in range(OW)]
    P = len(positions)
    taps = [(kh, kw) for kh in range(3) for kw in range(3)]
    tap_tiles = [taps[i:i + 2] for i in range(0, 9, 2)]
    acc = np.zeros((P, 16), dtype=np.int64)
    for t, tile in enumerate(tap_tiles):
        Wt_rtl = line_to_tile(lines[t])                       # what the HW will multiply
        acts = [np.zeros(16, dtype=np.int64) for _ in range(P)]
        for slot, (kh, kw) in enumerate(tile):
            base = slot * 8
            for p, (oh, ow) in enumerate(positions):
                for c in range(8):
                    acts[p][base + c] = int(X[oh + kh, ow + kw, c])
        cap = route_stream(Wt_rtl, acts, N=16, spacing=2)
        for p in range(P):
            for r in range(16):
                acc[p][r] += cap[p][r]
    Y = np.zeros((P, 16), dtype=np.int64)
    for p, (oh, ow) in enumerate(positions):
        Y[p] = ref[oh, ow]
    assert np.array_equal(acc, Y), "conv2 WS-tile self-check FAILED"

    with open(DST, "w") as f:
        for l in lines:
            f.write(l + "\n")

    print(f"self-check A (byte order) PASS; self-check B (WS conv2 == reference) PASS")
    print(f"wrote {NTILE} tile lines ({HEX_PT} hex chars each) to {os.path.abspath(DST)}")
    print("engine: student_weight_bram #(.N(16)); tile_addr_i = tap-tile index 0..4; 1-cyc sync read.")


if __name__ == "__main__":
    main()
