"""Vergleicht die HW-Ergebnisziffer mit der Golden-Referenz (vectors/expected.txt)."""

import argparse
import glob
import os
import sys


def read_digit(path: str) -> int:
    with open(path) as f:
        first = f.readline().strip()
    tok = first.split()[0]
    return int(tok)


def find_result(explicit: str) -> str:
    if explicit:
        return explicit
    candidates = ["student_cnn_result.txt"]
    candidates += glob.glob("**/student_cnn_result.txt", recursive=True)
    for c in candidates:
        if os.path.isfile(c):
            return c
    return ""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--result", default="", help="student_cnn_result.txt der Sim")
    ap.add_argument("--expected", default="vectors/expected.txt")
    args = ap.parse_args()

    res_path = find_result(args.result)
    if not res_path:
        print("FEHLER: student_cnn_result.txt nicht gefunden.")
        print("  -> Erst die Simulation laufen lassen, dann die Datei hierher")
        print("     kopieren oder mit --result <pfad> angeben.")
        sys.exit(2)

    if not os.path.isfile(args.expected):
        print(f"FEHLER: {args.expected} nicht gefunden.")
        print("  -> Erst golden_model.py laufen lassen.")
        sys.exit(2)

    hw = read_digit(res_path)
    gold = read_digit(args.expected)

    print("=" * 50)
    print(f"Hardware-Ziffer (Sim)     : {hw}   [{res_path}]")
    print(f"Golden-Ziffer (PyTorch)   : {gold} [{args.expected}]")
    print("=" * 50)
    if hw == gold:
        print("### PASS: Hardware stimmt mit PyTorch ueberein ###")
        sys.exit(0)
    else:
        print("### FAIL: Abweichung ###")
        sys.exit(1)


if __name__ == "__main__":
    main()
