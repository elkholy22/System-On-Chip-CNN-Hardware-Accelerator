module student_pe_db_tb;

  localparam int unsigned ACT_W  = 8;
  localparam int unsigned W_W    = 8;
  localparam int unsigned PSUM_W = 32;
  localparam int unsigned NBANK  = 8;
  localparam int unsigned BW     = 3;

  logic clk, rst_n;
  logic load_w;
  logic [BW-1:0] load_bank;
  logic signed [W_W-1:0] wdata;
  logic [BW-1:0] bank_sel, bank_out;
  logic clear;
  logic signed [ACT_W-1:0]  act_in,  act_out;
  logic signed [PSUM_W-1:0] psum_in, psum_out;

  always begin clk = 1'b1; #10000; clk = 1'b0; #10000; end

  student_pe_db #(
      .ACT_W(ACT_W), .W_W(W_W), .PSUM_W(PSUM_W), .NBANK(NBANK)
  ) dut (
      .clk_i        (clk),
      .rst_ni       (rst_n),
      .load_weight_i(load_w),
      .load_bank_i  (load_bank),
      .weight_i     (wdata),
      .bank_i       (bank_sel),
      .bank_o       (bank_out),
      .clear_i      (clear),
      .act_i        (act_in),
      .psum_i       (psum_in),
      .act_o        (act_out),
      .psum_o       (psum_out)
  );

  int errors = 0;

  logic signed [W_W-1:0] w_model [NBANK];

  task automatic step(input bit lw, input logic [BW-1:0] lb,
                      input logic signed [W_W-1:0] w,
                      input logic signed [ACT_W-1:0] a,
                      input logic signed [PSUM_W-1:0] ps,
                      input logic [BW-1:0] bk,
                      input bit show, input string name);
    logic signed [PSUM_W-1:0] exp_psum;
    int pa, pw;
    bit ok;
    begin
      load_w = lw; load_bank = lb; wdata = w;
      act_in = a; psum_in = ps; bank_sel = bk; clear = 1'b0;
      pa = a;
      pw = w_model[bk];
      exp_psum = ps + pa * pw;
      if (lw) w_model[lb] = w;
      @(posedge clk); #1;
      ok = 1'b1;
      if (psum_out !== exp_psum) begin
        $error("%s: psum_o=%0d, expected %0d", name, psum_out, exp_psum);
        errors++; ok = 1'b0;
      end
      if (act_out !== a) begin
        $error("%s: act_o=%0d, expected %0d", name, act_out, a);
        errors++; ok = 1'b0;
      end
      if (bank_out !== bk) begin
        $error("%s: bank_o=%0d, expected %0d", name, bank_out, bk);
        errors++; ok = 1'b0;
      end
      if (ok && show)
        $display("PASS %s: psum_o=%0d act_o=%0d bank_o=%0d",
                 name, psum_out, act_out, bank_out);
    end
  endtask

  task automatic do_clear();
    begin
      clear = 1'b1; act_in = -8'sd55; psum_in = 32'sd12345; bank_sel = 3'd5;
      @(posedge clk); #1;
      clear = 1'b0; act_in = '0; psum_in = '0; bank_sel = '0;
      if (act_out !== '0 || psum_out !== '0 || bank_out !== '0) begin
        $error("clear_i: outputs not cleared (act=%0d psum=%0d bank=%0d)",
               act_out, psum_out, bank_out);
        errors++;
      end else $display("PASS clear_i flushes outputs");
    end
  endtask

  initial begin
    #200_000_000;
    $error("TIMEOUT");
    $display("==== 1 CHECK(S) FEHLGESCHLAGEN ====");
    $finish;
  end

  initial begin
    int i;
    logic signed [ACT_W-1:0]  ra;
    logic signed [PSUM_W-1:0] rp;
    logic signed [W_W-1:0]    rw;
    logic [BW-1:0] rb, rlb;
    bit rl;

    rst_n = 1'b0; load_w = 1'b0; load_bank = '0; wdata = '0;
    bank_sel = '0; clear = 1'b0; act_in = '0; psum_in = '0;
    for (i = 0; i < NBANK; i++) w_model[i] = '0;
    repeat (4) @(posedge clk); #1;
    rst_n = 1'b1;

    if (act_out !== '0 || psum_out !== '0 || bank_out !== '0) begin
      $error("reset: outputs not zero");
      errors++;
    end else $display("PASS reset state");

    $display("\n--- basic MAC, bank 0 ---");
    step(1, 3'd0, 8'sd5, 8'sd0,  32'sd0,   3'd0, 1, "load b0=5 (old w=0)");
    step(0, 3'd0, 8'sd0, 8'sd3,  32'sd10,  3'd0, 1, "3*5+10");
    step(0, 3'd0, 8'sd0, -8'sd7, 32'sd100, 3'd0, 1, "-7*5+100");
    step(0, 3'd0, 8'sd0, -8'sd7, -32'sd100, 3'd0, 1, "-7*5-100");

    $display("\n--- bank swap (double buffer) ---");
    step(1, 3'd1, -8'sd9, 8'sd2,  32'sd0, 3'd0, 1, "load b1=-9 during 2*5 on b0");
    step(0, 3'd0, 8'sd0,  8'sd4,  32'sd1, 3'd0, 1, "old bank still used: 4*5+1");
    step(0, 3'd0, 8'sd0,  8'sd2,  32'sd0, 3'd1, 1, "swap to b1: 2*(-9)");
    step(0, 3'd0, 8'sd0,  -8'sd3, 32'sd7, 3'd1, 1, "(-3)*(-9)+7");

    $display("\n--- same-bank load timing ---");
    step(1, 3'd0, 8'sd100, 8'sd1, 32'sd0, 3'd0, 1, "load b0=100, MAC still 1*5");
    step(0, 3'd0, 8'sd0,   8'sd1, 32'sd0, 3'd0, 1, "next cycle 1*100");

    $display("\n--- extremes ---");
    step(1, 3'd2, -8'sd128, 8'sd0,   32'sd0, 3'd2, 1, "load b2=-128");
    step(0, 3'd0, 8'sd0,  -8'sd128,  32'sd0, 3'd2, 1, "(-128)*(-128)=16384");
    step(1, 3'd3, 8'sd127, 8'sd0,    32'sd0, 3'd3, 1, "load b3=127");
    step(0, 3'd0, 8'sd0,   8'sd127,  32'sd1, 3'd3, 1, "127*127+1");

    $display("\n--- all banks ---");
    for (i = 0; i < NBANK; i++)
      step(1, 3'(i), 8'(i*17 - 60), 8'sd0, 32'sd0, 3'd0, 0,
           $sformatf("load b%0d", i));
    for (i = 0; i < NBANK; i++)
      step(0, 3'd0, 8'sd0, 8'sd3, 32'(i), 3'(i), 1,
           $sformatf("bank %0d readback", i));

    $display("\n--- clear_i ---");
    do_clear();

    $display("\n--- random phase (300 cycles) ---");
    for (i = 0; i < 300; i++) begin
      ra  = 8'($urandom);
      rp  = $urandom;
      rw  = 8'($urandom);
      rb  = 3'($urandom);
      rlb = 3'($urandom);
      rl  = 1'($urandom);
      step(rl, rlb, rw, ra, rp, rb, 0, $sformatf("rand[%0d]", i));
    end
    $display("random phase done: 300 cycles checked");

    if (errors == 0) $display("\n==== ALLE CHECKS BESTANDEN ====");
    else             $display("\n==== %0d CHECK(S) FEHLGESCHLAGEN ====", errors);
    $finish;
  end

endmodule
