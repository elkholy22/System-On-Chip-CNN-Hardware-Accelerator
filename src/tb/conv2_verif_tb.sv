`ifndef STRINGIFY
  `define STRINGIFY(x) `"x`"
`endif

module conv2_verif_tb;

  localparam int N      = 8;
  localparam int ACT_W  = 8;
  localparam int W_W    = 8;
  localparam int PSUM_W = 32;
  localparam int K      = 9;      // conv2: 8 Kanaele x 9 Taps -> 9 Schritte

  logic clk, rst_n;

  logic                       op_start;
  logic [8:0]                 op_nsteps;
  logic [11:0]                op_wbase;
  logic                       op_busy, op_rvalid;
  logic signed [N-1:0][PSUM_W-1:0] op_result;

  logic [11:0]                       wtile_addr;
  logic signed [N-1:0][N-1:0][W_W-1:0] wtile;

  logic [8:0]                 astep;
  logic                       av_req;
  logic signed [N-1:0][ACT_W-1:0] avec;

  logic                       a_start, a_mode, a_wload;
  logic [2:0]                 a_lbank, a_ubank;   // per-wavefront Bank (NBANK=8 -> 3 Bit)
  logic [8:0]                 a_nsteps;
  logic                       a_avalid, a_ready, a_rvalid;
  logic signed [N-1:0][N-1:0][W_W-1:0] a_wtile;
  logic signed [N-1:0][ACT_W-1:0]      a_arow;
  logic signed [N-1:0][PSUM_W-1:0]     a_result;

  // ---- Referenz aus Dateien ----
  logic [7:0]  win_mem [0:71];   // 9 Taps x 8 Kanaele
  logic [31:0] exp_mem [0:7];
  initial $readmemh(`STRINGIFY(`CONV2_WINDOW_FILE), win_mem);
  initial $readmemh(`STRINGIFY(`CONV2_EXP_FILE),    exp_mem);

  always begin clk = 1'b1; #10000; clk = 1'b0; #10000; end

  // ---- avec pro Schritt = 8 Kanaele des Fenster-Worts astep ----
  always_comb begin
    avec = '0;
    if (astep < K)
      for (int c = 0; c < N; c++) avec[c] = $signed(win_mem[astep*8 + c]);
  end

  student_weight_bram #(.N(N)) u_wgt (
      .clk_i(clk), .rst_ni(rst_n),
      .we_i(1'b0), .waddr_i('0), .wdata_i('0),
      .tile_addr_i(wtile_addr), .wtile_o(wtile)
  );

  student_systolic_array_feeder #(.N(N)) u_feed (
      .clk_i(clk), .rst_ni(rst_n),
      .op_start_i(op_start), .op_nsteps_i(op_nsteps), .op_wbase_i(op_wbase),
      .op_busy_o(op_busy), .op_rvalid_o(op_rvalid), .op_result_o(op_result),
      .wtile_addr_o(wtile_addr), .wtile_i(wtile),
      .astep_o(astep), .av_req_o(av_req), .avec_i(avec),
      .a_start_o(a_start), .a_mode_o(a_mode), .a_nsteps_o(a_nsteps),
      .a_wload_o(a_wload), .a_lbank_o(a_lbank), .a_ubank_o(a_ubank),
      .a_wtile_o(a_wtile), .a_avalid_o(a_avalid), .a_ready_i(a_ready),
      .a_arow_o(a_arow), .a_rvalid_i(a_rvalid), .a_result_i(a_result)
  );

  student_systolic_array #(.N(N)) u_array (
      .clk_i(clk), .rst_ni(rst_n),
      .start_i(a_start), .mode_route_i(a_mode), .num_steps_i(a_nsteps),
      .weight_load_i(a_wload), .load_bank_i(a_lbank), .use_bank_i(a_ubank),
      .weight_tile_i(a_wtile),
      .act_valid_i(a_avalid), .ready_o(a_ready), .act_row_i(a_arow),
      .result_valid_o(a_rvalid), .result_o(a_result)
  );

  initial begin
    #8_000_000;
    $error("TIMEOUT: op_rvalid kam nie.");
    $finish;
  end

  initial begin
    automatic int errors = 0;
    op_start = 1'b0; op_nsteps = K; op_wbase = 12'd2;   // conv2 Gruppe 0 -> Kacheln 2..10
    rst_n = 1'b0;

    repeat (6) @(posedge clk);
    @(posedge clk); #1; rst_n = 1'b1;

    @(posedge clk); #1; op_wbase = 12'd2; op_nsteps = K; op_start = 1'b1;
    @(posedge clk); #1; op_start = 1'b0;

    do begin @(posedge clk); #1; end while (op_rvalid !== 1'b1);

    for (int f = 0; f < N; f++) begin
      if (op_result[f] !== $signed(exp_mem[f])) begin
        $error("op_result[%0d] = %0d  !=  erwartet %0d",
               f, op_result[f], $signed(exp_mem[f]));
        errors++;
      end else begin
        $display("ok  conv2 filter %0d : MAC = %0d", f, $signed(exp_mem[f]));
      end
    end

    if (errors == 0) $display("### CONV2 VERIF PASSED ###");
    else             $display("### CONV2 VERIF FAILED (%0d Fehler) ###", errors);
    $finish;
  end

endmodule
