"""Erzeugt aus einem MNIST-Testbild die Golden-Referenzen (image.mem, Schicht-Aktivierungen, erwartete Ziffer) fuer die Simulation."""

import argparse
import os

import numpy as np
import torch
import torch.quantization
from torchvision import datasets, transforms

from model import MeinCNN

# Skript-Ordner -> Pfade funktionieren egal, von wo aus gestartet wird.
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))


def _abs(p: str) -> str:
    """Relative Pfade an den Skript-Ordner haengen, absolute unveraendert."""
    return p if os.path.isabs(p) else os.path.join(SCRIPT_DIR, p)


# ---------------------------------------------------------------------------
def load_quantized_model(path: str) -> MeinCNN:
    m = MeinCNN()
    m.eval()
    m.fuse_model()
    m.qconfig = torch.quantization.get_default_qconfig("fbgemm")
    torch.quantization.prepare(m, inplace=True)
    torch.quantization.convert(m, inplace=True)
    m.load_state_dict(torch.load(path, map_location="cpu"))
    m.eval()
    return m


def load_test_image(index: int):
    """Ein einzelnes MNIST-Testbild als [1,1,28,28]-float-Tensor + Label."""
    tf = transforms.Compose([transforms.ToTensor()])
    ds = datasets.MNIST(root=_abs("data"), train=False, download=True, transform=tf)
    img, label = ds[index]
    return img.unsqueeze(0), int(label)


def int8_flat(qtensor) -> np.ndarray:
    """int8-Repraesentation eines quantisierten Tensors, flach (row-major)."""
    return qtensor.int_repr().numpy().astype(np.int8).flatten()


def write_hex_bytes(path: str, arr: np.ndarray):
    """int8 -> 2-stelliges Hex (2er-Komplement), eine Zeile pro Byte."""
    with open(path, "w") as f:
        for v in arr:
            f.write(f"{int(v) & 0xFF:02x}\n")


def write_ints(path: str, arr: np.ndarray):
    with open(path, "w") as f:
        for v in arr:
            f.write(f"{int(v)}\n")


def requant_fixed_point(M: float, max_shift: int = 31):
    """
    Reeller Requant-Faktor M (0<M<1 ueblich) -> (mult, shift) mit
    M ~ mult / 2^shift, mult moeglichst gross fuer Genauigkeit.
    relu_pool rechnet: act = sat( (psum * mult) >>> shift ).
    """
    if M <= 0:
        return 0, 0
    shift = 0
    while (M * (1 << (shift + 1))) < (1 << 30) and shift < max_shift:
        shift += 1
    mult = int(round(M * (1 << shift)))
    return mult, shift


# ---------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--index", type=int, default=0, help="MNIST-Testbild-Index")
    ap.add_argument("--model", default="cnn_mnist_int8.pth")
    ap.add_argument("--out", default="vectors", help="Ausgabeordner")
    args = ap.parse_args()

    out_dir = _abs(args.out)
    os.makedirs(out_dir, exist_ok=True)
    model = load_quantized_model(_abs(args.model))
    x, label = load_test_image(args.index)

    # --- forward() Schritt fuer Schritt reproduzieren -----------------------
    with torch.no_grad():
        xq  = model.quant(x)          # float -> int8 (Eingabe-Quantisierung)
        c1  = model.conv1(xq)         # fused conv+relu -> quantisiert
        p1  = model.pool(c1)          # MaxPool 2x2 -> 8 x 13 x 13
        c2  = model.conv2(p1)         # fused conv+relu
        p2  = model.pool(c2)          # 16 x 5 x 5
        flat = p2.reshape(1, -1)      # 400
        f1  = model.fc1(flat)         # fused linear+relu -> 64
        f2  = model.fc2(f1)           # 10 (quantisiert)
        out = model.dequant(f2)       # -> float scores
        digit = int(out.argmax(dim=1).item())

    # --- Vektoren schreiben -------------------------------------------------
    img_i8 = int8_flat(xq)            # 784
    assert img_i8.size == 784, f"Eingabe hat {img_i8.size} statt 784 Pixel"
    write_hex_bytes(os.path.join(out_dir, "image.mem"), img_i8)

    write_ints(os.path.join(out_dir, "golden_conv1.txt"), int8_flat(p1))   # 1352
    write_ints(os.path.join(out_dir, "golden_conv2.txt"), int8_flat(p2))   # 400
    write_ints(os.path.join(out_dir, "golden_fc1.txt"),   int8_flat(f1))   # 64
    write_ints(os.path.join(out_dir, "golden_fc2.txt"),   int8_flat(f2))   # 10

    with open(os.path.join(out_dir, "expected.txt"), "w") as f:
        f.write(f"{digit}\n")         # Zeile 1: vorhergesagte Ziffer (= HW-Ziel)
        f.write(f"label {label}\n")   # Zeile 2: wahres MNIST-Label (Info)

    # --- Requant-Parameter pro Schicht (per-Tensor-Uebersicht) --------------
    layers = [("conv1", model.conv1, xq, c1),
              ("conv2", model.conv2, p1, c2),
              ("fc1",   model.fc1,   flat, f1),
              ("fc2",   model.fc2,   f1, f2)]
    lines = []
    lines.append("Schicht  in_scale     w_scale(mean)  out_scale    M=in*w/out   mult   shift")
    lines.append("-" * 78)
    for name, mod, xin, xout in layers:
        in_s  = float(xin.q_scale())
        out_s = float(xout.q_scale())
        w = mod.weight()
        try:
            w_s = float(w.q_per_channel_scales().mean())
        except Exception:
            w_s = float(w.q_scale())
        M = in_s * w_s / out_s
        mult, shift = requant_fixed_point(M)
        lines.append(f"{name:6s}  {in_s:.3e}  {w_s:.3e}   {out_s:.3e}  "
                     f"{M:.4e}  {mult:6d}  {shift:4d}")
    with open(os.path.join(out_dir, "requant.txt"), "w") as f:
        f.write("\n".join(lines) + "\n")

    # --- Zusammenfassung ----------------------------------------------------
    print("=" * 60)
    print(f"Testbild #{args.index}  (wahres Label = {label})")
    print(f"Vorhergesagte Ziffer (Golden) = {digit}")
    print("=" * 60)
    print("\n".join(lines))
    print("-" * 60)
    print(f"Geschrieben nach '{out_dir}':")
    for fn in ("image.mem", "golden_conv1.txt", "golden_conv2.txt",
               "golden_fc1.txt", "golden_fc2.txt", "expected.txt", "requant.txt"):
        print(f"  {fn}")
    print("\nNaechster Schritt: image.mem (+ weights.mem) nach")
    print("  src/rtl/student/  kopieren, dann Simulation starten.")


if __name__ == "__main__":
    main()
