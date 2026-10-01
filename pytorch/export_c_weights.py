"""Erzeugt cnn_params.h (int8-Gewichte in PyTorch-Reihenfolge) fuer die CPU/SW-Referenz."""

import argparse
import os

import numpy as np
import torch
import torch.quantization
from torchvision import datasets, transforms

from model import MeinCNN

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(SCRIPT_DIR)
OUT_HEADER = os.path.join(REPO_ROOT, "src", "sw", "cnn_cpu", "cnn_params.h")


def _abs(p):
    return p if os.path.isabs(p) else os.path.join(SCRIPT_DIR, p)


# ---------------------------------------------------------------------------
def load():
    m = MeinCNN()
    m.eval()
    m.fuse_model()
    m.qconfig = torch.quantization.get_default_qconfig("fbgemm")
    torch.quantization.prepare(m, inplace=True)
    torch.quantization.convert(m, inplace=True)
    m.load_state_dict(torch.load(_abs("cnn_mnist_int8.pth"), map_location="cpu"))
    m.eval()
    return m


def fixed_point(M, max_shift=31):
    """Reeller Requant-Faktor M -> (mult, shift) mit M ~ mult/2^shift. Wie export_bias.py."""
    if M <= 0:
        return 0, 0
    shift = 0
    while (M * (1 << (shift + 1))) < (1 << 30) and shift < max_shift:
        shift += 1
    return int(round(M * (1 << shift))), shift


def layer_params(mod, w_flat, in_scale, in_zp, out_scale):
    """(offset[out], mult[out], shift[out]) -- identische Formel wie export_bias.py."""
    wsc = mod.weight().q_per_channel_scales().numpy()
    bias = mod.bias().detach().numpy()
    n = w_flat.shape[0]
    off = np.zeros(n, dtype=np.int64)
    mul = np.zeros(n, dtype=np.int64)
    sh = np.zeros(n, dtype=np.int64)
    for o in range(n):
        off[o] = round(float(bias[o]) / (in_scale * float(wsc[o]))) - in_zp * int(w_flat[o].sum())
        M = in_scale * float(wsc[o]) / out_scale
        mul[o], sh[o] = fixed_point(M)
    return off, mul, sh


# ---------------------------------------------------------------------------
# C-Emitter
def _fmt(v):
    return str(int(v))


def emit_1d(f, ctype, name, arr):
    f.write(f"const {ctype} {name}[{len(arr)}] = {{\n    ")
    f.write(", ".join(_fmt(v) for v in arr))
    f.write("\n};\n\n")


def emit_conv1_w(f, w):  # [8][3][3]
    f.write("const int8_t conv1_w[8][3][3] = {\n")
    for oc in range(8):
        f.write("  {")
        for ky in range(3):
            f.write("{" + ", ".join(_fmt(w[oc, ky, kx]) for kx in range(3)) + "}")
            f.write(", " if ky < 2 else "")
        f.write("},\n")
    f.write("};\n\n")


def emit_conv2_w(f, w):  # [16][8][3][3]
    f.write("const int8_t conv2_w[16][8][3][3] = {\n")
    for oc in range(16):
        f.write("  {\n")
        for ic in range(8):
            f.write("    {")
            for ky in range(3):
                f.write("{" + ", ".join(_fmt(w[oc, ic, ky, kx]) for kx in range(3)) + "}")
                f.write(", " if ky < 2 else "")
            f.write("},\n")
        f.write("  },\n")
    f.write("};\n\n")


def emit_fc_w(f, name, w, rows, cols):  # [rows][cols]
    f.write(f"const int8_t {name}[{rows}][{cols}] = {{\n")
    for o in range(rows):
        f.write("  {" + ", ".join(_fmt(w[o, i]) for i in range(cols)) + "},\n")
    f.write("};\n\n")


# ---------------------------------------------------------------------------
# numpy-Referenz: EXAKT die Arithmetik von cnn_sw.c
def requant_relu(acc, mult, shift):
    t = int(acc) * int(mult)
    if shift != 0:
        t += 1 << (int(shift) - 1)
    r = t >> int(shift)
    if r < 0:
        r = 0
    if r > 127:
        r = 127
    return r


