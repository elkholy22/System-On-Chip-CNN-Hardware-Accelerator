module student_systolic_array #(
    parameter  int unsigned N      = 8,
    parameter  int unsigned ACT_W  = 8,
    parameter  int unsigned W_W    = 8,
    parameter  int unsigned PSUM_W = 32,
    parameter  int unsigned NBANK  = 8,               // Gewichts-Banks (per-wavefront)
    localparam int unsigned BW     = $clog2(NBANK)    // Bank-Tag-Breite (NBANK=8 -> 3)
) (
    input  logic clk_i,
    input  logic rst_ni,

    // Control
    input  logic                   start_i,      // begin fresh result (clears accumulators / pipe)
    input  logic                   mode_route_i, // 0 = accumulate (depth), 1 = route (stream positions)
    input  logic [$clog2(512)-1:0] num_steps_i,  // accumulate mode: depth steps to sum

    // Weight load (NBANK-fach gepuffert). weight_tile_i loaded in parallel into
    // bank load_bank_i when weight_load_i is high. use_bank_i ist der Bank-Tag des
    // aktuell gespeisten Tiles; er reist mit der Aktivierung durch Skew+Grid
    // (per-wavefront), sodass jedes PE weight_q[<mitgereister Tag>] multipliziert.
    input  logic                                weight_load_i,
    input  logic [BW-1:0]                        load_bank_i,
    input  logic [BW-1:0]                        use_bank_i,
    input  logic signed [N-1:0][N-1:0][W_W-1:0] weight_tile_i,

    // Activation input: N activations (one per COLUMN), natural order.
    // Handshake: a tile transfers only when act_valid_i && ready_o are both
    // high on the same cycle. ready_o is held LOW while the array cannot
    // accept the next tile (accumulate mode: until MIN_SPACING cycles have
    // elapsed since the last accept). The feeder must hold its chunk and not
    // advance while ready_o is low.
    input  logic                           act_valid_i,
    output logic                           ready_o,
    input  logic signed [N-1:0][ACT_W-1:0] act_row_i,

    // Result. In accumulate mode: one pulse, result_o = final acc_q.
    //         In route mode: result_o = the just-finished tile's row
    //         results, result_valid_o pulses per finished tile.
    output logic                            result_valid_o,
    output logic signed [N-1:0][PSUM_W-1:0] result_o,

    // ROHER rechter Array-Rand (registriertes psum_h[r][N-1]) fuer die
    // WEIGHT-STATIONARY-Erfassung: student_ws_accum sammelt diese Anti-Diagonale
    // im route mode je Takt ein (bypass des Einzel-Latch route_q).
    output logic signed [N-1:0][PSUM_W-1:0] right_psum_o
);

    // --------------------------------------------------------
    // 1) INPUT SKEW  (identical to baseline)
    // --------------------------------------------------------
    logic signed [N-1:0][ACT_W-1:0]        act_skewed;
    logic signed [N-1:0][N-1:0][ACT_W-1:0] act_delay;   // [col][stage]
    // Bank-Skew PARALLEL zum Act-Skew: die Bank des aktuellen Tiles begleitet die
    // Aktivierung durch die Skew-Kette (per-wavefront banking) -> bis NBANK Tiles
    // in-flight. Bank-Tag ist BW Bit breit.
    logic [N-1:0][BW-1:0]        bank_skewed;
    logic [N-1:0][N-1:0][BW-1:0] bank_delay;

    genvar c;
    generate
        for (c = 0; c < N; c++) begin : gen_skew_col
            always_ff @(posedge clk_i, negedge rst_ni) begin
                if (~rst_ni) begin
                    act_delay[c]  <= '{default: '0};
                    bank_delay[c] <= '0;
                end else if (start_i) begin
                    act_delay[c]  <= '{default: '0};   // Skew pro Op leeren
                    bank_delay[c] <= '0;
                end else begin
                    act_delay[c][0]  <= act_row_i[c];
                    bank_delay[c][0] <= use_bank_i;    // Bank des aktuell gespeisten Tiles
                    for (int st = 1; st < N; st++) begin
                        act_delay[c][st]  <= act_delay[c][st-1];
                        bank_delay[c][st] <= bank_delay[c][st-1];
                    end
                end
            end
            assign act_skewed[c]  = act_delay[c][c];
            assign bank_skewed[c] = bank_delay[c][c];
        end
    endgenerate

    // --------------------------------------------------------
    // 2) LEFT EDGE = 0  (stateless grid; accumulation external)
    // --------------------------------------------------------
    logic signed [N-1:0][PSUM_W-1:0] left_psum;
    assign left_psum = '0;

    // per-wavefront banking: kein globales use_bank_q. Die Bank
    // des jeweiligen Tiles reist als bank_skewed/bank_v mit der Aktivierung durch
    // Skew + Grid. Dadurch koennen zwei Tiles (Bank 0 und 1) gleichzeitig in-flight
    // sein -> spacing N statt 2N-1, waehrend jeder MAC die korrekte Bank sieht.

    // --------------------------------------------------------
    // 3) PE GRID  (now double-buffered PEs)
    // --------------------------------------------------------
    logic signed [N-1:0][N-1:0][ACT_W-1:0]  act_v;
    logic signed [N-1:0][N-1:0][PSUM_W-1:0] psum_h;
    logic        [N-1:0][N-1:0][BW-1:0]     bank_v;    // Bank haengt mit act nach unten

    genvar gr, gc;
    generate
        for (gr = 0; gr < N; gr++) begin : gen_row
            for (gc = 0; gc < N; gc++) begin : gen_col
                logic signed [ACT_W-1:0] act_in;
                assign act_in = (gr == 0) ? act_skewed[gc] : act_v[gr-1][gc];

                logic [BW-1:0] bank_in;
                assign bank_in = (gr == 0) ? bank_skewed[gc] : bank_v[gr-1][gc];

                logic signed [PSUM_W-1:0] psum_in;
                assign psum_in = (gc == 0) ? left_psum[gr] : psum_h[gr][gc-1];

                student_pe_db #(
                    .ACT_W (ACT_W),
                    .W_W   (W_W),
                    .PSUM_W(PSUM_W),
                    .NBANK (NBANK)
                ) pe_i (
                    .clk_i,
                    .rst_ni,
                    .load_weight_i(weight_load_i),
                    .load_bank_i  (load_bank_i),
                    .weight_i     (weight_tile_i[gr][gc]),
                    .bank_i       (bank_in),           // Bank folgt der Wellenfront
                    .bank_o       (bank_v[gr][gc]),
                    .clear_i      (start_i),
                    .act_i        (act_in),
                    .psum_i       (psum_in),
                    .act_o        (act_v[gr][gc]),
                    .psum_o       (psum_h[gr][gc])
                );
            end
        end
    endgenerate

    logic signed [N-1:0][PSUM_W-1:0] right_psum;
    genvar br;
    generate
        for (br = 0; br < N; br++) begin : gen_right
            assign right_psum[br] = psum_h[br][N-1];
        end
    endgenerate
    assign right_psum_o = right_psum;   // roher Rand fuer WS-Erfassung

    // --------------------------------------------------------
    // 4) CONTROL
    //    Shared pipe tracks each tile's wavefront; row r is ready at
    //    bit GRID_LAT + r (= N + r), exactly as the baseline.
    //
    //    ACCUMULATE mode: sum right_psum[r] into acc_q[r] each time a
    //      pipe bit fires; one tile in flight at a time (caller spaces
    //      tiles >= 2N-1). Emit once after num_steps_i steps.
    //
    //    ROUTE mode: each fired tile is a complete, independent result.
    //      We do NOT accumulate; we latch right_psum into result_o and
    //      pulse result_valid_o when the LAST row of that tile is ready.
    //      Multiple tiles may be in flight (back-to-back), all sharing
    //      the active weight bank.
    // --------------------------------------------------------
    localparam int unsigned GRID_LAT = N;
    localparam int unsigned PIPE_D   = 2*N;

    logic [$clog2(512)-1:0] acc_cnt;
    logic                   running;
    logic [PIPE_D:0]        tile_pipe;

    // Spacing tracker for accumulate-mode backpressure: counts cycles since
    // the last accepted tile.
    // per-wavefront banking, NBANK Banks: MIN_SPACING ist die
    // ready-Schwelle -> Annahme-PERIODE = MIN_SPACING+1. Tiles nutzen Bank =
    // step mod NBANK; mit NBANK=8 wird Bank s erst von Tile s+8 ueberschrieben.
    // WICHTIG: mit nur 2 Banks ist ein kleines Spacing FALSCH (Bank s wird von
    // s+2 ueberschrieben, waehrend s' tiefe PEs noch rechnen).
    // MIN_SPACING=3 -> Periode 4 = echter Feeder-Floor (S_WADDR->WLAT->WGET->FEED
    // = 4 Takte/Schritt). pytorch/feeder_sim.py verifiziert K8: spacing=3 (Periode 4)
    // ist bit-exakt (0/3000 Fehler, 0/500 bei S=50), spacing=2 (Periode 3) BRICHT
    // (566/3000). Das frueher gesetzte MIN_SPACING=4 (Periode 5) war 1 Takt/Schritt
    // unnoetige Marge -> hier auf den verifizierten Floor gesenkt.
    localparam int unsigned MIN_SPACING = 3;
    logic [$clog2(2*N)-1:0] space_cnt;

    // route-mode latch of a finished tile's row results
    logic signed [N-1:0][PSUM_W-1:0] route_q;

    // accumulators (accumulate mode)
    logic signed [N-1:0][PSUM_W-1:0] acc_q;

    always_ff @(posedge clk_i, negedge rst_ni) begin
        if (~rst_ni) begin
            acc_q          <= '0;
            route_q        <= '0;
            acc_cnt        <= '0;
            running        <= 1'b0;
            tile_pipe      <= '0;
            result_valid_o <= 1'b0;
            space_cnt      <= MIN_SPACING[$clog2(2*N)-1:0];  // start ready
        end else begin
            result_valid_o <= 1'b0;

            // advance the wavefront tracker
            tile_pipe <= {tile_pipe[PIPE_D-1:0], (running & act_valid_i & ready_o)};

            // spacing counter: 0 on an accepted tile, else count up (saturate).
            // route mode keeps ready high (no spacing needed), so only
            // accumulate mode uses this to gate ready_o.
            if (running & act_valid_i & ready_o) begin
                space_cnt <= '0;
            end else if (space_cnt != MIN_SPACING[$clog2(2*N)-1:0]) begin
                space_cnt <= space_cnt + 1'b1;
            end

            if (start_i) begin
                acc_q     <= '0;
                route_q   <= '0;
                acc_cnt   <= '0;
                running   <= 1'b1;
                tile_pipe <= '0;
                space_cnt <= MIN_SPACING[$clog2(2*N)-1:0];  // ready for first tile
            end else if (running) begin

                if (!mode_route_i) begin
                    // ---------- ACCUMULATE (baseline) ----------
                    for (int rr = 0; rr < N; rr++) begin
                        if (tile_pipe[GRID_LAT + rr]) begin
                            acc_q[rr] <= acc_q[rr] + right_psum[rr];
                        end
                    end
                    if (tile_pipe[PIPE_D] && (acc_cnt + 1 == num_steps_i)) begin
                        running        <= 1'b0;
                        result_valid_o <= 1'b1;
                    end
                    if (tile_pipe[PIPE_D]) begin
                        acc_cnt <= acc_cnt + 1;
                    end

                end else begin
                    // ---------- ROUTE / STREAM ----------
                    // Each row r of THIS tile is complete at bit N+r. We
                    // latch it directly (no accumulation). The tile is
                    // fully emitted when the last row (N-1) is ready.
                    for (int rr = 0; rr < N; rr++) begin
                        if (tile_pipe[GRID_LAT + rr]) begin
                            route_q[rr] <= right_psum[rr];
                        end
                    end
                    if (tile_pipe[PIPE_D]) begin
                        result_valid_o <= 1'b1;   // one pulse per finished tile
                    end
                    // route mode runs until the caller stops feeding and
                    // de-asserts via start of a new op; we keep running.
                end
            end
        end
    end

    // Bank reist per-wavefront mit der Aktivierung.

    // Backpressure to the feeder.
    //  - route mode: always ready (same-weight tiles may stream; the feeder
    //    is responsible for >= N spacing to avoid route_q overwrite).
    //  - accumulate mode: ready only once the previous tile has drained the
    //    required spacing, and only while running.
    assign ready_o = mode_route_i
                   ? 1'b1
                   : (running & (space_cnt == MIN_SPACING[$clog2(2*N)-1:0]));

    assign result_o = mode_route_i ? route_q : acc_q;

endmodule