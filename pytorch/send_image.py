"""Schickt MNIST-Testbilder (784 Bytes) ueber UART an die FPGA und liest die Ziffer zurueck.

    python send_image.py --port COM5 --index 42
    python send_image.py --port COM5 --random 20         # Zufallsbilder + Statistik
    python send_image.py --port COM5 --mem vectors/image.mem   # ohne PyTorch
"""

import argparse
import os
import random
import sys
import time

try:
    import serial
except ImportError:
    sys.exit("pyserial fehlt:  pip install pyserial")

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))


def _abs(p):
    return p if os.path.isabs(p) else os.path.join(SCRIPT_DIR, p)


# ---------------------------------------------------------------------------
#  Bildquellen
# ---------------------------------------------------------------------------
def load_mem(path):
    """Fertige .mem-Datei (784 Hex-Bytes) -- braucht KEIN PyTorch."""
    with open(_abs(path)) as f:
        vals = [int(l.strip(), 16) for l in f if l.strip()]
    if len(vals) != 784:
        sys.exit(f"FEHLER: {path} hat {len(vals)} statt 784 Pixel.")
    return bytes(vals)


class Quantizer:
    """Laedt Modell + Testset EINMAL und quantisiert beliebige Testbilder
    exakt wie golden_model.py (gleiche Skala/Zero-Point wie die Hardware)."""

    def __init__(self, model_path="cnn_mnist_int8.pth"):
        import torch
        import torch.quantization
        from torchvision import datasets, transforms
        from model import MeinCNN

        # Quantisierungs-Backend waehlen, sonst:
        #   "Didn't find engine for operation quantized::conv2d_prepack NoQEngine".
        # fbgemm = x86, qnnpack = ARM. Ersten unterstuetzten nehmen.
        for _eng in ("fbgemm", "qnnpack"):
            if _eng in torch.backends.quantized.supported_engines:
                torch.backends.quantized.engine = _eng
                break

        m = MeinCNN(); m.eval(); m.fuse_model()
        m.qconfig = torch.quantization.get_default_qconfig("fbgemm")
        torch.quantization.prepare(m, inplace=True)
        torch.quantization.convert(m, inplace=True)
        m.load_state_dict(torch.load(_abs(model_path), map_location="cpu"))
        m.eval()
        self.model = m
        self.torch = torch

        tf = transforms.Compose([transforms.ToTensor()])
        self.ds = datasets.MNIST(root=_abs("data"), train=False,
                                 download=True, transform=tf)

    def __len__(self):
        return len(self.ds)

    def get(self, index):
        """-> (784 Bytes, wahres Label, PyTorch-Vorhersage)"""
        import numpy as np
        img, label = self.ds[index]
        with self.torch.no_grad():
            xq = self.model.quant(img.unsqueeze(0))
            pred = int(self.model(img.unsqueeze(0)).argmax(dim=1).item())
        raw = xq.int_repr().numpy().astype(np.uint8).flatten()
        return bytes(int(v) & 0xFF for v in raw), int(label), pred


def plot_image(data, title=None):
    """28x28-Vorschau als matplotlib-Fenster (Vollbild, bleibt offen, blockiert NICHT den Ablauf)."""
    import numpy as np
    import matplotlib.pyplot as plt
    arr = np.frombuffer(bytes(data), dtype=np.uint8).reshape(28, 28)
    fig = plt.figure()
    plt.imshow(arr, cmap="gray")
    if title:
        plt.title(title)
    plt.axis("off")

    mgr = fig.canvas.manager
    try:
        mgr.full_screen_toggle()          # Qt/GTK3/GTK4-Agg
    except AttributeError:
        try:
            mgr.window.showMaximized()    # Qt-Backends
        except AttributeError:
            try:
                mgr.window.state("zoomed")   # TkAgg (Windows)
            except Exception:
                try:
                    mgr.window.wm_attributes("-zoomed", True)  # TkAgg (Linux)
                except Exception:
                    try:
                        mgr.frame.Maximize(True)  # WXAgg
                    except Exception:
                        pass

    plt.show(block=False)
    plt.pause(0.001)


def ascii_art(data):
    """28x28-Vorschau im Terminal (Bytes -> Graustufen-Zeichen)."""
    lo, hi = min(data), max(data)
    span = max(hi - lo, 1)
    chars = " .:-=+*#%@"
    lines = []
    for r in range(28):
        row = ""
        for c in range(28):
            v = (data[r * 28 + c] - lo) * (len(chars) - 1) // span
            row += chars[v] * 2
        lines.append(row)
    return "\n".join(lines)


