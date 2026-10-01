`timescale 1ns/1ps
module student_ws_conv2_tb;

  localparam int N      = 16;
  localparam int ACT_W  = 8;
  localparam int W_W    = 8;
  localparam int PSUM_W = 32;
  localparam int INJ_LEAD = 1;      // <-- Alignment-Knopf (siehe Kopf)

  `include "ws_gold.svh"            // GN, GNTILE, GP, gold_w/a/y, load_golden()

  logic clk, rst_n;
  always begin clk = 1'b1; #5; clk = 1'b0; #5; end   // 100 MHz TB-Takt

  // --- Array-I/O ---
  logic                              a_start, a_mode, a_wload, a_avalid;
  logic [2:0]                        a_lbank, a_ubank;     // NBANK=8 -> 3b (Bank 0)
  logic [8:0]                        a_nsteps;
  logic signed [N-1:0][N-1:0][W_W-1:0]  a_wtile;
  logic signed [N-1:0][ACT_W-1:0]       a_arow;
  logic                              a_ready, a_rvalid;
  logic signed [N-1:0][PSUM_W-1:0]      a_result, a_rpsum;

  student_systolic_array #(.N(N), .ACT_W(ACT_W), .W_W(W_W), .PSUM_W(PSUM_W)) u_arr (
      .clk_i(clk), .rst_ni(rst_n),
      .start_i(a_start), .mode_route_i(a_mode), .num_steps_i(a_nsteps),
      .weight_load_i(a_wload), .load_bank_i(a_lbank), .use_bank_i(a_ubank),
      .weight_tile_i(a_wtile),
      .act_valid_i(a_avalid), .ready_o(a_ready), .act_row_i(a_arow),
      .result_valid_o(a_rvalid), .result_o(a_result),
      .right_psum_o(a_rpsum)
  );

  // --- Akkumulator ---
  logic                       ac_tstart, ac_first;
  logic [$clog2(GP)-1:0]      ac_npos, ac_rdpos;
  logic signed [N-1:0][PSUM_W-1:0] ac_acc;

  student_ws_accum #(.N(N), .PSUM_W(PSUM_W), .NPOS(GP)) u_acc (
      .clk_i(clk), .rst_ni(rst_n),
      .tile_start_i(ac_tstart), .first_tile_i(ac_first), .npos_i(ac_npos),
      .spacing_i(GSPACING[1:0]),
      .right_psum_i(a_rpsum),
      .rd_pos_i(ac_rdpos), .acc_o(ac_acc)
  );

  integer errors = 0;

  // Ein Tap-Tile fahren: Gewicht laden, Pipe leeren + tile_start, P Positionen
  // stroemen (spacing 1), dann Drain abwarten.
  task automatic run_tile(input int t, input bit first);
    // 1) Gewichts-Tile in Bank 0 laden
    @(posedge clk); #1;
    for (int r = 0; r < N; r++)
      for (int c = 0; c < N; c++)
        a_wtile[r][c] = gold_w[t][r][c];
    a_wload = 1'b1; a_lbank = 3'd0; a_ubank = 3'd0;
    @(posedge clk); #1; a_wload = 1'b0;

    // 2) Pipe leeren (start) + Akkumulator-Stream starten (tile_start) im selben Takt S
    a_mode    = 1'b1;            // route mode
    a_start   = 1'b1;
    ac_tstart = 1'b1; ac_first = first; ac_npos = GP[$clog2(GP)-1:0];
    for (int c = 0; c < N; c++) a_arow[c] = '0;
    a_avalid  = 1'b0;
    @(posedge clk); #1;
    a_start   = 1'b0;
    ac_tstart = 1'b0;

    // INJ_LEAD-1 Leer-Takte (INJ_LEAD=1 -> keine), dann P Positionen mit Kadenz
    // GSPACING: Position p bei S+INJ_LEAD+p*GSPACING; die (GSPACING-1) Luecken-
    // takte praesentieren act_row=0 (single-port act_buffer liefert 2 Woerter/Pos).
    for (int k = 0; k < INJ_LEAD - 1; k++) begin @(posedge clk); #1; end

    for (int p = 0; p < GP; p++) begin
      for (int c = 0; c < N; c++) a_arow[c] = gold_a[t][p][c];
      a_avalid = 1'b1;
      @(posedge clk); #1;
      for (int g = 1; g < GSPACING; g++) begin      // Luecken-Takte (kein neuer Vektor)
        for (int c = 0; c < N; c++) a_arow[c] = '0;
        a_avalid = 1'b0;
        @(posedge clk); #1;
      end
    end
    a_avalid = 1'b0;
    for (int c = 0; c < N; c++) a_arow[c] = '0;

    // 3) Drain: letzte Position verlaesst nach ~2N, Erfassung laeuft bis tcnt=npos+2N+1
    repeat (2*N + 4) begin @(posedge clk); #1; end
  endtask

  initial begin
    load_golden();
    a_start=0; a_mode=1; a_wload=0; a_avalid=0; a_lbank=0; a_ubank=0; a_nsteps=0;
    ac_tstart=0; ac_first=0; ac_npos=0; ac_rdpos=0;
    for (int r=0;r<N;r++) begin a_arow[r]='0; for (int c=0;c<N;c++) a_wtile[r][c]='0; end
    rst_n = 1'b0;
    repeat (4) @(posedge clk);
    @(posedge clk); #1; rst_n = 1'b1;

    // 5 Tap-Tiles: Tile 0 ueberschreibt, Rest addiert
    for (int t = 0; t < GNTILE; t++)
      run_tile(t, (t == 0));

    // --- Readout + Vergleich ---
    for (int p = 0; p < GP; p++) begin
      ac_rdpos = p[$clog2(GP)-1:0];
      @(posedge clk); @(posedge clk); #1;     // 1 Takt Read-Latenz + Rand
      for (int r = 0; r < N; r++) begin
        if (ac_acc[r] !== gold_y[p][r]) begin
          $error("pos %0d ch %0d: acc=%0d != erwartet %0d",
                 p, r, ac_acc[r], gold_y[p][r]);
          errors = errors + 1;
        end
      end
    end

    if (errors == 0) $display("### WS-CONV2 CORE TB PASSED (%0d Positionen x %0d Kanaele) ###", GP, N);
    else             $display("### WS-CONV2 CORE TB FAILED (%0d Fehler) -- ggf. INJ_LEAD justieren ###", errors);
    $finish;
  end

  initial begin
    #200000;
    $error("TIMEOUT");
    $finish;
  end

endmodule
