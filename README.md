# RVLab 04 — FPGA MNIST Digit Classifier

Hardware-accelerated CNN that classifies handwritten MNIST digits on the
Nexys Video (Artix-7) board. A CV32E40P RISC-V core receives a 28×28 image
over USB-UART, runs inference on a shared 16×16 systolic-array accelerator,
and returns the predicted digit (also shown on the OLED and the 8 LEDs).

- **Network:** conv1 (1→8, 3×3) → pool → conv2 (8→16, 3×3) → pool → fc1
  (400→64) → fc2 (64→10) → argmax, int8 quantized.
- **Accelerator:** one 16×16 systolic array (256 MACs on DSP48) reused for all
  four layers, on its own asynchronous 75 MHz clock domain.
- **Result:** 3876 cycles = 51.7 µs per image, 97.52 % accuracy on the full
  MNIST test set.

## Repository layout

| Path | Contents |
|---|---|
| `src/rtl/student/` | Accelerator and peripheral RTL (`student_*`) |
| `src/rtl/rvlab_fpga/` | SoC top level, clock manager |
| `src/sw/` | RISC-V software (`cnn_uart` = demo, `hal_tests` = self-tests) |
| `src/tb/` | Self-checking testbenches |
| `src/design/` | Register descriptions (reggen), XDC constraints |
| `pytorch/` | Model, quantization, weight packing, golden vectors, PC demo |
| `flow/` | pydesignflow build/sim/synthesis tasks |

## Prerequisites

- Vivado 2022.2 (synthesis) and/or QuestaSim (simulation)
- The RISC-V toolchain used by the lab framework
- Python: `pip install -r pytorch/requirements.txt`

The generated weight/image `.mem` files are already committed in
`src/rtl/student/`, so building the design needs no extra steps. To regenerate
them from the trained model, see `pytorch/README.md`.

## Build and run on the board

```bash
# 1. Synthesize, place & route, generate bitstream
flow rvlab_fpga_top.syn
flow rvlab_fpga_top.bitstream

# 2. Flash the bitstream to the FPGA
flow rvlab_fpga_top.program

# 3. Start the CNN + UART demo program on the RISC-V core
flow sw_cnn_uart.run
```

With the demo running, send an MNIST test image from the host PC over the
USB-UART adapter and read back the classified digit:

```bash
cd pytorch
python send_image.py            # sends an image, prints the predicted digit
```

The recognized digit also appears on the OLED display and in binary on the
8 board LEDs, and the software reports the measured cycle count.

## Simulation and verification

Every module has a self-checking testbench. Run one with:

```bash
flow <testbench>.sim_rtl_questa          # e.g. flow student_cnn_tb.sim_rtl_questa
```

Key testbenches:

- `student_cnn_tb` — full inference through the register interface, scores
  checked bit-exactly against the PyTorch golden model
- `student_cnn_cdc_tb` — same inference across the 50/75 MHz clock domains
- `conv1_verif_tb`, `conv2_verif_tb`, `fc1_verif_tb` — per-layer bit-exact checks
- module-level: `student_systolic_array_tb`, `student_pe_db_tb`,
  `student_ws_accum_tb`, `student_relu_pool_tb`, `student_im2col_tb`,
  `student_act_buffer_tb`, `student_weight_bram_tb`, `student_controller_fsm_tb`,
  `student_argmax_tb`, `student_oled_gpio_tb`, `student_irq_ctrl_tb`,
  `student_uart_tb`, `student_tlul_mux_tb`, `student_rlight_tb`, `student_dma_tb`

`sw_hal_tests` is an on-target C program that checks every peripheral's HAL and
the accelerator registers from software.

## Team

RVLab 04 — Mohannad Al Moued, Abdelrahman Elkholy, Berkant Tug, Selin Orhanlar
(TU Berlin, SoC + RISC-V Lab, SS 26).
