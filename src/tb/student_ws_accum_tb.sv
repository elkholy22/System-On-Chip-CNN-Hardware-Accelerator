module student_ws_accum_tb;

  localparam int N      = 16;
  localparam int PSUM_W = 32;
  localparam int NPOS   = 121;
  localparam int PAW    = 7;
  localparam int MAXNP  = 8;

  logic clk, rst_n;
  logic tile_start, first_tile;
  logic [PAW-1:0]                  npos_in;
  logic [1:0]                      spacing_in;
  logic signed [N-1:0][PSUM_W-1:0] right_psum;
  logic [PAW-1:0]                  rd_pos;
  logic signed [N-1:0][PSUM_W-1:0] acc;

  int errors = 0;

  always begin clk = 1'b1; #10000; clk = 1'b0; #10000; end

  student_ws_accum #(
      .N(N), .PSUM_W(PSUM_W), .NPOS(NPOS)
  ) dut (
      .clk_i        (clk),
      .rst_ni       (rst_n),
      .tile_start_i (tile_start),
      .first_tile_i (first_tile),
      .npos_i       (npos_in),
      .spacing_i    (spacing_in),
      .right_psum_i (right_psum),
      .rd_pos_i     (rd_pos),
      .acc_o        (acc)
  );

  int ref_acc [0:N-1][0:MAXNP-1];

  function automatic int psum_val(input int pass_id, input int r, input int p);
    int v;
    v = (pass_id * 100000) + (r * 977) + (p * 131) + 7;
    if (((r + p + pass_id) % 3) == 0) v = -v - 12345;
    return v;
  endfunction

  task automatic run_pass(input int pass_id, input bit first,
                          input int np, input int s);
    int praw;
    for (int r = 0; r < N; r++)
      for (int p = 0; p < np; p++) begin
        if (first) ref_acc[r][p] = psum_val(pass_id, r, p);
        else       ref_acc[r][p] = ref_acc[r][p] + psum_val(pass_id, r, p);
      end

    tile_start = 1'b1; first_tile = first;
    npos_in    = PAW'(np); spacing_in = 2'(s);
    @(posedge clk); #1;
    tile_start = 1'b0;

    for (int k = 0; k <= np*s + 2*N + 6; k++) begin
      for (int r = 0; r < N; r++) begin
        praw = k - (N + r + 1);
        if ((praw >= 0) && ((s == 1) || (praw % 2 == 0)) && ((praw / s) < np))
          right_psum[r] = psum_val(pass_id, r, praw / s);
        else
          right_psum[r] = 32'hDEAD_BEEF;
      end
      @(posedge clk); #1;
    end

    for (int r = 0; r < N; r++) right_psum[r] = 32'hDEAD_BEEF;
    repeat (3) begin @(posedge clk); #1; end
  endtask

  task automatic check_totals(input int np, input string tag);
    int mism;
    for (int p = 0; p < np; p++) begin
      rd_pos = PAW'(p);
      @(posedge clk); #1;
      mism = 0;
      for (int r = 0; r < N; r++) begin
        if (acc[r] !== ref_acc[r][p]) begin
          $error("FAIL %s pos %0d row %0d: acc=%0d erwartet %0d",
                 tag, p, r, $signed(acc[r]), ref_acc[r][p]);
          errors++; mism++;
        end
      end
      if (mism == 0)
        $display("PASS %s pos %0d: alle %0d Zeilen ok (row0=%0d)",
                 tag, p, N, $signed(acc[0]));
    end
  endtask

  initial begin
    rst_n = 1'b0; tile_start = 1'b0; first_tile = 1'b0;
    npos_in = '0; spacing_in = 2'd1; rd_pos = '0;
    for (int r = 0; r < N; r++) right_psum[r] = 32'hDEAD_BEEF;
    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk); #1;

    run_pass(0, 1'b1, 6, 1);  check_totals(6, "A0 first s1");
    run_pass(1, 1'b0, 6, 1);  check_totals(6, "A1 accum s1");
    run_pass(2, 1'b0, 6, 1);  check_totals(6, "A2 accum s1");

    run_pass(3, 1'b1, 4, 2);  check_totals(6, "B0 first s2");
    run_pass(4, 1'b0, 4, 2);  check_totals(6, "B1 accum s2");

    if (errors == 0) $display("\n==== ALLE CHECKS BESTANDEN ====");
    else             $display("\n==== %0d CHECK(S) FEHLGESCHLAGEN ====", errors);
    $finish;
  end

endmodule
