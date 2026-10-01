"""Referenzwerte (roher MAC) fuer die isolierte conv1-Verifikation."""

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
    ap.add_argument("--row", type=int, default=8, help="obere Zeile des 3x3-Fensters")
    ap.add_argument("--col", type=int, default=13, help="linke Spalte des 3x3-Fensters")
    ap.add_argument("--model", default="cnn_mnist_int8.pth")
    args = ap.parse_args()

    m = load_quantized_model(args.model)

    tf = transforms.Compose([transforms.ToTensor()])
    ds = datasets.MNIST(root=_abs("data"), train=False, download=True, transform=tf)
    x, label = ds[args.index]
    xq = m.quant(x.unsqueeze(0))
    img = xq.int_repr().numpy().astype(np.int8)[0, 0]   # [28,28] int8

    r0, c0 = args.row, args.col
    patch = np.zeros(9, dtype=np.int64)
    for kh in range(3):
        for kw in range(3):
            patch[kh * 3 + kw] = img[r0 + kh, c0 + kw]   # tap = kh*3+kw (wie im2col)

    w1 = m.conv1.weight().int_repr().numpy().astype(np.int64).reshape(8, 9)

    mac = np.zeros(8, dtype=np.int64)
    for f in range(8):
        mac[f] = int(np.sum(w1[f] * patch))

    with open(_abs("conv1_patch.mem"), "w") as f:
        for p in patch:
            f.write(f"{int(p) & 0xFF:02x}\n")
    with open(_abs("conv1_expected.mem"), "w") as f:
        for v in mac:
            f.write(f"{int(v) & 0xFFFFFFFF:08x}\n")

    print(f"Bild #{args.index} (Label {label}), Fenster (row={r0}, col={c0})")
    print("patch (9 int8, tap-Reihenfolge): " + " ".join(str(int(p)) for p in patch))
    print("erwartete MACs (8 int32):        " + " ".join(str(int(v)) for v in mac))
    print("\nGeschrieben: conv1_patch.mem, conv1_expected.mem")
    print("-> beide nach src/rtl/student/ kopieren, dann conv1_verif_tb simulieren.")


if __name__ == "__main__":
    main()
