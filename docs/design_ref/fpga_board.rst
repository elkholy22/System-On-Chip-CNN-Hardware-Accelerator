.. _`fpga_board`:

FPGA Board
^^^^^^^^^^

.. figure:: fpga_board.jpg
   :width: 100%

   Nexys Video FPGA board mounted in acrylic glass

The RISC-V Lab uses the Digilent Nexys Video board with the Xilinx Artix-7 XC7A200T FPGA (see :ref:`resources`).

See :ref:`fpga_upload` for how to load FPGA bitstreams and programs to the board. 

External Components
-------------------

Following components are already used in the predefined rvlab codebase:

- USB-JTAG Prog via FT2232 (bitstream loading & RISC-V debug)
- 100 MHz crystal oscillator (clock source for MMCM)
- 512 MB DDR3 DRAM (external volatile memory attached to TL-UL bus)

The following table lists components and connectors that can be used for student project I/O. The signals are available in the *userio_fpga2board_t* and *userio_board2fpga_t* structs defined in *src/rtl/rvlab_fpga/pkg/top_pkg.sv* and connected to the student module.  

+-----------------------------+--------------+-------------------------+
| Component                   | Signal Names | Notes                   |
+=============================+==============+=========================+
| 8x LEDs                     | led          |                         |
+-----------------------------+--------------+-------------------------+
| 8x user switches            | switch       |                         |
+-----------------------------+--------------+-------------------------+
| OLED mini display           | oled\_...    |                         |
+-----------------------------+--------------+-------------------------+
| Audio Codec                 | ac\_...      |                         |
+-----------------------------+--------------+-------------------------+
| USB-UART FT232R             | uart\_...    | \(2\)                   |
+-----------------------------+--------------+-------------------------+
| HDMI sink / input           | hdmi_rx\_... |                         |
+-----------------------------+--------------+-------------------------+
| HDMI source / output        | hdmi_tx\_... |                         |
+-----------------------------+--------------+-------------------------+
| USB HID Host (PS/2)         | ps2\_...     |                         |
+-----------------------------+--------------+-------------------------+
| Ethernet PHY (RGMII + MDIO) | eth\_...     |                         |
+-----------------------------+--------------+-------------------------+
| Micro SD card               | sd\_...      |                         |
+-----------------------------+--------------+-------------------------+
| Pmod JA (200 ohm protected) | pmod_a\_...  |                         |
+-----------------------------+--------------+-------------------------+
| Pmod JB (unprotected)       | pmod_d\_...  | use with caution! \(1\) |
+-----------------------------+--------------+-------------------------+
| Pmod JC (unprotected)       | pmod_c\_...  | use with caution! \(1\) |
+-----------------------------+--------------+-------------------------+

**\(1\)** Pmod JB and JC must be used with caution: There is no series protection, so driving a signal both externally and from the FPGA can result in permanent damage to the FPGA! 

**\(2\)** Use JTAG for data transfer if possible.

Following components **should not be used** in the project:

- Pmod JXADC, reason: uses VADJ voltage rail
- 5x user buttons (cross-shaped), reason: prevent mechanical damage
- FMC LPC connector, reason: board will be added in the future
- QSPI Flash, reason: for on-board memory, use volatile DDR3 instead.
- DisplayPort source, reason: HDMI is easier to work with, DisplayPort requires additional Xilinx IP

Mechanical Design
-----------------

- :download:`Acrylic board drawing <mechanical/acrylic_board.pdf>`
- STL files for 3D printing :download:`part 1 <mechanical/cable_clamp_part1.stl>` and :download:`part 2 <mechanical/cable_clamp_part2.stl>` of the USB cable strain-relief clamp