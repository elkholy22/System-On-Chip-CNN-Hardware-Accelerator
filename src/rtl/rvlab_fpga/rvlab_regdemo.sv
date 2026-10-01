// SPDX-License-Identifier: SHL-2.1
// SPDX-FileCopyrightText: 2024 RVLab Contributors

module rvlab_regdemo (
  input clk_i,
  input rst_ni,

  input  tlul_pkg::tl_h2d_t tl_i,
  output tlul_pkg::tl_d2h_t tl_o
);
  import regdemo_reg_pkg::*;

  regdemo_reg2hw_t reg2hw;
  regdemo_hw2reg_t hw2reg;

  regdemo_reg_top reg_top_i (
    .clk_i,
    .rst_ni,
    .tl_i,
    .tl_o,
    .reg2hw,
    .hw2reg,
    .devmode_i('0)
  );

  always_ff @(posedge clk_i, negedge rst_ni) begin
    if (~rst_ni) begin
      hw2reg.shiftout.d <= '0;
    end else begin
      if (reg2hw.shiftcfg.dir.q) begin
        // right shift
        hw2reg.shiftout.d <= reg2hw.shiftin.q >> reg2hw.shiftcfg.amt.q;
      end else begin
        // left shift
        hw2reg.shiftout.d <= reg2hw.shiftin.q << reg2hw.shiftcfg.amt.q;
      end
    end
  end

endmodule
