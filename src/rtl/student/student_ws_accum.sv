module student_ws_accum #(
    parameter  int unsigned N       = 16,              // Zeilen/Kanaele pro Takt
    parameter  int unsigned PSUM_W  = 32,
    parameter  int unsigned NPOS    = 121,             // max. Positionen (conv2 11x11)
    localparam int unsigned PAW     = (NPOS <= 1) ? 1 : $clog2(NPOS)
) (
    input  logic clk_i,
    input  logic rst_ni,

    // --- Capture-Steuerung (vom WS-Sequencer) ---
    input  logic                          tile_start_i,  // Puls: neuer Tap-Tile-Stream
    input  logic                          first_tile_i,  // 1 = ueberschreiben, 0 = addieren
    input  logic [PAW-1:0]                npos_i,        // Anzahl Positionen dieses Streams
    input  logic [1:0]                    spacing_i,     // Injektions-Kadenz (conv1=1, conv2=2)
    input  logic signed [N-1:0][PSUM_W-1:0] right_psum_i,// rechter Array-Rand, DIESER Takt

    // --- Readout (nach dem letzten Tap-Tile) ---
    input  logic [PAW-1:0]                rd_pos_i,
    output logic signed [N-1:0][PSUM_W-1:0] acc_o
);

    // Zaehler: Takte seit tile_start. Laeuft bis npos*SPACING + 2N (letzte Diagonale).
    logic        capturing;
    logic [15:0] tcnt;                         // gross genug fuer npos*spacing + 2N
    logic        first_q;
    logic [PAW-1:0] npos_q;
    logic [1:0]  spacing_q;                    // gelatchte Kadenz (1 oder 2)

    always_ff @(posedge clk_i, negedge rst_ni) begin
        if (~rst_ni) begin
            capturing <= 1'b0;
            tcnt      <= '0;
            first_q   <= 1'b0;
            npos_q    <= '0;
            spacing_q <= 2'd1;
        end else if (tile_start_i) begin
            capturing <= 1'b1;
            tcnt      <= '0;
            first_q   <= first_tile_i;
            npos_q    <= npos_i;
            spacing_q <= spacing_i;
        end else if (capturing) begin
            // Stop-Grenze: spacing=1 -> npos+2N+1 ; spacing=2 -> npos*2+2N+1
            if (tcnt >= (((spacing_q == 2'd1) ? {5'b0, npos_q} : ({4'b0, npos_q} << 1)) + 2*N + 1))
                capturing <= 1'b0;
            tcnt <= tcnt + 1'b1;
        end
    end

    // --- N Baenke: je NPOS x PSUM_W, Simple-Dual-Port (1R/1W) ---
    genvar r;
    generate
        for (r = 0; r < N; r++) begin : g_bank
            (* ram_style = "block" *) logic signed [PSUM_W-1:0] mem [0:NPOS-1];

            // Stage A: Anti-Diagonale mit Kadenz SPACING. Zeile r bei Zyklus tcnt
            // gehoert zu Position p mit  p*SPACING + N + r + 1 == tcnt, also
            //   praw = tcnt-N-r-1,  p = praw/SPACING   (gueltig nur wenn praw>=0,
            //   auf dem SPACING-Raster liegt und p < npos).
            logic signed [15:0]  praw;
            logic                on_grid;
            logic signed [15:0]  p_div;
            logic                p_ok;
            logic [PAW-1:0]      p_addr;
            always_comb begin
                praw    = $signed(tcnt) - $signed(16'(N + r + 1));
                // spacing=1: jede Diagonale gueltig, p=praw. spacing=2: nur gerade
                // praw, p=praw/2 (>>>1, da praw>=0 beim Zugriff -> exakt).
                on_grid = (spacing_q == 2'd1) ? 1'b1 : ~praw[0];
                p_div   = (spacing_q == 2'd1) ? praw : (praw >>> 1);
                p_ok    = capturing && (praw >= 0) && on_grid
                                    && (p_div < $signed({1'b0, npos_q}));
                p_addr  = p_div[PAW-1:0];
            end

            // EIN Leseport (echtes SDP 1R/1W), zeit-gemuxt: waehrend capture der
            // RMW-Read der aktuellen Position, sonst Readout an rd_pos_i. Capture
            // (capturing=1) und Readout ueberlappen NIE, also genuegt ein Port ->
            // keine BRAM-Replikation auf dem 7-series-Target.
            logic [PAW-1:0]           rd_addr;
            logic signed [PSUM_W-1:0] rdata;
            assign rd_addr = capturing ? p_addr : rd_pos_i;
            always_ff @(posedge clk_i) rdata <= mem[rd_addr];   // 1-Takt Read-Latenz

            // Stage B: Add/Overwrite-Kontext parallel zur Read-Latenz registriert
            logic [PAW-1:0]      p_b;
            logic                first_b, val_b;
            logic signed [PSUM_W-1:0] rp_b;

            always_ff @(posedge clk_i, negedge rst_ni) begin
                if (~rst_ni) begin
                    val_b <= 1'b0; p_b <= '0; first_b <= 1'b0; rp_b <= '0;
                end else begin
                    val_b   <= p_ok;
                    p_b     <= p_addr;
                    first_b <= first_q;
                    rp_b    <= right_psum_i[r];
                end
            end

            // Stage B: addieren/ueberschreiben, zurueckschreiben (1W-Port).
            // rdata == mem[p_addr(t-1)] == acc der zu schreibenden Position p_b.
            wire signed [PSUM_W-1:0] wsum = first_b ? rp_b : (rdata + rp_b);
            always_ff @(posedge clk_i) begin
                if (val_b) mem[p_b] <= wsum;
            end

            // Readout: bei capturing=0 ist rdata == mem[rd_pos_i] (1-Takt-Latenz).
            assign acc_o[r] = rdata;
        end
    endgenerate

endmodule
