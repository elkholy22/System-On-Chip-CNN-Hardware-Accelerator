// SPDX-License-Identifier: SHL-2.1
// SPDX-FileCopyrightText: 2024 RVLab Contributors

package rvlab_tap_pkg;

  localparam int unsigned IrLength = 5;
  
  // JTAG IDCODE Value
  localparam logic [31:0] IdcodeValue = 32'h08D00001;
  // xxxx             version
  // xxxxxxxxxxxxxxxx part number
  // xxxxxxxxxxx      manufacturer id
  // 1                required by standard


  typedef enum logic [IrLength-1:0] {
    BYPASS0   = 'h00,
    IDCODE    = 'h01,
    DTMCSR    = 'h10,
    DMIACCESS = 'h11,
    BYPASS1   = 'h1f
  } ir_reg_e;

  typedef struct packed {
    logic [31:18] zero1;
    logic         dmihardreset;
    logic         dmireset;
    logic         zero0;
    logic [14:12] idle;
    logic [11:10] dmistat;
    logic [9:4]   abits;
    logic [3:0]   version;
  } dtmcs_t;

endpackage