def ref_infer(img_u8, P):
    img = img_u8.astype(np.int64)  # 0..255
    # conv1: 1x28x28 -> 8x26x26
    c1 = np.zeros((8, 26, 26), dtype=np.int64)
    for oc in range(8):
        for oy in range(26):
            for ox in range(26):
                acc = int(P["conv1_bias"][oc])
                for ky in range(3):
                    for kx in range(3):
                        acc += int(img[(oy + ky) * 28 + (ox + kx)]) * int(P["conv1_w"][oc, ky, kx])
                c1[oc, oy, ox] = requant_relu(acc, P["conv1_mult"][oc], P["conv1_shift"][oc])
    p1 = maxpool(c1)                       # 8x13x13
    # conv2: 8x13x13 -> 16x11x11
    c2 = np.zeros((16, 11, 11), dtype=np.int64)
    for oc in range(16):
        for oy in range(11):
            for ox in range(11):
                acc = int(P["conv2_bias"][oc])
                for ic in range(8):
                    for ky in range(3):
                        for kx in range(3):
                            acc += int(p1[ic, oy + ky, ox + kx]) * int(P["conv2_w"][oc, ic, ky, kx])
                c2[oc, oy, ox] = requant_relu(acc, P["conv2_mult"][oc], P["conv2_shift"][oc])
    p2 = maxpool(c2)                       # 16x5x5
    flat = p2.reshape(-1)                  # 400 (channel-major, row-major)
    # fc1: 400 -> 64
    f1 = np.zeros(64, dtype=np.int64)
    for o in range(64):
        acc = int(P["fc1_bias"][o]) + int(np.dot(flat, P["fc1_w"][o].astype(np.int64)))
        f1[o] = requant_relu(acc, P["fc1_mult"][o], P["fc1_shift"][o])
    # fc2: 64 -> 10 (kein Requant, direkt argmax auf 32-bit-Score)
    scores = np.zeros(10, dtype=np.int64)
    for o in range(10):
        scores[o] = int(P["fc2_bias"][o]) + int(np.dot(f1, P["fc2_w"][o].astype(np.int64)))
    return int(np.argmax(scores)), scores, p1, p2, f1


def maxpool(x):  # (C,H,W) -> (C,H//2,W//2), stride 2, mirror von maxpool2()
    C, H, W = x.shape
    OH, OW = H // 2, W // 2
    out = np.full((C, OH, OW), -128, dtype=np.int64)
    for c in range(C):
        for oy in range(OH):
            for ox in range(OW):
                m = -128
                for dy in range(2):
                    for dx in range(2):
                        v = int(x[c, oy * 2 + dy, ox * 2 + dx])
                        if v > m:
                            m = v
                out[c, oy, ox] = m
    return out


