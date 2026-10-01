module student_systolic_array_tb;

  localparam int N      = 8;
  localparam int ACT_W  = 8;
  localparam int W_W    = 8;
  localparam int PSUM_W = 32;
  localparam int K      = 2;      // Anzahl Kontraktions-Haeppchen

  logic clk, rst_n;
  logic start, mode, wload, avalid, ready, rvalid;
  logic [2:0] lbank, ubank;   // per-wavefront Bank-Index (NBANK=8 -> 3 Bit)
  logic [8:0] nsteps;

  logic signed [N-1:0][N-1:0][W_W-1:0]  wtile;
  logic signed [N-1:0][ACT_W-1:0]       arow;
  logic signed [N-1:0][PSUM_W-1:0]      result;

  // Referenzwerte (unpacked)
  logic signed [7:0]  Wm       [0:N-1][0:N-1];
  logic signed [7:0]  Am       [0:K-1][0:N-1];
  logic signed [31:0] expected [0:N-1];

  // 50 MHz
  always begin clk = 1'b1; #10000; clk = 1'b0; #10000; end

  student_systolic_array #(.N(N), .ACT_W(ACT_W), .W_W(W_W), .PSUM_W(PSUM_W)) dut (
      .clk_i(clk), .rst_ni(rst_n),
      .start_i(start), .mode_route_i(mode), .num_steps_i(nsteps),
      .weight_load_i(wload), .load_bank_i(lbank), .use_bank_i(ubank),
      .weight_tile_i(wtile),
      .act_valid_i(avalid), .ready_o(ready), .act_row_i(arow),
      .result_valid_o(rvalid), .result_o(result)
  );

  initial begin
    automatic int errors = 0;

    // Defaults
    rst_n  = 1'b0; start = 1'b0; mode = 1'b0; wload = 1'b0;
    lbank  = 1'b0; ubank = 1'b0; avalid = 1'b0; nsteps = K;
    arow   = '0;   wtile = '0;

    // Bekannte, kleine (vorzeichenbehaftete) Gewichte + Aktivierungen
    for (int r = 0; r < N; r++)
      for (int c = 0; c < N; c++)
        Wm[r][c] = (r + 2*c) % 5 - 2;          // -2..+2

    for (int s = 0; s < K; s++)
      for (int c = 0; c < N; c++)
        Am[s][c] = (s*3 + c) % 7 - 3;          // -3..+3

    // packen
    for (int r = 0; r < N; r++)
      for (int c = 0; c < N; c++)
        wtile[r][c] = Wm[r][c];

    // Erwartungswerte
    for (int r = 0; r < N; r++) begin
      expected[r] = '0;
      for (int s = 0; s < K; s++)
        for (int c = 0; c < N; c++)
          expected[r] = expected[r] + Am[s][c] * Wm[r][c];
    end

    // Reset (Eingaenge stets #1 NACH der Flanke treiben -> kein Delta-Race)
    repeat (4) @(posedge clk);
    @(posedge clk); #1; rst_n = 1'b1;

    // Gewichte in Bank 0 laden
    @(posedge clk); #1; lbank = 1'b0; ubank = 1'b0; wload = 1'b1;
    @(posedge clk); #1; wload = 1'b0;

    // Accumulate-Operation starten
    @(posedge clk); #1; mode = 1'b0; nsteps = K; start = 1'b1;
    @(posedge clk); #1; start = 1'b0;

    // K Aktivierungs-Vektoren einspeisen (Handshake, sauber getaktet)
    for (int s = 0; s < K; s++) begin
      for (int c = 0; c < N; c++) arow[c] = Am[s][c];
      avalid = 1'b1;
      do begin @(posedge clk); #1; end while (ready !== 1'b1);   // halten, bis akzeptiert
    end
    avalid = 1'b0;

    // Auf Ergebnis warten (nach der Flanke sampeln)
    do begin @(posedge clk); #1; end while (rvalid !== 1'b1);

    for (int r = 0; r < N; r++) begin
      if (result[r] !== expected[r]) begin
        $error("result[%0d] = %0d != erwartet %0d", r, result[r], expected[r]);
        errors++;
      end else begin
        $display("ok  result[%0d] = %0d", r, result[r]);
      end
    end

    if (errors == 0) $display("### ARRAY TB PASSED ###");
    else             $display("### ARRAY TB FAILED (%0d Fehler) ###", errors);

    $finish;
  end

endmodule
