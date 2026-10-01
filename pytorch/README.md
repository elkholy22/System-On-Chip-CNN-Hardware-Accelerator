# PyTorch-Toolchain fuer den CNN-Beschleuniger

Alle Python-Werkzeuge, die die Hardware-Artefakte (`.mem`, `image7.h`) erzeugen,
die Verifikation gegen PyTorch treiben und die FPGA-Demo bedienen.

Modell: **MeinCNN** (`model.py`), post-training static quantisiert (fbgemm, int8):
conv1 1→8 k3 → pool → conv2 8→16 k3 → pool → fc1 400→64 → fc2 64→10 → argmax.

## Setup

```bash
pip install -r requirements.txt
```

Benoetigt wird ausserdem das trainierte Modell **`cnn_mnist_int8.pth`** in diesem
Ordner (binaer, ggf. aus dem Original-Trainingsordner kopieren). Der MNIST-
Datensatz (`data/`) wird beim ersten Lauf automatisch heruntergeladen.

## Workflow: Hardware-Artefakte erzeugen

Reihenfolge bei einem frischen Checkout (Ziel: `../src/rtl/student/`):

```bash
# 1. Gewichte im Kachel-Format des systolischen Arrays
python reorder_weights.py
cp weights.mem ../src/rtl/student/

# 2. Per-Kanal-Requant: Offset/Multiplikator/Shift pro Ausgangskanal
python export_bias.py
cp bias.mem mult.mem shift.mem ../src/rtl/student/

# 3. Testbild + Golden-Referenzen (Ziffer, Schicht-Zwischenwerte)
python golden_model.py --index 0
cp vectors/image.mem ../src/rtl/student/

# 4. Testbild als C-Header fuer die Software
python make_image_header.py
cp image7.h ../src/sw/cnn/
```

## Verifikation (gegen PyTorch)

| Skript | erzeugt | geprueft von (Testbench) |
|---|---|---|
| `conv1_check.py` | conv1_patch/expected.mem | `conv1_verif_tb` |
| `conv2_check.py` | conv2_window/expected.mem | `conv2_verif_tb` |
| `fc1_check.py` | fc1_input/expected.mem | `fc1_verif_tb` |
| `golden_model.py` | vectors/ (Golden je Schicht + Ziffer) | `student_cnn_tb` |
| `compare.py` | — (vergleicht HW-Ziffer mit Golden) | — |

Die `.mem`-Ausgaben jeweils nach `../src/rtl/student/` kopieren, dann
`flow <tb>.sim_rtl_questa`. End-to-End: `student_cnn_tb` schreibt
`student_cnn_result.txt` → `python compare.py --result <pfad>`.

## FPGA-Demo (CNN + UART)

`send_image.py` schickt beliebige MNIST-Testbilder ueber einen USB-UART-Adapter
(Pmod A: Adapter-TX→Pin1, Adapter-RX→Pin2, GND) an das laufende
`sw_cnn_uart`-Programm und liest die klassifizierte Ziffer zurueck:

```bash
python send_image.py --port COM5 --index 42          # ein Bild
python send_image.py --port COM5 --random 50         # 50 Zufallsbilder + Genauigkeit
python send_image.py --port COM5 --index 3 --show    # mit ASCII-Vorschau
python send_image.py --port COM5 --mem vectors/image.mem  # ohne PyTorch (nur pyserial)
```

Der `--mem`-Modus braucht nur pyserial → ideal fuer den Labor-PC (Skript +
`.mem`-Dateien kopieren, kein PyTorch noetig).

## Wichtige Konventionen (muessen zur Hardware passen)

- **Kachel-Layout** (`reorder_weights.py`): tile[r][c] = Gewicht[Ausgang r][Kontraktion c];
  Basen conv1=0, conv2=2, fc1=20, fc2=420 (= `op_wbase` in `student_cnn.sv`).
- **Requant** (`export_bias.py`): per-Kanal `(MAC+offset)*mult >>> shift` mit
  Rundung; Zero-Point-Korrektur nur bei conv1. Basen in bias/mult/shift.mem:
  conv1=0, conv2=8, fc1=24, fc2=88.
- **fc1-Wortreihenfolge**: Wort s<25 = conv2-Gruppe0 Position s, s>=25 = Gruppe1.
- **Baudrate** (`send_image.py` / `sw_cnn_uart`): baud_div = clk_hz/baud − 1.
