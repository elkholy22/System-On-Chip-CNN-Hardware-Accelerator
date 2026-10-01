module student_irq_ctrl_tb;

  localparam int IRQ_MAX = 32;

  logic clk;
  logic rst_n;
  logic [IRQ_MAX-1:0] irq;
  logic irq_out;
  tlul_pkg::tl_d2h_t tl_d2h;
  tlul_pkg::tl_h2d_t tl_h2d;

  localparam logic [31:0] ADDR_ALL_EN   = 32'h00;
  localparam logic [31:0] ADDR_MASK     = 32'h04;
  localparam logic [31:0] ADDR_MASK_SET = 32'h08;
  localparam logic [31:0] ADDR_MASK_CLR = 32'h0C;
  localparam logic [31:0] ADDR_STATUS   = 32'h10;
  localparam logic [31:0] ADDR_IRQ_NO   = 32'h14;
  localparam logic [31:0] ADDR_TEST     = 32'h18;
  localparam logic [31:0] ADDR_TEST_IRQ = 32'h1C;

  always begin
    clk = '1; #10000;
    clk = '0; #10000;
  end

  student_irq_ctrl #(.IRQ_MAX(IRQ_MAX)) DUT (
    .clk_i (clk),
    .rst_ni(rst_n),
    .tl_o  (tl_d2h),
    .tl_i  (tl_h2d),
    .irq_i (irq),
    .irq_o (irq_out)
  );

  tlul_test_host bus (
    .clk_i (clk),
    .rst_no(rst_n),
    .tl_i  (tl_d2h),
    .tl_o  (tl_h2d)
  );

  int errors = 0;

  task automatic check_reg(input logic [31:0] addr,
                           input logic [31:0] expected,
                           input string       name);
    logic [31:0] rdata;
    bus.get_word(addr, rdata);
    if (rdata !== expected) begin
      $error("FAIL %s: expected 0x%08x, read 0x%08x", name, expected, rdata);
      errors++;
    end else begin
      $display("PASS %s = 0x%08x", name, rdata);
    end
  endtask

  task automatic check_irq(input logic expected, input string name);
    @(posedge clk); #1;
    if (irq_out !== expected) begin
      $error("FAIL %s: irq_o=%b, expected %b", name, irq_out, expected);
      errors++;
    end else begin
      $display("PASS %s: irq_o=%b", name, irq_out);
    end
  endtask

  task automatic check_irq_low_for(input int n, input string name);
    bit fail = 0;
    for (int i = 0; i < n; i++) begin
      @(posedge clk); #1;
      if (irq_out !== 1'b0) fail = 1;
    end
    if (fail) begin
      $error("FAIL %s: irq_o went high", name);
      errors++;
    end else begin
      $display("PASS %s: irq_o stayed 0 for %0d cycles", name, n);
    end
  endtask

  initial begin
    irq = '0;
    bus.reset();

    $display("\n--- Reset values / everything off ---");
    check_reg(ADDR_ALL_EN, 32'h0,  "ALL_EN reset");
    check_reg(ADDR_MASK,   32'h0,  "MASK reset");
    check_reg(ADDR_TEST,   32'h0,  "TEST reset");
    check_reg(ADDR_IRQ_NO, IRQ_MAX, "IRQ_NO reset (none)");

    irq = '1;
    check_irq_low_for(5, "disabled+masked: no irq_o");
    check_reg(ADDR_STATUS, 32'hFFFF_FFFF, "STATUS shows raw sources");

    bus.put_word(ADDR_ALL_EN, 32'h1);
    check_irq_low_for(5, "enabled but mask=0: no irq_o");

    bus.put_word(ADDR_ALL_EN, 32'h0);
    bus.put_word(ADDR_MASK, 32'hFFFF_FFFF);
    check_irq_low_for(5, "mask=all but ALL_EN=0: no irq_o");

    irq = '0;
    bus.put_word(ADDR_MASK, 32'h0);

    $display("\n--- Single source (bit 5) ---");
    bus.put_word(ADDR_ALL_EN, 32'h1);
    bus.put_word(ADDR_MASK, 32'h1 << 5);
    check_reg(ADDR_MASK, 32'h0000_0020, "MASK wr/rd");
    irq[5] = 1'b1;
    check_irq(1'b1, "source 5 fires");
    check_reg(ADDR_STATUS, 32'h0000_0020, "STATUS bit 5 set");
    check_reg(ADDR_IRQ_NO, 32'd5, "IRQ_NO = 5");

    $display("\n--- Clear mechanisms ---");
    irq[5] = 1'b0;
    check_irq(1'b0, "source dropped -> irq_o low");
    check_reg(ADDR_STATUS, 32'h0, "STATUS clear again");

    irq[5] = 1'b1;
    check_irq(1'b1, "source 5 fires again");
    bus.put_word(ADDR_MASK_CLR, 32'h1 << 5);
    check_irq(1'b0, "MASK_CLR silences irq_o");
    check_reg(ADDR_STATUS, 32'h0000_0020, "STATUS still shows raw source");
    check_reg(ADDR_IRQ_NO, IRQ_MAX, "IRQ_NO = none (masked)");
    irq[5] = 1'b0;

    $display("\n--- Two sources (bits 3 and 12) ---");
    bus.put_word(ADDR_MASK, 32'hFFFF_FFFF);
    irq[3]  = 1'b1;
    irq[12] = 1'b1;
    check_irq(1'b1, "two sources -> irq_o");
    check_reg(ADDR_STATUS, 32'h0000_1008, "STATUS bits 3+12");
    check_reg(ADDR_IRQ_NO, 32'd3, "IRQ_NO = lowest (3)");
    irq[3] = 1'b0;
    check_reg(ADDR_IRQ_NO, 32'd12, "IRQ_NO = 12 after bit 3 drops");
    irq[12] = 1'b0;
    check_irq(1'b0, "all sources gone -> irq_o low");

    $display("\n--- Level (not edge) behavior ---");
    irq[7] = 1'b1;
    check_irq(1'b1, "pulse high phase -> irq_o");
    irq[7] = 1'b0;
    check_irq(1'b0, "pulse ended -> irq_o follows");
    check_reg(ADDR_STATUS, 32'h0, "no latched pending after pulse");

    $display("\n--- Register write/readback ---");
    bus.put_word(ADDR_MASK, 32'h0000_00F0);
    bus.put_word(ADDR_MASK_SET, 32'h0000_000F);
    check_reg(ADDR_MASK, 32'h0000_00FF, "MASK_SET ORs bits in");
    bus.put_word(ADDR_MASK_CLR, 32'h0000_0030);
    check_reg(ADDR_MASK, 32'h0000_00CF, "MASK_CLR clears bits");

    bus.put_word(ADDR_TEST_IRQ, 32'h1 << 9);
    bus.put_word(ADDR_TEST, 32'h1);
    check_reg(ADDR_TEST, 32'h1, "TEST wr/rd");
    check_reg(ADDR_TEST_IRQ, 32'h0000_0200, "TEST_IRQ wr/rd");

    bus.put_word(ADDR_MASK, 32'hFFFF_FFFF);
    check_reg(ADDR_STATUS, 32'h0000_0200, "STATUS = TEST_IRQ in test mode");
    check_reg(ADDR_IRQ_NO, 32'd9, "IRQ_NO = 9 in test mode");
    check_irq(1'b1, "test mode drives irq_o");
    irq = '1;
    check_reg(ADDR_STATUS, 32'h0000_0200, "irq_i ignored in test mode");
    irq = '0;
    bus.put_word(ADDR_TEST, 32'h0);
    check_irq(1'b0, "back to normal mode, quiet");

    check_reg(ADDR_ALL_EN, 32'h1, "ALL_EN still 1");
    bus.put_word(ADDR_ALL_EN, 32'h0);
    check_reg(ADDR_ALL_EN, 32'h0, "ALL_EN wr/rd 0");

    if (errors == 0) $display("\n==== ALLE CHECKS BESTANDEN ====");
    else             $display("\n==== %0d CHECK(S) FEHLGESCHLAGEN ====", errors);

    $finish;
  end

endmodule
