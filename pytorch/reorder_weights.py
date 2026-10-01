"""Schreibt weights.mem im 8x8-Kachel-Format des systolischen Arrays."""

import argparse
import os

import numpy as np
import torch
import torch.quantization
from model import MeinCNN

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))


def _abs(p):
    return p if os.path.isabs(p) else os.path.join(SCRIPT_DIR, p)


def load_quantized_model(path):
    m = MeinCNN()
    m.eval()
    m.fuse_model()
    m.qconfig = torch.quantization.get_default_qconfig("fbgemm")
    torch.quantization.prepare(m, inplace=True)
    torch.quantization.convert(m, inplace=True)
    m.load_state_dict(torch.load(_abs(path), map_location="cpu"))
    m.eval()
    return m


def int8_w(module):
    return module.weight().int_repr().numpy().astype(np.int8)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default="cnn_mnist_int8.pth")
    ap.add_argument("--out", default="weights.mem")
    args = ap.parse_args()

    m = load_quantized_model(args.model)
    w1 = int8_w(m.conv1).reshape(8, 9)        # [out, tap]
    w2 = int8_w(m.conv2).reshape(16, 8, 9)    # [out, in_ch, tap]
    wf1 = int8_w(m.fc1)                        # [64, 400]
    wf2 = int8_w(m.fc2)                        # [10, 64]

    tiles = []  # jede Kachel: 8x8 int (row-major beim Schreiben)

    def new_tile():
        return np.zeros((8, 8), dtype=np.int64)

    # ---- conv1: 2 Kacheln (8+1-Split) ----
    conv1_base = len(tiles)
    t0 = new_tile()
    for r in range(8):
        for c in range(8):
            t0[r][c] = w1[r][c]          # Taps 0..7
    tiles.append(t0)
    t1 = new_tile()
    for r in range(8):
        t1[r][0] = w1[r][8]              # Tap 8, Rest 0
    tiles.append(t1)

    # ---- conv2: 2 Gruppen x 9 steps ----
    conv2_base = len(tiles)
    for g in range(2):
        for k in range(9):               # step = Tap
            t = new_tile()
            for r in range(8):
                for c in range(8):        # Spalte = Eingangskanal
                    t[r][c] = w2[g * 8 + r][c][k]
            tiles.append(t)

    # ---- fc1: 8 Gruppen x 50 steps ----
    # HW liest act_buffer-Wort s (conv2-Ausgabe): s<25 -> Gruppe0 (Filter 0..7)
    # an Position s; s>=25 -> Gruppe1 (Filter 8..15) an Position s-25.
    # PyTorch-fc1-Eingang ist channel-major: idx = filter*25 + position.
    fc1_base = len(tiles)
    for g in range(8):
        for s in range(50):
            t = new_tile()
            for r in range(8):
                for c in range(8):
                    if s < 25:
                        pyidx = c * 25 + s
                    else:
                        pyidx = (8 + c) * 25 + (s - 25)
                    t[r][c] = wf1[g * 8 + r][pyidx]
            tiles.append(t)

    # ---- fc2: 2 Gruppen x 8 steps (out 8..9 real, 10..15 = 0) ----
    fc2_base = len(tiles)
    for g in range(2):
        for s in range(8):
            t = new_tile()
            for r in range(8):
                out = g * 8 + r
                if out < 10:
                    for c in range(8):
                        t[r][c] = wf2[out][s * 8 + c]
            tiles.append(t)

    # ---- weights.mem schreiben (64 Byte/Kachel, zeilen-major) ----
    out_path = _abs(args.out)
    with open(out_path, "w") as f:
        for t in tiles:
            for r in range(8):
                for c in range(8):
                    f.write(f"{int(t[r][c]) & 0xFF:02x}\n")

    print("Kachel-Layout (op_wbase pro Schicht):")
    print(f"  conv1 : base {conv1_base:4d}   2 Kacheln  (steps=2)")
    print(f"  conv2 : base {conv2_base:4d}  18 Kacheln  (2 Gruppen x 9)")
    print(f"  fc1   : base {fc1_base:4d} 400 Kacheln  (8 Gruppen x 50)")
    print(f"  fc2   : base {fc2_base:4d}  16 Kacheln  (2 Gruppen x 8)")
    print(f"Gesamt: {len(tiles)} Kacheln = {len(tiles)*64} Bytes -> {out_path}")
    print("weight_bram NTILES muss >= {} sein.".format(len(tiles)))
    print("\nNaechster Schritt: weights.mem nach src/rtl/student/ kopieren.")


if __name__ == "__main__":
    main()
