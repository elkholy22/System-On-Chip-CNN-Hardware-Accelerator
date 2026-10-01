"""Zeigt ein einzelnes Bild aus dem MNIST-Testset an."""

import argparse
import os

import matplotlib.pyplot as plt
from torchvision import datasets

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--index", type=int, required=True, help="Bildindex im Datensatz")
    ap.add_argument("--train", action="store_true",
                    help="Trainingsset statt Testset verwenden")
    args = ap.parse_args()

    ds = datasets.MNIST(root=os.path.join(SCRIPT_DIR, "data"),
                         train=args.train, download=True)

    if not (0 <= args.index < len(ds)):
        raise SystemExit(f"FEHLER: Index {args.index} ausserhalb 0..{len(ds) - 1}")

    img, label = ds[args.index]

    plt.imshow(img, cmap="gray")
    plt.title(f"Index #{args.index}")
    plt.axis("off")
    plt.show()


if __name__ == "__main__":
    main()
