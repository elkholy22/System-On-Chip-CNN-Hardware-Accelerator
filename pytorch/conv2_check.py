"""Referenzwerte (roher MAC) fuer die isolierte conv2-Verifikation."""

import argparse
import os
import numpy as np
import torch
import torch.quantization
from torchvision import datasets, transforms
from model import MeinCNN

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))


def _abs(p):
    return p if os.path.isabs(p) else os.path.join(SCRIPT_DIR, p)


def load_quantized_model(path="cnn_mnist_int8.pth"):
    m = MeinCNN()
    m.eval()
    m.fuse_model()
    m.qconfig = torch.quantization.get_default_qconfig("fbgemm")
    torch.quantization.prepare(m, inplace=True)
    torch.quantization.convert(m, inplace=True)
    m.load_state_dict(torch.load(_abs(path), map_location="cpu"))
    m.eval()
    return m


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--index", type=int, default=0)
    ap.add_argument("--orow", type=int, default=4, help="conv2-Ausgabezeile 0..10")
    ap.add_argument("--ocol", type=int, default=4, help="conv2-Ausgabespalte 0..10")
    args = ap.parse_args()

    m = load_quantized_model()
    tf = transforms.Compose([transforms.ToTensor()])
    ds = datasets.MNIST(root=_abs("data"), train=False, download=True, transform=tf)
    x, _ = ds[args.index]
    with torch.no_grad():
        xq = m.quant(x.unsqueeze(0))
        c1 = m.conv1(xq)
        p1 = m.pool(c1)                       # 8 x 13 x 13, quantisiert
    inp = p1.int_repr().numpy().astype(np.int64)[0]   # [8,13,13] int8

    w2 = m.conv2.weight().int_repr().numpy().astype(np.int64)  # [16,8,3,3]

    orow, ocol = args.orow, args.ocol

    window = np.zeros((9, 8), dtype=np.int64)
    for kh in range(3):
        for kw in range(3):
            tap = kh * 3 + kw
            for ch in range(8):
                window[tap][ch] = inp[ch][orow + kh][ocol + kw]

    mac = np.zeros(8, dtype=np.int64)
    for f in range(8):
        s = 0
        for kh in range(3):
            for kw in range(3):
                tap = kh * 3 + kw
                for ch in range(8):
                    s += int(w2[f][ch][kh][kw]) * int(window[tap][ch])
        mac[f] = s

    with open(_abs("conv2_window.mem"), "w") as fp:
        for tap in range(9):
            for ch in range(8):
                fp.write(f"{int(window[tap][ch]) & 0xFF:02x}\n")
    with open(_abs("conv2_expected.mem"), "w") as fp:
        for v in mac:
            fp.write(f"{int(v) & 0xFFFFFFFF:08x}\n")

    print(f"conv2-Position (orow={orow}, ocol={ocol})")
    print("window[tap0] (8 ch):", window[0].tolist())
    print("erwartete MACs (Filter 0..7):", mac.tolist())
    print("\nGeschrieben: conv2_window.mem, conv2_expected.mem")
    print("-> beide nach src/rtl/student/ kopieren, dann conv2_verif_tb simulieren.")


if __name__ == "__main__":
    main()
