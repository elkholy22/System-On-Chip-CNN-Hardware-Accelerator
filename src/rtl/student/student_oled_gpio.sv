module student_oled_gpio (
  input  logic clk_i,
  input  logic rst_ni,

  output tlul_pkg::tl_d2h_t tl_o,
  input  tlul_pkg::tl_h2d_t tl_i,

  output logic oled_sdin,
  output logic oled_sclk,
  output logic oled_dc,
  output logic oled_res,
  output logic oled_vbat,
  output logic oled_vdd
);

  logic [3:0]  addr;
  logic        we;
  logic        re;
  logic [31:0] wdata;
  logic [31:0] rdata;

  tlul_adapter_reg #(
    .RegAw(4),
    .RegDw(32)
  ) adapter_reg_i (
    .clk_i,
    .rst_ni,
    .tl_i,
    .tl_o,
    .we_o   (we),
    .re_o   (re),
    .addr_o (addr),
    .wdata_o(wdata),
    .be_o   (),
    .rdata_i(rdata),
    .error_i('0)
  );

  // Reset: Display aus. vdd/vbat aktiv-low -> 1=aus; res=0 (im Reset); sclk idle high.
  //  {vdd, vbat, res, dc, sclk, sdin} = {1, 1, 0, 0, 1, 0}
  logic [5:0] gpio_q;

  always_comb begin
    rdata = '0;
    if (re && addr == 4'h0) rdata = {26'b0, gpio_q};
  end

  always_ff @(posedge clk_i, negedge rst_ni) begin
    if (~rst_ni)                 gpio_q <= 6'b11_0_0_1_0;
    else if (we && addr == 4'h0) gpio_q <= wdata[5:0];
  end

  assign oled_sdin = gpio_q[0];
  assign oled_sclk = gpio_q[1];
  assign oled_dc   = gpio_q[2];
  assign oled_res  = gpio_q[3];
  assign oled_vbat = gpio_q[4];
  assign oled_vdd  = gpio_q[5];

endmodule
