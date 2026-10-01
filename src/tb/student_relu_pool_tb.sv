module student_relu_pool_tb;

  localparam int unsigned IN_W      = 32;
  localparam int unsigned OUT_W     = 8;
  localparam int unsigned IMG_W_MAX = 26;
  localparam int unsigned IMG_H_MAX = 26;

  logic clk, rst_n;
  logic start;
  logic [5:0] img_w, img_h;
  logic relu_en, pool_en;
  logic signed [31:0] rq_mult;
  logic [5:0] rq_shift;
  logic valid_in, ready_out;
  logic signed [IN_W-1:0]  pixel;
  logic ready_in, valid_out;
  logic signed [OUT_W-1:0] act;

  always begin clk = 1'b1; #10000; clk = 1'b0; #10000; end

  student_relu_pool #(
      .IN_W(IN_W), .OUT_W(OUT_W), .IMG_W_MAX(IMG_W_MAX), .IMG_H_MAX(IMG_H_MAX)
  ) dut (
      .clk_i               (clk),
      .rst_ni              (rst_n),
      .start_i             (start),
      .img_w_i             (img_w),
      .img_h_i             (img_h),
      .relu_en_i           (relu_en),
      .pool_en_i           (pool_en),
      .requant_multiplier_i(rq_mult),
      .requant_shift_i     (rq_shift),
      .valid_i             (valid_in),
      .ready_o             (ready_out),
      .pixel_i             (pixel),
      .ready_i             (ready_in),
      .valid_o             (valid_out),
      .act_o               (act)
  );

  int errors = 0;
  int n_out  = 0;

  logic signed [OUT_W-1:0] exp_q [$];

  function automatic logic signed [OUT_W-1:0] exp_requant
      (input int px, input int mult, input int shift, input bit relu);
    longint p, sh;
    begin
      p = longint'(px) * longint'(mult);
      if (shift != 0) p = p + (64'sd1 <<< (shift - 1));
      sh = p >>> shift;
      if (relu && (sh < 0)) sh = 0;
      if (sh > 127)       return 8'sd127;
      else if (sh < -128) return -8'sd128;
      else                return 8'(sh);
    end
  endfunction

  int m_col, m_row, m_w, m_h, m_mult, m_shift;
  bit m_pool, m_relu;
  logic signed [OUT_W-1:0] m_hpair;
  logic signed [OUT_W-1:0] m_hbuf [0:IMG_W_MAX/2-1];

  function automatic void model_push(input int px);
    logic signed [OUT_W-1:0] q, hmax;
    begin
      q = exp_requant(px, m_mult, m_shift, m_relu);
      if (!m_pool) begin
        exp_q.push_back(q);
      end else begin
        if ((m_col % 2) == 0) begin
          m_hpair = q;
        end else begin
          hmax = (m_hpair > q) ? m_hpair : q;
          if ((m_row % 2) == 0) m_hbuf[m_col/2] = hmax;
          else exp_q.push_back((m_hbuf[m_col/2] > hmax) ? m_hbuf[m_col/2] : hmax);
        end
      end
      if (m_col == m_w - 1) begin
        m_col = 0;
        m_row = (m_row == m_h - 1) ? 0 : m_row + 1;
      end else begin
        m_col = m_col + 1;
      end
    end
  endfunction

  task automatic new_frame(input int w, input int h, input bit pool, input bit relu,
                           input int mult, input int shift);
    begin
      repeat (3) @(posedge clk); #1;
      img_w    = 6'(w);
      img_h    = 6'(h);
      pool_en  = pool;
      relu_en  = relu;
      rq_mult  = mult;
      rq_shift = 6'(shift);
      start    = 1'b1;
      @(posedge clk); #1;
      start    = 1'b0;
      m_col = 0; m_row = 0; m_w = w; m_h = h;
      m_pool = pool; m_relu = relu; m_mult = mult; m_shift = shift;
    end
  endtask

  task automatic send_pixel(input int px);
    begin
      model_push(px);
      valid_in = 1'b1;
      pixel    = px;
      @(posedge clk);
      while (ready_out !== 1'b1) @(posedge clk);
      #1;
      valid_in = 1'b0;
    end
  endtask

  always @(negedge clk) begin : mon
    logic signed [OUT_W-1:0] e;
    if (rst_n === 1'b1 && valid_out === 1'b1 && ready_in === 1'b1) begin
      if (exp_q.size() == 0) begin
        $error("unexpected output act_o=%0d", act);
        errors++;
      end else begin
        e = exp_q.pop_front();
        if (act !== e) begin
          $error("out[%0d]: act_o=%0d, expected %0d", n_out, act, e);
          errors++;
        end else begin
          $display("PASS out[%0d] = %0d", n_out, act);
        end
        n_out++;
      end
    end
  end

  initial begin
    #200_000_000;
    $error("TIMEOUT");
    $display("==== 1 CHECK(S) FEHLGESCHLAGEN ====");
    $finish;
  end

  initial begin
    rst_n = 1'b0; start = 1'b0; valid_in = 1'b0; ready_in = 1'b1;
    pixel = '0; img_w = 6'd4; img_h = 6'd4;
    relu_en = 1'b1; pool_en = 1'b0; rq_mult = 32'sd1; rq_shift = '0;
    repeat (4) @(posedge clk); #1;
    rst_n = 1'b1;

    $display("\n--- bypass, ReLU on: all-negative ---");
    new_frame(4, 4, 1'b0, 1'b1, 1, 0);
    send_pixel(-1); send_pixel(-5); send_pixel(-300); send_pixel(-128000);

    $display("\n--- bypass, ReLU on: mixed / saturation ---");
    new_frame(4, 4, 1'b0, 1'b1, 1, 0);
    send_pixel(0);    send_pixel(1);  send_pixel(127); send_pixel(128);
    send_pixel(1000); send_pixel(-7); send_pixel(126);

    $display("\n--- bypass, ReLU off ---");
    new_frame(4, 4, 1'b0, 1'b0, 1, 0);
    send_pixel(-5); send_pixel(-128);     send_pixel(-129); send_pixel(-300);
    send_pixel(42); send_pixel(-2000000); send_pixel(2000000);

    $display("\n--- requant 3/4, ReLU on ---");
    new_frame(4, 4, 1'b0, 1'b1, 3, 4);
    send_pixel(100);
    send_pixel(104);
    send_pixel(3);
    send_pixel(2);
    send_pixel(1000);
    send_pixel(-100);

    $display("\n--- requant 3/4, ReLU off ---");
    new_frame(4, 4, 1'b0, 1'b0, 3, 4);
    send_pixel(-3);
    send_pixel(-2);
    send_pixel(-100);

    $display("\n--- pool 4x4, ReLU on ---");
    new_frame(4, 4, 1'b1, 1'b1, 1, 0);
    send_pixel(1);  send_pixel(5);  send_pixel(-3); send_pixel(2);
    send_pixel(7);  send_pixel(2);  send_pixel(8);  send_pixel(-9);
    send_pixel(-1); send_pixel(-2); send_pixel(-5); send_pixel(-6);
    send_pixel(-4); send_pixel(-3); send_pixel(-7); send_pixel(-8);

    $display("\n--- pool 2x2, ReLU off ---");
    new_frame(2, 2, 1'b1, 1'b0, 1, 0);
    send_pixel(-9); send_pixel(-3); send_pixel(-7); send_pixel(-5);

    $display("\n--- pool 4x2 + requant 1/1, ReLU off ---");
    new_frame(4, 2, 1'b1, 1'b0, 1, 1);
    send_pixel(10); send_pixel(3); send_pixel(-8); send_pixel(-2);
    send_pixel(6);  send_pixel(1); send_pixel(-6); send_pixel(-4);

    $display("\n--- start_i restart ---");
    new_frame(4, 4, 1'b1, 1'b1, 1, 0);
    send_pixel(99); send_pixel(88); send_pixel(77);
    new_frame(4, 4, 1'b1, 1'b1, 1, 0);
    send_pixel(10); send_pixel(20); send_pixel(30); send_pixel(40);
    send_pixel(50); send_pixel(60); send_pixel(70); send_pixel(80);
    send_pixel(1);  send_pixel(2);  send_pixel(3);  send_pixel(4);
    send_pixel(5);  send_pixel(6);  send_pixel(7);  send_pixel(8);

    $display("\n--- backpressure ---");
    new_frame(4, 4, 1'b0, 1'b1, 1, 0);
    ready_in = 1'b0;
    send_pixel(42);
    repeat (4) @(posedge clk); #1;
    if (valid_out !== 1'b1 || act !== 8'sd42) begin
      $error("backpressure: valid_o=%b act_o=%0d, expected held 42", valid_out, act);
      errors++;
    end else $display("PASS backpressure: output held (act_o=%0d)", act);
    if (ready_out !== 1'b0) begin
      $error("backpressure: ready_o=%b, expected 0 while pending", ready_out);
      errors++;
    end else $display("PASS backpressure: ready_o blocks input");
    repeat (3) @(posedge clk); #1;
    if (valid_out !== 1'b1 || act !== 8'sd42) begin
      $error("backpressure: output not stable while stalled");
      errors++;
    end else $display("PASS backpressure: output stable");
    ready_in = 1'b1;
    @(posedge clk); #1;
    if (valid_out !== 1'b0) begin
      $error("backpressure: valid_o still set after handshake");
      errors++;
    end else $display("PASS backpressure: consumed on ready_i");

    repeat (10) @(posedge clk); #1;
    if (exp_q.size() != 0) begin
      $error("%0d expected output(s) never appeared", exp_q.size());
      errors++;
    end else $display("PASS all %0d expected outputs seen", n_out);

    if (errors == 0) $display("\n==== ALLE CHECKS BESTANDEN ====");
    else             $display("\n==== %0d CHECK(S) FEHLGESCHLAGEN ====", errors);
    $finish;
  end

endmodule
