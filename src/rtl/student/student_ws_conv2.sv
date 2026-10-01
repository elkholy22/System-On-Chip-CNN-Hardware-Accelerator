module student_ws_conv2 (
    input  logic clk_i,
    input  logic rst_ni,
    input  logic start_i,
    output logic busy_o,
    output logic done_o,
    output logic [10:0]                buf_raddr_o,
    input  logic signed [63:0]         buf_rdata_i,
    output logic                       rp_start_o,
    output logic                       rvalid_o,
    output logic                       grp_o,
    output logic signed [7:0][31:0]    result_o
);

  // Das Array liegt in student_ws_conv; dieser Wrapper haelt
  // eine LOKALE Array-Instanz, damit die conv2-Engine-TB self-contained bleibt.
  logic                        w_start, w_wload, w_avalid;
  logic signed [15:0][15:0][7:0] w_wtile;
  logic signed [15:0][7:0]     w_arow;
  logic signed [15:0][31:0]    w_rpsum;

  student_ws_conv #(
      .N(16), .ACT_W(8), .W_W(8), .PSUM_W(32),
      .NPOS_MAX(676), .IMW_C2(13), .CONV1_BASE(5), .DRAIN_CYC(36)
  ) u_e (
      .clk_i, .rst_ni,
      .start_i     (start_i),
      .mode_i      (1'b1),          // conv2
      .busy_o      (busy_o),
      .done_o      (done_o),
      .buf_raddr_o (buf_raddr_o),
      .buf_rdata_i (buf_rdata_i),
      .buf_raddr2_o(),             // Tap-B-Port: die conv2-Engine-TB muss ihn fuer
      .buf_rdata2_i(buf_rdata_i),  //   korrekte Werte modellieren (hier nur Compile).
      .pbuf_raddr_o(),              // ungenutzt im conv2-Modus
      .pbuf_rdata_i(72'b0),
      .rp_start_o  (rp_start_o),
      .rvalid_o    (rvalid_o),
      .grp_o       (grp_o),
      .result_o    (result_o),
      .a_start_o   (w_start),
      .a_wload_o   (w_wload),
      .a_avalid_o  (w_avalid),
      .a_wtile_o   (w_wtile),
      .a_arow_o    (w_arow),
      .a_rpsum_i   (w_rpsum)
  );

  student_systolic_array #(.N(16), .ACT_W(8), .W_W(8), .PSUM_W(32), .NBANK(2)) u_arr (
      .clk_i, .rst_ni,
      .start_i        (w_start),
      .mode_route_i   (1'b1),
      .num_steps_i    (9'd0),
      .weight_load_i  (w_wload),
      .load_bank_i    ('0),
      .use_bank_i     ('0),
      .weight_tile_i  (w_wtile),
      .act_valid_i    (w_avalid),
      .ready_o        (),
      .act_row_i      (w_arow),
      .result_valid_o (),
      .result_o       (),
      .right_psum_o   (w_rpsum)
  );

endmodule
