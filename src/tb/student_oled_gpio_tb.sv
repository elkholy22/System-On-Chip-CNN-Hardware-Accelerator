module student_oled_gpio_tb;
  logic clk;
  logic rst_n;
  logic sdin, sclk, dc, res, vbat, vdd;
  tlul_pkg::tl_d2h_t tl_d2h;
  tlul_pkg::tl_h2d_t tl_h2d;

  localparam logic [31:0] ADDR_GPIO = 32'h0;

  localparam int B_SDIN = 0;
  localparam int B_SCLK = 1;
  localparam int B_DC   = 2;
  localparam int B_RES  = 3;
  localparam int B_VBAT = 4;
  localparam int B_VDD  = 5;

  localparam logic [5:0] RESET_VAL = 6'b110010;

  always begin
    clk = '1; #10000;
    clk = '0; #10000;
  end

  student_oled_gpio DUT (
    .clk_i    (clk),
    .rst_ni   (rst_n),
    .tl_i     (tl_h2d),
    .tl_o     (tl_d2h),
    .oled_sdin(sdin),
    .oled_sclk(sclk),
    .oled_dc  (dc),
    .oled_res (res),
    .oled_vbat(vbat),
    .oled_vdd (vdd)
  );

  tlul_test_host bus (
    .clk_i (clk),
    .rst_no(rst_n),
    .tl_i  (tl_d2h),
    .tl_o  (tl_h2d)
  );

  int errors = 0;

  task automatic check_pins(input logic [5:0] expected, input string name);
    logic [5:0] pins;
    #1;
    pins = {vdd, vbat, res, dc, sclk, sdin};
    if (pins !== expected) begin
      $error("FAIL %s: pins {vdd,vbat,res,dc,sclk,sdin} = %06b, expected %06b",
             name, pins, expected);
      errors++;
    end else begin
      $display("PASS %s: pins = %06b", name, pins);
    end
  endtask

  task automatic check_reg(input logic [31:0] addr,
                           input logic [31:0] expected,
                           input string       name);
    logic [31:0] rdata;
    bus.get_word(addr, rdata);
    if (rdata !== expected) begin
      $error("FAIL %s: read 0x%08x, expected 0x%08x", name, rdata, expected);
      errors++;
    end else begin
      $display("PASS %s = 0x%08x", name, rdata);
    end
  endtask

  task automatic write_and_check(input logic [5:0] value, input string name);
    bus.put_word(ADDR_GPIO, {26'b0, value});
    check_pins(value, name);
    check_reg(ADDR_GPIO, {26'b0, value}, {name, " readback"});
  endtask

  task automatic spi_bit(input logic [5:0] base, input logic d,
                         output logic sampled);
    logic [5:0] v;
    v = base;
    v[B_SDIN] = d;
    v[B_SCLK] = 1'b0;
    bus.put_word(ADDR_GPIO, {26'b0, v});
    check_pins(v, "spi sclk low");
    v[B_SCLK] = 1'b1;
    bus.put_word(ADDR_GPIO, {26'b0, v});
    check_pins(v, "spi sclk high");
    sampled = sdin;
  endtask

  initial begin
    logic [5:0] v;
    logic [7:0] tx_byte, rx_byte;
    logic       s;

    bus.reset();

    $display("\n--- reset values ---");
    check_pins(RESET_VAL, "reset pins");
    check_reg(ADDR_GPIO, {26'b0, RESET_VAL}, "GPIO reset readback");

    $display("\n--- one-hot pin walk ---");
    write_and_check(6'b000001, "sdin only");
    write_and_check(6'b000010, "sclk only");
    write_and_check(6'b000100, "dc only");
    write_and_check(6'b001000, "res only");
    write_and_check(6'b010000, "vbat only");
    write_and_check(6'b100000, "vdd only");

    $display("\n--- pattern writes ---");
    write_and_check(6'b000000, "all low");
    write_and_check(6'b111111, "all high");
    write_and_check(6'b101010, "pattern 101010");
    write_and_check(6'b010101, "pattern 010101");

    $display("\n--- upper bits ignored ---");
    bus.put_word(ADDR_GPIO, 32'hFFFF_FFC0);
    check_pins(6'b000000, "write 0xFFFFFFC0 -> pins low");
    check_reg(ADDR_GPIO, 32'h0, "readback masked to [5:0]");

    $display("\n--- other offsets ---");
    bus.put_word(ADDR_GPIO, {26'b0, 6'b100110});
    bus.put_word(32'h4, 32'hFFFF_FFFF);
    bus.put_word(32'h8, 32'h0000_003F);
    check_pins(6'b100110, "pins unchanged after off-target writes");
    check_reg(ADDR_GPIO, 32'h0000_0026, "GPIO reg unchanged");
    check_reg(32'h4, 32'h0, "offset 0x4 reads 0");
    check_reg(32'h8, 32'h0, "offset 0x8 reads 0");
    check_reg(32'hC, 32'h0, "offset 0xC reads 0");

    $display("\n--- power-up sequence ---");
    write_and_check(6'b110010, "start from reset state");
    write_and_check(6'b010010, "vdd on (active low)");
    write_and_check(6'b011010, "release reset (res=1)");
    write_and_check(6'b010010, "reset pulse low");
    write_and_check(6'b011010, "reset high again");
    write_and_check(6'b001010, "vbat on (active low)");

    $display("\n--- SPI command byte 0xA5 ---");
    tx_byte = 8'hA5;
    v = 6'b001010;
    v[B_DC] = 1'b0;
    rx_byte = '0;
    for (int i = 7; i >= 0; i--) begin
      spi_bit(v, tx_byte[i], s);
      rx_byte = {rx_byte[6:0], s};
    end
    if (rx_byte !== tx_byte) begin
      $error("FAIL SPI byte: sampled 0x%02x, expected 0x%02x", rx_byte, tx_byte);
      errors++;
    end else begin
      $display("PASS SPI byte sampled on rising edges = 0x%02x", rx_byte);
    end
    if (dc !== 1'b0) begin
      $error("FAIL dc: not low during command byte");
      errors++;
    end else begin
      $display("PASS dc stayed low during command byte");
    end

    $display("\n--- SPI data byte 0x3C ---");
    tx_byte = 8'h3C;
    v[B_DC] = 1'b1;
    bus.put_word(ADDR_GPIO, {26'b0, v});
    check_pins(v, "dc high before data byte");
    rx_byte = '0;
    for (int i = 7; i >= 0; i--) begin
      spi_bit(v, tx_byte[i], s);
      rx_byte = {rx_byte[6:0], s};
    end
    if (rx_byte !== tx_byte) begin
      $error("FAIL SPI byte: sampled 0x%02x, expected 0x%02x", rx_byte, tx_byte);
      errors++;
    end else begin
      $display("PASS SPI byte sampled on rising edges = 0x%02x", rx_byte);
    end

    if (errors == 0) $display("\n==== ALLE CHECKS BESTANDEN ====");
    else             $display("\n==== %0d CHECK(S) FEHLGESCHLAGEN ====", errors);

    $finish;
  end

endmodule
