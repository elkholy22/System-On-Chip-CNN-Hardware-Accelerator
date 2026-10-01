"""Per-Kanal-Requant (offset/mult/shift) fuer alle Schichten -> bias.mem, mult.mem, shift.mem."""

import os
import numpy as np
import torch
import torch.quantization
from torchvision import datasets, transforms
from model import MeinCNN

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
def _abs(p): return p if os.path.isabs(p) else os.path.join(SCRIPT_DIR, p)


def load():
    m = MeinCNN(); m.eval(); m.fuse_model()
    m.qconfig = torch.quantization.get_default_qconfig("fbgemm")
    torch.quantization.prepare(m, inplace=True)
    torch.quantization.convert(m, inplace=True)
    m.load_state_dict(torch.load(_abs("cnn_mnist_int8.pth"), map_location="cpu")); m.eval()
    return m


def fixed_point(M, max_shift=31):
    if M <= 0:
        return 0, 0
    shift = 0
    while (M * (1 << (shift + 1))) < (1 << 30) and shift < max_shift:
        shift += 1
    return int(round(M * (1 << shift))), shift


def layer_params(mod, w_flat, in_scale, in_zp, out_scale):
    """Gibt (offset[out], mult[out], shift[out])."""
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


def main():
    m = load()
    tf = transforms.Compose([transforms.ToTensor()])
    ds = datasets.MNIST(root=_abs("data"), train=False, download=True, transform=tf)
    x, _ = ds[0]
    with torch.no_grad():
        xq = m.quant(x.unsqueeze(0))
        c1 = m.conv1(xq); p1 = m.pool(c1)
        c2 = m.conv2(p1); p2 = m.pool(c2)
        flat = p2.reshape(1, -1)
        f1 = m.fc1(flat); f2 = m.fc2(f1)

    def sc_zp(t): return float(t.q_scale()), int(t.q_zero_point())
    a1, z1 = sc_zp(xq);  o1s = float(c1.q_scale())   # conv1: Eingang xq, Ausgang c1
    a2, z2 = sc_zp(p1);  o2s = float(c2.q_scale())
    a3, z3 = sc_zp(p2);  o3s = float(f1.q_scale())
    a4, z4 = sc_zp(f1);  o4s = float(f2.q_scale())

    w1 = m.conv1.weight().int_repr().numpy().astype(np.int64).reshape(8, 9)
    w2 = m.conv2.weight().int_repr().numpy().astype(np.int64).reshape(16, 72)
    wf1 = m.fc1.weight().int_repr().numpy().astype(np.int64)
    wf2 = m.fc2.weight().int_repr().numpy().astype(np.int64)

    # WICHTIG: Zero-Point-Korrektur (-z_a*sumW) NUR bei conv1 (Eingang = rohes
    # quantisiertes Bild). conv2/fc1/fc2 bekommen als Eingang die bereits
    # ZENTRIERTE Vorschicht-Ausgabe -> effektives input-zero-point = 0.
    of1, m1, s1 = layer_params(m.conv1, w1,  a1, z1, o1s)   # conv1: echtes z_a
    of2, m2, s2 = layer_params(m.conv2, w2,  a2, 0,  o2s)   # conv2: z_a=0
    of3, m3, s3 = layer_params(m.fc1,   wf1, a3, 0,  o3s)   # fc1:   z_a=0
    of4, m4, s4 = layer_params(m.fc2,   wf2, a4, 0,  o4s)   # fc2:   z_a=0

    offset = np.concatenate([of1, of2, of3, of4])
    mult   = np.concatenate([m1, m2, m3, m4])
    shift  = np.concatenate([s1, s2, s3, s4])

    with open(_abs("bias.mem"), "w") as f:
        for v in offset: f.write(f"{int(v) & 0xFFFFFFFF:08x}\n")
    with open(_abs("mult.mem"), "w") as f:
        for v in mult:   f.write(f"{int(v) & 0xFFFFFFFF:08x}\n")
    with open(_abs("shift.mem"), "w") as f:
        for v in shift:  f.write(f"{int(v):02x}\n")

    print("conv1 offset:", of1.tolist())
    print("conv1 mult:  ", m1.tolist())
    print("conv1 shift: ", s1.tolist())
    print(f"\nGeschrieben: bias.mem, mult.mem, shift.mem ({offset.size} Werte)")
    print("-> alle drei nach src/rtl/student/ kopieren.")


if __name__ == "__main__":
    main()