# ---------------------------------------------------------------------------
#  UART
# ---------------------------------------------------------------------------
def classify_on_fpga(ser, data, timeout_s=5.0):
    """784 Bytes senden, Antwortzeile lesen -> erkannte Ziffer (int) oder None."""
    ser.reset_input_buffer()
    ser.write(data)
    ser.flush()
    deadline = time.time() + timeout_s
    line = b""
    while time.time() < deadline:
        b1 = ser.read(1)
        if not b1:
            continue
        if b1 in (b"\r", b"\n"):
            if line:
                break
            continue
        line += b1
    txt = line.decode(errors="replace").strip()
    if len(txt) == 1 and txt.isdigit():
        return int(txt)
    return None


# ---------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", required=True, help="z.B. COM5 oder /dev/ttyUSB0")
    ap.add_argument("--baud", type=int, default=115200)
    src = ap.add_mutually_exclusive_group()
    src.add_argument("--index", type=int, help="EIN MNIST-Testbild (0..9999)")
    src.add_argument("--indices", type=str, help="mehrere, z.B. 0,7,123")
    src.add_argument("--random", type=int, metavar="N", help="N Zufallsbilder + Statistik")
    src.add_argument("--all", action="store_true", help="alle Testbilder senden (10000) + Genauigkeit")
    src.add_argument("--mem", type=str, help="fertige image.mem (ohne PyTorch)")
    ap.add_argument("--seed", type=int, default=None, help="Seed fuer --random")
    ap.add_argument("--show", action="store_true", help="ASCII-Vorschau anzeigen")
    ap.add_argument("--plot", action="store_true", help="Bild vor dem Senden mit matplotlib anzeigen")
    args = ap.parse_args()


    

    # --- Auftragsliste bauen ---
    jobs = []   # (beschreibung, bytes, label|None, pytorch_pred|None)
    if args.mem:
        jobs.append((args.mem, load_mem(args.mem), None, None))
    else:
        q = Quantizer()
        if args.indices:
            idxs = [int(s) for s in args.indices.split(",")]
        elif args.random:
            rng = random.Random(args.seed)
            idxs = rng.sample(range(len(q)), args.random)
        elif args.all:
            idxs = list(range(len(q)))
        else:
            idxs = [args.index if args.index is not None else 0]
        for i in idxs:
            if not (0 <= i < len(q)):
                sys.exit(f"FEHLER: Index {i} ausserhalb 0..{len(q)-1}")
            data, label, pred = q.get(i)
            jobs.append((f"Testbild #{i}", data, label, pred))

    # --- Senden + auswerten ---
    total_jobs = len(jobs)
    show_each = total_jobs <= 100   # bei sehr vielen Bildern (z.B. --all) nur Fortschritt zeigen
    progress_every = 500

    n_label_ok = 0    # FPGA == wahres Label
    n_torch_ok = 0    # FPGA == PyTorch-Vorhersage (das eigentliche HW-Kriterium)
    n_done = 0
    with serial.Serial(args.port, args.baud, timeout=0.2) as ser:
        time.sleep(0.2)
        for desc, data, label, pred in jobs:
            if args.show:
                print(ascii_art(data))
            if args.plot:
                plot_image(data, title=desc)
            digit = classify_on_fpga(ser, data)
            if digit is None:
                sys.exit(f"{desc}: keine Antwort (Timeout). "
                         "Verkabelung/Baudrate/UART_CLK_HZ pruefen.")
            n_done += 1
            parts = [f"{desc}: FPGA={digit}"]
            if label is not None:
                ok_l = digit == label
                n_label_ok += ok_l
                parts.append(f"Label={label} {'OK' if ok_l else 'X'}")
            if pred is not None:
                ok_t = digit == pred
                n_torch_ok += ok_t
                parts.append(f"PyTorch={pred} {'OK' if ok_t else 'X'}")

            if show_each:
                print("  ".join(parts))
            elif n_done % progress_every == 0 or n_done == total_jobs:
                acc_txt = (f"{100.0 * n_label_ok / n_done:.2f} %"
                           if label is not None else "n/a")
                print(f"[{n_done}/{total_jobs}] Genauigkeit bisher: {acc_txt}", flush=True)

    if n_done > 1:
        print("-" * 50)
        print(f"Genauigkeit vs. Label:   {n_label_ok}/{n_done} "
              f"({100.0 * n_label_ok / n_done:.1f} %)")
        print(f"Uebereinstimmung PyTorch: {n_torch_ok}/{n_done} "
              f"({100.0 * n_torch_ok / n_done:.1f} %)")

    if args.plot:
        import matplotlib.pyplot as plt
        print("Fenster offen -- zum Beenden schliessen.")
        plt.show(block=True)


if __name__ == "__main__":
    main()
