"""Erzeugt image7.h (C-Array) aus vectors/image.mem fuer die CNN-Software."""

import argparse
import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
def _abs(p): return p if os.path.isabs(p) else os.path.join(SCRIPT_DIR, p)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mem", default="vectors/image.mem")
    ap.add_argument("--out", default="image7.h")
    ap.add_argument("--label", type=int, default=7)
    args = ap.parse_args()

    with open(_abs(args.mem)) as f:
        vals = [int(line.strip(), 16) for line in f if line.strip()]
    assert len(vals) == 784, f"{len(vals)} statt 784 Pixel in {args.mem}"

    with open(_abs(args.out), "w") as f:
        f.write("/* Auto-generiert von make_image_header.py aus %s */\n" % args.mem)
        f.write("#ifndef _IMAGE7_H\n#define _IMAGE7_H\n\n#include <stdint.h>\n\n")
        f.write("#define IMAGE7_LABEL %du\n\n" % args.label)
        f.write("static const uint8_t image7[784] = {\n")
        for i in range(0, 784, 16):
            row = ", ".join(f"0x{v:02x}" for v in vals[i:i+16])
            f.write("    " + row + ",\n")
        f.write("};\n\n#endif /* _IMAGE7_H */\n")

    print(f"{args.out} geschrieben (784 Pixel, Label {args.label}).")
    print("-> cp image7.h ../src/sw/cnn/")


if __name__ == "__main__":
    main()
