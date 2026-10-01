`ifndef STRINGIFY
  `define STRINGIFY(x) `"x`"
`endif

module conv1_verif_tb;

  localparam int N      = 8;
  localparam int ACT_W  = 8;
  localparam int W_W    = 8;
  localparam int PSUM_W = 32;
  localparam int K      = 2;      // conv1: 9 Taps = 8+1 -> 2 Schritte

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
  logic [7:0]  patch_mem [0:8];
  logic [31:0] exp_mem   [0:7];
  initial $readmemh(`STRINGIFY(`CONV1_PATCH_FILE), patch_mem);
  initial $readmemh(`STRINGIFY(`CONV1_EXP_FILE),   exp_mem);

  // 50 MHz
  always begin clk = 1'b1; #10000; clk = 1'b0; #10000; end

  // ---- Aktivierungs-Split (wie student_cnn.avec) ----
  always_comb begin
    avec = '0;
    if (astep == 9'd0) begin
      for (int c = 0; c < N; c++) avec[c] = $signed(patch_mem[c]);  // Taps 0..7
    end else begin
      avec[0] = $signed(patch_mem[8]);                              // Tap 8
    end
  end

  // ---- ECHTES weight_bram (laedt gekachelte weights.mem) ----
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
    #5_000_000;
    $error("TIMEOUT: op_rvalid kam nie.");
    $finish;
  end

  initial begin
    automatic int errors = 0;
    op_start = 1'b0; op_nsteps = K; op_wbase = 12'd0;   // conv1 -> Kacheln 0,1
    rst_n = 1'b0;

    repeat (6) @(posedge clk);
    @(posedge clk); #1; rst_n = 1'b1;

    // Eine conv1-Op anstossen (op_wbase=0, 2 Schritte)
    @(posedge clk); #1; op_wbase = 12'd0; op_nsteps = K; op_start = 1'b1;
    @(posedge clk); #1; op_start = 1'b0;

    do begin @(posedge clk); #1; end while (op_rvalid !== 1'b1);

    for (int r = 0; r < N; r++) begin
      if (op_result[r] !== $signed(exp_mem[r])) begin
        $error("op_result[%0d] = %0d  !=  erwartet %0d",
               r, op_result[r], $signed(exp_mem[r]));
        errors++;
      end else begin
        $display("ok  conv1 filter %0d : MAC = %0d", r, $signed(exp_mem[r]));
      end
    end

    if (errors == 0) $display("### CONV1 VERIF PASSED ###");
    else             $display("### CONV1 VERIF FAILED (%0d Fehler) ###", errors);
    $finish;
  end

endmodule
