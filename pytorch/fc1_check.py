"""Referenzwerte fuer die isolierte fc1-Verifikation."""

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
    m = MeinCNN(); m.eval(); m.fuse_model()
    m.qconfig = torch.quantization.get_default_qconfig("fbgemm")
    torch.quantization.prepare(m, inplace=True)
    torch.quantization.convert(m, inplace=True)
    m.load_state_dict(torch.load(_abs(path), map_location="cpu")); m.eval()
    return m


def main():
    m = load_quantized_model()
    tf = transforms.Compose([transforms.ToTensor()])
    ds = datasets.MNIST(root=_abs("data"), train=False, download=True, transform=tf)
    x, _ = ds[0]
    with torch.no_grad():
        xq = m.quant(x.unsqueeze(0))
        p1 = m.pool(m.conv1(xq))
        p2 = m.pool(m.conv2(p1))          # [1,16,5,5] quantisiert
    inp = p2.int_repr().numpy().astype(np.int64)[0]     # [16,5,5]
    flat = inp.reshape(-1)                               # 400, channel-major (ch*25+pos)

    wf1 = m.fc1.weight().int_repr().numpy().astype(np.int64)   # [64,400]

    mac = np.array([int(np.dot(wf1[f], flat)) for f in range(8)], dtype=np.int64)

    # HW-Wort-Reihenfolge: 50 Woerter x 8 Kanaele
    words = np.zeros((50, 8), dtype=np.int64)
    for s in range(50):
        base_ch = 0 if s < 25 else 8
        pos = s if s < 25 else s - 25
        h, w = pos // 5, pos % 5
        for c in range(8):
            words[s][c] = inp[base_ch + c][h][w]

    with open(_abs("fc1_input.mem"), "w") as fp:
        for s in range(50):
            for c in range(8):
                fp.write(f"{int(words[s][c]) & 0xFF:02x}\n")
    with open(_abs("fc1_expected.mem"), "w") as fp:
        for v in mac:
            fp.write(f"{int(v) & 0xFFFFFFFF:08x}\n")

    print("fc1 erwartete MACs (Ausgabe 0..7):", mac.tolist())
    print("Geschrieben: fc1_input.mem (400), fc1_expected.mem (8)")
    print("-> beide nach src/rtl/student/ kopieren, dann fc1_verif_tb simulieren.")


if __name__ == "__main__":
    main()