# ---------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--index", type=int, default=0, help="MNIST-Testbild-Index (0 = image7.h)")
    args = ap.parse_args()

    m = load()
    tf = transforms.Compose([transforms.ToTensor()])
    ds = datasets.MNIST(root=_abs("data"), train=False, download=True, transform=tf)
    x, label = ds[args.index]

    with torch.no_grad():
        xq = m.quant(x.unsqueeze(0))
        c1 = m.conv1(xq); p1 = m.pool(c1)
        c2 = m.conv2(p1); p2 = m.pool(c2)
        flat = p2.reshape(1, -1)
        f1 = m.fc1(flat); f2 = m.fc2(f1)
        golden_digit = int(m.dequant(f2).argmax(dim=1).item())

    def sc_zp(t):
        return float(t.q_scale()), int(t.q_zero_point())

    a1, z1 = sc_zp(xq); o1s = float(c1.q_scale())
    a2, z2 = sc_zp(p1); o2s = float(c2.q_scale())
    a3, z3 = sc_zp(p2); o3s = float(f1.q_scale())
    a4, z4 = sc_zp(f1); o4s = float(f2.q_scale())

    # int8-Gewichte in natuerlicher Reihenfolge
    w1 = m.conv1.weight().int_repr().numpy().astype(np.int8).reshape(8, 3, 3)
    w2 = m.conv2.weight().int_repr().numpy().astype(np.int8).reshape(16, 8, 3, 3)
    wf1 = m.fc1.weight().int_repr().numpy().astype(np.int8)          # [64,400]
    wf2 = m.fc2.weight().int_repr().numpy().astype(np.int8)          # [10,64]

    # offset/mult/shift (fuer sum-W: geflachte Gewichte)
    of1, m1, s1 = layer_params(m.conv1, w1.reshape(8, 9),   a1, z1, o1s)   # conv1: echtes in_zp
    of2, m2, s2 = layer_params(m.conv2, w2.reshape(16, 72), a2, 0,  o2s)   # conv2: in_zp = 0
    of3, m3, s3 = layer_params(m.fc1,   wf1,                a3, 0,  o3s)   # fc1:   in_zp = 0
    of4, _mm, _ss = layer_params(m.fc2, wf2,                a4, 0,  o4s)   # fc2:   nur offset

    P = dict(
        conv1_w=w1, conv1_bias=of1, conv1_mult=m1, conv1_shift=s1,
        conv2_w=w2, conv2_bias=of2, conv2_mult=m2, conv2_shift=s2,
        fc1_w=wf1, fc1_bias=of3, fc1_mult=m3, fc1_shift=s3,
        fc2_w=wf2, fc2_bias=of4,
    )

    # --- SELBSTCHECK: exakte cnn_sw.c-Arithmetik nachrechnen -----------------
    img_u8 = xq.int_repr().numpy().astype(np.uint8).reshape(784)   # 0..255, = image7.h
    ref_digit, scores, rp1, rp2, rf1 = ref_infer(img_u8, P)

    print("=" * 64)
    print(f"Testbild #{args.index}  (wahres Label = {label})")
    print(f"Golden (PyTorch dequant argmax) = {golden_digit}")
    print(f"CPU-SW-Referenz (numpy, = cnn_sw.c) = {ref_digit}")
    print(f"fc2-Scores: {scores.tolist()}")
    print("=" * 64)
    assert ref_digit == label, (
        f"FEHLER: SW-Referenz liefert {ref_digit}, erwartet {label}. "
        "cnn_params.h wurde NICHT geschrieben. Arithmetik/Reihenfolge pruefen."
    )
    assert ref_digit == golden_digit, (
        f"WARNUNG: SW-Referenz {ref_digit} != Golden {golden_digit}."
    )

    # --- cnn_params.h schreiben ---------------------------------------------
    os.makedirs(os.path.dirname(OUT_HEADER), exist_ok=True)
    with open(OUT_HEADER, "w") as f:
        f.write("/* AUTO-GENERIERT von pytorch/export_c_weights.py -- NICHT haendisch editieren.\n")
        f.write(" * int8-Gewichte + per-Kanal Requant (offset/mult/shift), konsistent zu\n")
        f.write(" * export_bias.py und zum HW-Beschleuniger. Selbstcheck bestanden:\n")
        f.write(f" *   erkannte Ziffer = {ref_digit} (Label {label}, Golden {golden_digit}).\n")
        f.write(" */\n")
        f.write("#ifndef _CNN_PARAMS_H\n#define _CNN_PARAMS_H\n#include <stdint.h>\n\n")

        emit_conv1_w(f, w1)
        emit_1d(f, "int32_t", "conv1_bias", of1)
        emit_1d(f, "int32_t", "conv1_mult", m1)
        emit_1d(f, "uint8_t", "conv1_shift", s1)

        emit_conv2_w(f, w2)
        emit_1d(f, "int32_t", "conv2_bias", of2)
        emit_1d(f, "int32_t", "conv2_mult", m2)
        emit_1d(f, "uint8_t", "conv2_shift", s2)

        emit_fc_w(f, "fc1_w", wf1, 64, 400)
        emit_1d(f, "int32_t", "fc1_bias", of3)
        emit_1d(f, "int32_t", "fc1_mult", m3)
        emit_1d(f, "uint8_t", "fc1_shift", s3)

        emit_fc_w(f, "fc2_w", wf2, 10, 64)
        emit_1d(f, "int32_t", "fc2_bias", of4)

        f.write("#endif /* _CNN_PARAMS_H */\n")

    print(f"Geschrieben: {OUT_HEADER}")
    print("Naechster Schritt: 'flow sw_cnn_cpu.build' bzw. 'flow systb_cnn_cpu.sim_rtl_questa'.")


if __name__ == "__main__":
    main()
