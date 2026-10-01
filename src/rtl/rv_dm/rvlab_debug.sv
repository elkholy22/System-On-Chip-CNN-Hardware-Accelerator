// SPDX-License-Identifier: SHL-2.1
// SPDX-FileCopyrightText: 2024 RVLab Contributors

module rvlab_debug(
  input logic clk_i,
  input logic rst_ni,

  input  logic jtag_tck_i,
  input  logic jtag_tdi_i,
  output logic jtag_tdo_o,
  input  logic jtag_tms_i,
  input  logic jtag_trst_ni,

  output logic ndmreset_o,

  output logic debug_req_o,

  output tlul_pkg::tl_d2h_t tl_dbgmem_d2h_o,
  input  tlul_pkg::tl_h2d_t tl_dbgmem_h2d_i,

  input  tlul_pkg::tl_d2h_t tl_dbgsba_d2h_i,
  output tlul_pkg::tl_h2d_t tl_dbgsba_h2d_o
); 
  logic       test_logic_reset;
  logic       shift_dr;
  logic       update_dr;
  logic       capture_dr;

  logic       dmi_access;
  logic       dmi_reset;
  logic [1:0] dmi_error;
  logic       dmi_tdo;
  logic       dtmcs_select;

  rvlab_tap tap_i (
    .tck_i             (jtag_tck_i),
    .tms_i             (jtag_tms_i),
    .trst_ni           (jtag_trst_ni),
    .td_i              (jtag_tdi_i),
    .td_o              (jtag_tdo_o),
    .test_logic_reset_o(test_logic_reset),
    .shift_dr_o        (shift_dr),
    .update_dr_o       (update_dr),
    .capture_dr_o      (capture_dr),

    .dmi_access_o  (dmi_access),
    .dmi_reset_o   (dmi_reset),
    .dmi_error_i   (dmi_error),
    .dmi_tdo_i     (dmi_tdo),
    .dtmcs_select_o(dtmcs_select)
  );

  rv_dm #(
    .NrHarts(1)
  ) u_dm_top (
    .clk_i,
    .rst_ni,

    .testmode_i   ('0),
    .ndmreset_o,
    .dmactive_o   (),
    .debug_req_o,
    .unavailable_i('0),

    // bus device with debug memory (for execution-based debug)
    .tl_d_i(tl_dbgmem_h2d_i),
    .tl_d_o(tl_dbgmem_d2h_o),

    // bus host (for system bus accesses, SBA)
    .tl_h_o(tl_dbgsba_h2d_o),
    .tl_h_i(tl_dbgsba_d2h_i),

    .tck_i             (jtag_tck_i),
    .test_logic_reset_i(test_logic_reset),
    .shift_dr_i        (shift_dr),
    .update_dr_i       (update_dr),
    .capture_dr_i      (capture_dr),
    .trst_ni           (jtag_trst_ni),

    .dmi_access_i  (dmi_access),
    .dmi_reset_i   (dmi_reset),
    .dmi_error_o   (dmi_error),
    .dmi_tdi_i     (jtag_tdi_i),
    .dmi_tdo_o     (dmi_tdo),
    .dtmcs_select_i(dtmcs_select)
  );
endmodule
