module student_feed_array_tb;

  localparam int N      = 8;
  localparam int ACT_W  = 8;
  localparam int W_W    = 8;
  localparam int PSUM_W = 32;
  localparam int K      = 2;   // Kontraktions-Schritte (conv1: 9 Taps = 8+1 -> 2)

  logic clk, rst_n;

  // ---- Feeder-Kommando (Sequencer-Seite) ----
  logic                       op_start;
  logic [8:0]                 op_nsteps;
  logic [11:0]                op_wbase;
  logic                       op_busy, op_rvalid;
  logic signed [N-1:0][PSUM_W-1:0] op_result;

  // ---- Gewichtsquelle (weight_bram-Modell) ----
  logic [11:0]                       wtile_addr;
  logic signed [N-1:0][N-1:0][W_W-1:0] wtile;

  // ---- Aktivierungsquelle (avec-Modell) ----
  logic [8:0]                 astep;
  logic                       av_req;
  logic signed [N-1:0][ACT_W-1:0] avec;

  // ---- Feeder <-> Array ----
  logic                       a_start, a_mode, a_wload;
  logic [2:0]                 a_lbank, a_ubank;   // per-wavefront Bank (NBANK=8 -> 3 Bit)
  logic [8:0]                 a_nsteps;
  logic                       a_avalid, a_ready, a_rvalid;
  logic signed [N-1:0][N-1:0][W_W-1:0] a_wtile;
  logic signed [N-1:0][ACT_W-1:0]      a_arow;
  logic signed [N-1:0][PSUM_W-1:0]     a_result;

  // ---- Referenz (unpacked) ----
  logic signed [7:0]  Wt [0:K-1][0:N-1][0:N-1];
  logic signed [7:0]  Av [0:K-1][0:N-1];
  logic signed [31:0] expected [0:N-1];

  // gepackte Gewichts-Kacheln, indiziert wie im weight_bram
  logic signed [N-1:0][N-1:0][W_W-1:0] Wtiles [0:K-1];

  // 50 MHz
  always begin clk = 1'b1; #10000; clk = 1'b0; #10000; end

  // ---- Gewichtsmodell: 1-Takt registrierter Read (wie student_weight_bram) ----
  always_ff @(posedge clk) begin
    wtile <= (wtile_addr < K) ? Wtiles[wtile_addr] : '0;
  end

  // ---- Aktivierungsmodell: kombinatorisch aus astep (wie student_cnn.avec) ----
  always_comb begin
    avec = '0;
    if (astep < K)
      for (int c = 0; c < N; c++) avec[c] = Av[astep][c];
  end

  // ---- DUTs ----
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

  // ---- Watchdog ----
  initial begin
    #5_000_000;   // 5 us -> viel mehr als eine Op braucht
    $error("TIMEOUT: op_rvalid kam nie (Feeder/Array haengt).");
    $finish;
  end

  // ---- Ablauf ----
  initial begin
    automatic int errors = 0;

    op_start = 1'b0; op_nsteps = K; op_wbase = 12'd0;
    rst_n = 1'b0;

    // Bekannte, PRO SCHRITT UNTERSCHIEDLICHE Werte (so faellt ein Step-Mixup auf).
    // WICHTIG: +3*s (nicht +5*s) -> variiert wirklich mod 5, sonst waeren die
    // Gewichte fuer beide Schritte identisch und der Gewichts-Nachlade-Pfad
    // wuerde gar nicht getestet.
    for (int s = 0; s < K; s++) begin
      for (int r = 0; r < N; r++)
        for (int c = 0; c < N; c++)
          Wt[s][r][c] = ((r + 2*c + 3*s) % 5) - 2;   // -2..+2, variiert mit s
      for (int c = 0; c < N; c++)
        Av[s][c] = ((3*s + c) % 7) - 3;              // -3..+3, variiert mit s
    end

    // Referenz-Kacheln packen
    for (int s = 0; s < K; s++)
      for (int r = 0; r < N; r++)
        for (int c = 0; c < N; c++)
          Wtiles[s][r][c] = Wt[s][r][c];

    // Sollwerte
    for (int r = 0; r < N; r++) begin
      expected[r] = '0;
      for (int s = 0; s < K; s++)
        for (int c = 0; c < N; c++)
          expected[r] = expected[r] + Av[s][c] * Wt[s][r][c];
    end

    // Reset loesen (Eingaenge #1 nach der Flanke treiben)
    repeat (4) @(posedge clk);
    @(posedge clk); #1; rst_n = 1'b1;

    // EINE Accumulate-Op anstossen: der Feeder macht den Rest selbst
    @(posedge clk); #1; op_wbase = 12'd0; op_nsteps = K; op_start = 1'b1;
    @(posedge clk); #1; op_start = 1'b0;

    // Auf Ergebnis warten
    do begin @(posedge clk); #1; end while (op_rvalid !== 1'b1);

    for (int r = 0; r < N; r++) begin
      if (op_result[r] !== expected[r]) begin
        $error("op_result[%0d] = %0d  !=  erwartet %0d", r, op_result[r], expected[r]);
        errors++;
      end else begin
        $display("ok  op_result[%0d] = %0d", r, op_result[r]);
      end
    end

    if (errors == 0) $display("### FEED+ARRAY TB PASSED ###");
    else             $display("### FEED+ARRAY TB FAILED (%0d Fehler) ###", errors);

    $finish;
  end

endmodule
