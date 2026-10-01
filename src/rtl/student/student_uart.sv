// student_uart.sv

module student_uart (
  input  logic clk_i,
  input  logic rst_ni,

  input  tlul_pkg::tl_h2d_t tl_i,
  output tlul_pkg::tl_d2h_t tl_o,

  input  logic rx_serial_i,   // physical RX pin
  output logic tx_serial_o    // physical TX pin
);

  import student_uart_reg_pkg::*;

  student_uart_reg2hw_t reg2hw;
  student_uart_hw2reg_t hw2reg;

  student_uart_reg_top reg_top_i (
    .clk_i,
    .rst_ni,
    .tl_i,
    .tl_o,
    .reg2hw,
    .hw2reg,
    .devmode_i('0)
  );

  logic       tx_busy, rx_valid;
  logic [7:0] rx_data;

  assign hw2reg.status.tx_busy.d  = tx_busy;
  assign hw2reg.status.rx_valid.d = rx_valid;
  assign hw2reg.rxdata.d          = rx_data;

  student_uart_core core_i (
    .clk_i,
    .rst_ni,
    .enable_i   (reg2hw.ctrl.enable.q),
    .baud_div_i (reg2hw.ctrl.baud_div.q),

    .tx_data_i  (reg2hw.txdata.q),    // kollabiertes Einzel-Feld (siehe hjson)
    .tx_start_i (reg2hw.txdata.qe),
    .tx_busy_o  (tx_busy),
    .tx_serial_o(tx_serial_o),

    .rx_serial_i(rx_serial_i),
    .rx_data_o  (rx_data),
    .rx_valid_o (rx_valid),
    .rx_clear_i (reg2hw.rxdata.re)
  );

endmodule