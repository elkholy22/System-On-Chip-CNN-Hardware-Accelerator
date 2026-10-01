module student_controller_fsm_tb;

  localparam logic [2:0] ST_IDLE   = 3'd0;
  localparam logic [2:0] ST_CONV1  = 3'd1;
  localparam logic [2:0] ST_CONV2  = 3'd2;
  localparam logic [2:0] ST_FC1    = 3'd3;
  localparam logic [2:0] ST_FC2    = 3'd4;
  localparam logic [2:0] ST_ARGMAX = 3'd5;
  localparam logic [2:0] ST_DONE   = 3'd6;
  localparam logic [2:0] ST_ERROR  = 3'd7;

  logic clk, rst_n;
  logic start, clear, layer_done;
  logic busy, done, error;
  logic [2:0]  state;
  logic [2:0]  layer_sel;
  logic [1:0]  feeder_sel;
  logic [3:0]  in_ch;
  logic [7:0]  depth_steps;
  logic        use_pool, use_relu, argmax_en;
  logic        layer_start, clear_acc;
  logic [31:0] num_in;

  always begin clk = 1'b1; #10000; clk = 1'b0; #10000; end

  student_controller_fsm dut (
    .clk_i             (clk),
    .rst_ni            (rst_n),
    .start_i           (start),
    .clear_i           (clear),
    .layer_done_i      (layer_done),
    .busy_o            (busy),
    .done_o            (done),
    .error_o           (error),
    .state_o           (state),
    .layer_sel_o       (layer_sel),
    .feeder_sel_o      (feeder_sel),
    .in_ch_o           (in_ch),
    .depth_steps_o     (depth_steps),
    .use_pool_o        (use_pool),
    .use_relu_o        (use_relu),
    .argmax_en_o       (argmax_en),
    .layer_start_o     (layer_start),
    .clear_acc_o       (clear_acc),
    .relu_pool_num_in_o(num_in)
  );

  int errors = 0;

  logic       mon_en = 1'b0;
  int         n_start_pulses = 0;
  int         n_clear_pulses = 0;
  logic [2:0] order_buf [0:15];
  int         order_idx = 0;
  logic       prev_pulse = 1'b0;

  always @(negedge clk) begin
    if (mon_en) begin
      if (prev_pulse) begin
        if (order_idx < 16) order_buf[order_idx] = state;
        order_idx = order_idx + 1;
      end
      prev_pulse = layer_start;
      if (layer_start === 1'b1) n_start_pulses = n_start_pulses + 1;
      if (clear_acc   === 1'b1) n_clear_pulses = n_clear_pulses + 1;
      if (error !== 1'b0) begin
        $error("INVARIANT: error_o asserted (state=%0d)", state); errors++;
      end
      if (done === 1'b1 && state !== ST_DONE) begin
        $error("INVARIANT: done_o high outside S_DONE (state=%0d)", state); errors++;
      end
      if (busy === 1'b1 && done === 1'b1) begin
        $error("INVARIANT: busy_o and done_o high together"); errors++;
      end
      if (clear_acc === 1'b1 && layer_start !== 1'b1) begin
        $error("INVARIANT: clear_acc_o without layer_start_o"); errors++;
      end
    end else begin
      prev_pulse = 1'b0;
    end
  end

  task automatic mon_reset;
    n_start_pulses = 0;
    n_clear_pulses = 0;
    order_idx      = 0;
    prev_pulse     = 1'b0;
  endtask

  task automatic check_counts(input string name);
    int e0;
    e0 = errors;
    if (n_start_pulses != 5) begin
      $error("%s: %0d layer_start pulses, expected 5", name, n_start_pulses); errors++;
    end
    if (n_clear_pulses != 4) begin
      $error("%s: %0d clear_acc pulses, expected 4", name, n_clear_pulses); errors++;
    end
    if (order_idx != 5) begin
      $error("%s: %0d layer entries recorded, expected 5", name, order_idx); errors++;
    end else begin
      for (int i = 0; i < 5; i++) begin
        if (order_buf[i] !== 3'(i + 1)) begin
          $error("%s: entry %0d was state %0d, expected %0d", name, i, order_buf[i], i + 1); errors++;
        end
      end
    end
    if (errors == e0)
      $display("PASS %s: 5 starts in order CONV1->CONV2->FC1->FC2->ARGMAX, 4 acc clears", name);
  endtask

  task automatic run_layer(
      input string       name,
      input logic [2:0]  exp_state,
      input logic [2:0]  exp_sel,
      input logic [1:0]  exp_feed,
      input logic [3:0]  exp_in_ch,
      input logic [7:0]  exp_depth,
      input logic        exp_pool,
      input logic        exp_relu,
      input logic        exp_argmax,
      input logic [31:0] exp_num,
      input int          busy_cycles,
      input logic        nxt_start,
      input logic        nxt_clear);
    int e0;
    #1;
    e0 = errors;
    if (state !== exp_state) begin
      $error("%s: state=%0d, expected %0d", name, state, exp_state); errors++;
    end
    if (busy !== 1'b1 || done !== 1'b0 || error !== 1'b0) begin
      $error("%s: busy/done/error=%b/%b/%b, expected 1/0/0", name, busy, done, error); errors++;
    end
    if (layer_sel   !== exp_sel)    begin $error("%s: layer_sel=%0d exp %0d",   name, layer_sel,   exp_sel);    errors++; end
    if (feeder_sel  !== exp_feed)   begin $error("%s: feeder_sel=%0d exp %0d",  name, feeder_sel,  exp_feed);   errors++; end
    if (in_ch       !== exp_in_ch)  begin $error("%s: in_ch=%0d exp %0d",       name, in_ch,       exp_in_ch);  errors++; end
    if (depth_steps !== exp_depth)  begin $error("%s: depth_steps=%0d exp %0d", name, depth_steps, exp_depth);  errors++; end
    if (use_pool    !== exp_pool)   begin $error("%s: use_pool=%b exp %b",      name, use_pool,    exp_pool);   errors++; end
    if (use_relu    !== exp_relu)   begin $error("%s: use_relu=%b exp %b",      name, use_relu,    exp_relu);   errors++; end
    if (argmax_en   !== exp_argmax) begin $error("%s: argmax_en=%b exp %b",     name, argmax_en,   exp_argmax); errors++; end
    if (num_in      !== exp_num)    begin $error("%s: num_in=%0d exp %0d",      name, num_in,      exp_num);    errors++; end
    if (errors == e0) $display("PASS %s: status and layer config ok", name);

    repeat (busy_cycles) begin
      @(posedge clk); #2;
      if (layer_start !== 1'b0) begin $error("%s: spurious layer_start while busy", name); errors++; end
      if (state !== exp_state)  begin $error("%s: left state while computing", name); errors++; end
    end

    layer_done = 1'b1; #1;
    if (layer_start !== nxt_start) begin
      $error("%s: layer_start=%b in done cycle, expected %b", name, layer_start, nxt_start); errors++;
    end
    if (clear_acc !== nxt_clear) begin
      $error("%s: clear_acc=%b in done cycle, expected %b", name, clear_acc, nxt_clear); errors++;
    end
    @(posedge clk); #1;
    layer_done = 1'b0; #2;
    if (layer_start !== 1'b0) begin
      $error("%s: layer_start longer than one cycle", name); errors++;
    end
  endtask

  initial begin
    start = 1'b0; clear = 1'b0; layer_done = 1'b0;
    rst_n = 1'b0;
    repeat (4) @(posedge clk);
    #1; rst_n = 1'b1;
    @(posedge clk); #1;
    mon_en = 1'b1;

    if (state !== ST_IDLE || busy !== 1'b0 || done !== 1'b0 || error !== 1'b0) begin
      $error("reset: state=%0d busy=%b done=%b error=%b", state, busy, done, error); errors++;
    end else $display("PASS reset: S_IDLE, busy/done/error = 0/0/0");
    if (layer_start !== 1'b0 || clear_acc !== 1'b0) begin
      $error("reset: layer_start/clear_acc not idle"); errors++;
    end

    layer_done = 1'b1;
    @(posedge clk); #1; layer_done = 1'b0; #1;
    if (state !== ST_IDLE) begin
      $error("idle: layer_done_i changed state"); errors++;
    end else $display("PASS idle: layer_done_i ignored in S_IDLE");

    $display("--- inference #1: start held high ---");
    mon_reset;
    @(posedge clk); #1;
    start = 1'b1; #1;
    if (layer_start !== 1'b1 || clear_acc !== 1'b1) begin
      $error("start: missing layer_start/clear_acc pulse towards CONV1"); errors++;
    end else $display("PASS start: layer_start + clear_acc pulse for CONV1");
    @(posedge clk); #1;

    run_layer("CONV1",  ST_CONV1,  3'd0, 2'd0, 4'd1, 8'd2,  1'b1, 1'b1, 1'b0, 32'd1352, 3, 1'b1, 1'b1);
    run_layer("CONV2",  ST_CONV2,  3'd1, 2'd0, 4'd8, 8'd9,  1'b1, 1'b1, 1'b0, 32'd400,  4, 1'b1, 1'b1);
    run_layer("FC1",    ST_FC1,    3'd2, 2'd1, 4'd0, 8'd25, 1'b0, 1'b1, 1'b0, 32'd64,   2, 1'b1, 1'b1);
    run_layer("FC2",    ST_FC2,    3'd3, 2'd1, 4'd0, 8'd4,  1'b0, 1'b0, 1'b0, 32'd10,   5, 1'b1, 1'b0);
    run_layer("ARGMAX", ST_ARGMAX, 3'd4, 2'd1, 4'd0, 8'd0,  1'b0, 1'b0, 1'b1, 32'd0,    3, 1'b0, 1'b0);

    if (state !== ST_DONE || done !== 1'b1 || busy !== 1'b0) begin
      $error("done: state=%0d done=%b busy=%b, expected S_DONE/1/0", state, done, busy); errors++;
    end else $display("PASS done: S_DONE reached, done_o=1, busy_o=0");

    repeat (2) begin
      @(posedge clk); #2;
      if (state !== ST_DONE || done !== 1'b1) begin
        $error("done: S_DONE not held while start_i=1"); errors++;
      end
    end
    $display("PASS done: held while start_i stays high");

    start = 1'b0;
    @(posedge clk); #2;
    if (state !== ST_IDLE || busy !== 1'b0 || done !== 1'b0) begin
      $error("done: no return to S_IDLE after start release"); errors++;
    end else $display("PASS done: back to S_IDLE after start_i release");

    check_counts("inference #1");

    $display("--- clear_i abort test ---");
    mon_reset;
    @(posedge clk); #1; start = 1'b1;
    @(posedge clk); #1; start = 1'b0; #1;
    if (state !== ST_CONV1) begin
      $error("clear test: not in CONV1 after start pulse"); errors++;
    end
    repeat (2) @(posedge clk);
    #1; layer_done = 1'b1;
    @(posedge clk); #1; layer_done = 1'b0; #1;
    if (state !== ST_CONV2) begin
      $error("clear test: not in CONV2 after conv1 done"); errors++;
    end
    repeat (2) @(posedge clk);
    #1; clear = 1'b1; #1;
    if (busy !== 1'b1) begin
      $error("clear test: busy dropped before clock edge"); errors++;
    end
    if (layer_start !== 1'b0 || clear_acc !== 1'b0) begin
      $error("clear test: spurious pulse while clearing"); errors++;
    end
    @(posedge clk); #1; clear = 1'b0; #1;
    if (state !== ST_IDLE || busy !== 1'b0 || done !== 1'b0 || error !== 1'b0) begin
      $error("clear test: no clean return to S_IDLE"); errors++;
    end else $display("PASS clear: mid-inference abort returns to S_IDLE");
    if (n_start_pulses != 2 || n_clear_pulses != 2) begin
      $error("clear test: pulse counters %0d/%0d, expected 2/2", n_start_pulses, n_clear_pulses); errors++;
    end

    $display("--- inference #2: pulsed start after abort ---");
    mon_reset;
    @(posedge clk); #1; start = 1'b1; #1;
    if (layer_start !== 1'b1 || clear_acc !== 1'b1) begin
      $error("start #2: missing pulse towards CONV1"); errors++;
    end
    @(posedge clk); #1; start = 1'b0;

    run_layer("CONV1 #2",  ST_CONV1,  3'd0, 2'd0, 4'd1, 8'd2,  1'b1, 1'b1, 1'b0, 32'd1352, 2, 1'b1, 1'b1);
    run_layer("CONV2 #2",  ST_CONV2,  3'd1, 2'd0, 4'd8, 8'd9,  1'b1, 1'b1, 1'b0, 32'd400,  1, 1'b1, 1'b1);
    run_layer("FC1 #2",    ST_FC1,    3'd2, 2'd1, 4'd0, 8'd25, 1'b0, 1'b1, 1'b0, 32'd64,   3, 1'b1, 1'b1);
    run_layer("FC2 #2",    ST_FC2,    3'd3, 2'd1, 4'd0, 8'd4,  1'b0, 1'b0, 1'b0, 32'd10,   1, 1'b1, 1'b0);
    run_layer("ARGMAX #2", ST_ARGMAX, 3'd4, 2'd1, 4'd0, 8'd0,  1'b0, 1'b0, 1'b1, 32'd0,    2, 1'b0, 1'b0);

    if (state !== ST_DONE || done !== 1'b1) begin
      $error("done #2: S_DONE missed"); errors++;
    end else $display("PASS done #2: S_DONE, done_o=1");
    @(posedge clk); #2;
    if (state !== ST_IDLE || done !== 1'b0 || busy !== 1'b0) begin
      $error("done #2: no auto return to S_IDLE with start_i low"); errors++;
    end else $display("PASS done #2: auto return to S_IDLE (start_i low)");

    check_counts("inference #2");

    $display("NOTE: S_ERROR unreachable from ports; error_o==0 monitored throughout");

    if (errors == 0) $display("\n==== ALLE CHECKS BESTANDEN ====");
    else             $display("\n==== %0d CHECK(S) FEHLGESCHLAGEN ====", errors);
    $finish;
  end

  initial begin
    #20000000;
    $error("TIMEOUT: testbench hung");
    $finish;
  end

endmodule
