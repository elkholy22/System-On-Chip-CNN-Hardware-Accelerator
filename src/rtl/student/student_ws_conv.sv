module student_ws_conv #(
    parameter int unsigned N          = 16,
    parameter int unsigned ACT_W      = 8,
    parameter int unsigned W_W        = 8,
    parameter int unsigned PSUM_W     = 32,
    parameter int unsigned NPOS_MAX   = 676,   // max(conv1 676, conv2 121) -> accum-Tiefe
    parameter int unsigned IMW_C2     = 13,    // conv2-Eingabekarte 13 breit (gepolstert)
    parameter int unsigned CONV1_BASE = 5,     // conv1-Tile-Slot in der geteilten Weight-BRAM
    parameter int unsigned DRAIN_CYC  = 36     // 2N+4: Grid-Drain + RMW-Latenz
) (
    input  logic clk_i,
    input  logic rst_ni,

    // ---- Steuerung ----
    input  logic                            start_i,     // 1-Takt-Puls (Layer-Eintritt)
    input  logic                            mode_i,      // 1=conv2, 0=conv1 (bei start_i gelatcht)
    output logic                            busy_o,      // = (state != E_IDLE)
    output logic                            done_o,      // 1-Takt-Puls bei Abschluss

    // ---- conv2 act_buffer-Leseport: Port 1 = Tap A, Port 2 = Tap B (SPACING=1) ----
    output logic [10:0]                     buf_raddr_o, // Tap A: (rd_oh+kh_a)*IMW_C2 + (rd_ow+kw_a)
    input  logic signed [63:0]              buf_rdata_i, // 8-Kanal-Wort (Tap A)
    output logic [10:0]                     buf_raddr2_o,// Tap B: (rd_oh+kh_b)*IMW_C2 + (rd_ow+kw_b)
    input  logic signed [63:0]              buf_rdata2_i,// 8-Kanal-Wort (Tap B)

    // ---- conv1 pbuf-Leseport (NEU) ----
    output logic [9:0]                      pbuf_raddr_o,// pbuf-Position 0..675 (registriert)
    input  logic [71:0]                     pbuf_rdata_i,// 72b Patch-Wort {px8..px0}

    // ---- gemeinsamer Requant/relu_pool-Feed ----
    output logic                            rp_start_o,
    output logic                            rvalid_o,
    output logic                            grp_o,       // conv1 IMMER 0
    output logic signed [7:0][PSUM_W-1:0]   result_o,

    // ---- GETEILTES externes Array (Treiber-IF).
    //  Das systolic array lebt EINE Ebene hoeher (student_cnn) und wird
    //  zwischen conv (route, hier) und fc (accumulate, feeder) gemuxt. Diese
    //  Engine liefert nur noch die Steuer-/Datensignale (route mode) und
    //  konsumiert den rechten Array-Rand (right_psum) fuer den Akkumulator. ----
    output logic                                a_start_o,
    output logic                                a_wload_o,
    output logic                                a_avalid_o,
    output logic signed [N-1:0][N-1:0][W_W-1:0] a_wtile_o,
    output logic signed [N-1:0][ACT_W-1:0]      a_arow_o,
    input  logic signed [N-1:0][PSUM_W-1:0]     a_rpsum_i
);

  localparam int unsigned PAW = (NPOS_MAX <= 1) ? 1 : $clog2(NPOS_MAX);   // = 10

  logic mode_q;   // gelatchter Modus (1=conv2, 0=conv1)

  // ==========================================================================
  //  Interne Netze fuer die Submodule
  // ==========================================================================
  logic                              a_start, a_wload, a_avalid;
  logic signed [N-1:0][ACT_W-1:0]    a_arow;
  logic signed [N-1:0][N-1:0][W_W-1:0] wtile16;

  logic                              ac_tstart, ac_first;
  logic [PAW-1:0]                    ac_rdpos;
  logic signed [N-1:0][PSUM_W-1:0]   ac_acc;

  // ==========================================================================
  //  Submodul-Instanzen (geteilt zwischen conv1/conv2)
  // ==========================================================================
  // Das systolic array liegt in student_cnn (geteilt mit fc).
  // u_ws treibt es ueber a_*_o (route mode) und liest a_rpsum_i (rechter Rand).

  // Geteilter Akkumulator: Tiefe NPOS_MAX, Kadenz zur Laufzeit (spacing_i).
  student_ws_accum #(
      .N(N), .PSUM_W(PSUM_W), .NPOS(NPOS_MAX)
  ) u_acc (
      .clk_i        (clk_i),
      .rst_ni       (rst_ni),
      .tile_start_i (ac_tstart),
      .first_tile_i (ac_first),
      .npos_i       (mode_q ? PAW'(11'd121) : PAW'(11'd676)),
      .spacing_i    (2'd1),                     // conv1 UND conv2 SPACING=1
      .right_psum_i (a_rpsum_i),
      .rd_pos_i     (ac_rdpos),
      .acc_o        (ac_acc)
  );

  // ==========================================================================
  //  FSM-Zustand + Datenpfad-Zaehler (breiter fuer conv1's 676)
  // ==========================================================================
  typedef enum logic [3:0] {
      E_IDLE, E_WADDR, E_WLAT, E_WLOAD, E_PRE0, E_PRE1,
      E_START, E_STREAM, E_DRAIN_T, E_RO_G0, E_GDRAIN, E_RO_G1, E_DONE
  } e_state;
  e_state      state;

  logic [2:0]  tile;             // conv2 0..4, conv1 0
  logic [10:0] ic;               // Issue-Index (conv2 0..241, conv1 0..675)
  logic [10:0] sc;               // Stream-Zyklus / Akkumulator-tcnt-Bezug
  logic [3:0]  rd_oh, rd_ow;     // conv2-Issue-Position 0..10
  logic [6:0]  dcnt;             // Drain-Zaehler
  logic [10:0] rc;               // Auslese-Zaehler (conv2 0..122, conv1 0..677)

  // Weight-BRAM: conv2 -> Slot tile (0..4); conv1 -> Slot CONV1_BASE (=5).
  student_ws_weight_bram #(.N(N)) u_wbram (
      .clk_i       (clk_i),
      .tile_addr_i (mode_q ? tile : (3'(CONV1_BASE) + tile)),
      .wtile_o     (wtile16)
  );

  // ==========================================================================
  //  conv2 Issue-Adressierung (SPACING=1): pro Position BEIDE Taps eines Tiles
  //  gleichzeitig -- Tap A = Tap 2t (Port 1), Tap B = Tap 2t+1 (Port 2). ic zaehlt
  //  POSITIONEN (0..120), nicht Halb-Reads. Spiegelt conv1's spacing-1-Struktur.
  // ==========================================================================
  logic [3:0]  kh_a, kw_a, kh_b, kw_b;
  logic [10:0] addr_a, addr_b;
  logic        do_issue;

  always_comb begin
      // Tap A = 2t
      case ({1'b0, tile, 1'b0})
          5'd0:    begin kh_a = 4'd0; kw_a = 4'd0; end
          5'd2:    begin kh_a = 4'd0; kw_a = 4'd2; end
          5'd4:    begin kh_a = 4'd1; kw_a = 4'd1; end
          5'd6:    begin kh_a = 4'd2; kw_a = 4'd0; end
          default: begin kh_a = 4'd2; kw_a = 4'd2; end   // 5'd8 (tile 4)
      endcase
      // Tap B = 2t+1
      case ({1'b0, tile, 1'b0} + 5'd1)
          5'd1:    begin kh_b = 4'd0; kw_b = 4'd1; end
          5'd3:    begin kh_b = 4'd1; kw_b = 4'd0; end
          5'd5:    begin kh_b = 4'd1; kw_b = 4'd2; end
          5'd7:    begin kh_b = 4'd2; kw_b = 4'd1; end
          default: begin kh_b = 4'd2; kw_b = 4'd2; end   // 5'd9 (tile 4, ungenutzt -> b_word=0)
      endcase
  end
  assign addr_a = 11'( (rd_oh + kh_a) * IMW_C2 + (rd_ow + kw_a) );
  assign addr_b = 11'( (rd_oh + kh_b) * IMW_C2 + (rd_ow + kw_b) );

  // Eine Position pro Takt (beide Taps). conv2: ic<=120; conv1: ic<=675. Gleiche
  // Issue-Zustaende wie conv1 (E_PRE1/START/STREAM); E_PRE0 ist reiner Prime-Takt.
  assign do_issue = ((state==E_PRE1)||(state==E_START)||(state==E_STREAM))
                    && (ic <= (mode_q ? 11'd120 : 11'd675));

  // ==========================================================================
  //  Injektions-Datenpfad (kombinatorisch)
  //   conv2: even sc -> a_arow = {B(p), A(p)}; odd sc -> 0.
  //   conv1: jeder E_STREAM-Takt -> 9 Pixel in Lanes 0..8; Lanes 9..15 = 0.
  // ==========================================================================
  logic signed [63:0] a_word, b_word;
  assign a_word = buf_rdata_i;                             // Tap A (Port 1)
  assign b_word = (tile == 3'd4) ? 64'sd0 : buf_rdata2_i;  // Tap B (Port 2); tile4 High-8ch = 0

  always_comb begin
      a_arow = '0;
      if (mode_q) begin
          if (state == E_STREAM)                           // SPACING=1: jeden Takt injizieren
              a_arow = {b_word, a_word};                   // {Tap B (obere 8), Tap A (untere 8)}
      end else begin
          if (state == E_STREAM)
              for (int t = 0; t < 9; t++)
                  a_arow[t] = signed'(pbuf_rdata_i[t*8 +: 8]);
      end
  end

  // ==========================================================================
  //  Moore-Steuerausgaenge
  // ==========================================================================
  assign a_start   = (state == E_START);
  assign a_wload   = (state == E_WLOAD);
  assign a_avalid  = (state == E_STREAM);       // SPACING=1: conv1 UND conv2 jeden Takt

  // Treiber-Ausgaenge zum externen (geteilten) Array. mode_route/num_steps/banks
  // sind conv-Konstanten und werden in student_cnn gesetzt (route, 0, Bank 0).
  assign a_start_o  = a_start;
  assign a_wload_o  = a_wload;
  assign a_avalid_o = a_avalid;
  assign a_wtile_o  = wtile16;
  assign a_arow_o   = a_arow;

  assign ac_tstart = (state == E_START);
  assign ac_first  = (tile == 3'd0);

  assign busy_o    = (state != E_IDLE);
  assign done_o    = (state == E_DONE) && (dcnt == 7'd6);

  assign grp_o     = (state == E_RO_G1);   // conv1 erreicht diesen Zustand nie -> 0

  assign rp_start_o = ((state == E_RO_G0) || (state == E_RO_G1)) && (rc == 11'd0);
  assign rvalid_o   = ((state == E_RO_G0) || (state == E_RO_G1))
                      && (rc >= 11'd1) && (rc <= (mode_q ? 11'd121 : 11'd676));

  assign ac_rdpos   = (rc <= (mode_q ? 11'd120 : 11'd675)) ? rc[PAW-1:0] : {PAW{1'b0}};

  always_comb begin
      for (int k = 0; k < 8; k++)
          result_o[k] = grp_o ? ac_acc[k + 8] : ac_acc[k];
  end

  // ==========================================================================
  //  FSM + Datenpfad-Register
  // ==========================================================================
  always_ff @(posedge clk_i, negedge rst_ni) begin
      if (~rst_ni) begin
          state        <= E_IDLE;
          mode_q       <= 1'b1;
          tile         <= 3'd0;
          ic           <= 11'd0;
          sc           <= 11'd0;
          rd_oh        <= 4'd0;
          rd_ow        <= 4'd0;
          dcnt         <= 7'd0;
          rc           <= 11'd0;
          buf_raddr_o  <= 11'd0;
          buf_raddr2_o <= 11'd0;
          pbuf_raddr_o <= 10'd0;
      end else begin

          // ---- Issue-Pipeline (eine Position pro Takt; conv2: BEIDE Taps) ----
          if (do_issue) begin
              ic <= ic + 11'd1;
              if (mode_q) begin
                  buf_raddr_o  <= addr_a;                 // Tap A (Port 1)
                  buf_raddr2_o <= addr_b;                 // Tap B (Port 2)
                  if (rd_ow == 4'd10) begin rd_ow <= 4'd0; rd_oh <= rd_oh + 4'd1; end
                  else                     rd_ow <= rd_ow + 4'd1;
              end else begin
                  pbuf_raddr_o <= ic[9:0];                // conv1: lineare pbuf-Position
              end
          end

          // ---- Zustandsuebergaenge ----
          case (state)
              E_IDLE: begin
                  if (start_i) begin
                      mode_q <= mode_i;
                      tile   <= 3'd0;
                      state  <= E_WADDR;
                  end
              end

              E_WADDR: begin
                  ic    <= 11'd0;
                  rd_oh <= 4'd0;
                  rd_ow <= 4'd0;
                  state <= E_WLAT;
              end
              E_WLAT:  state <= E_WLOAD;
              E_WLOAD: state <= E_PRE0;

              // Prime: conv2 issued A(0)@PRE0, B(0)@PRE1. conv1: PRE0 idle,
              //        issued pos0@PRE1, pos1@START (via do_issue-Gate).
              E_PRE0:  state <= E_PRE1;
              E_PRE1:  state <= E_START;

              E_START: begin
                  sc    <= 11'd0;
                  state <= E_STREAM;
              end

              E_STREAM: begin
                  if (sc == (mode_q ? 11'd120 : 11'd675)) begin   // conv2 121 Pos (spacing-1)
                      dcnt  <= 7'd0;
                      state <= E_DRAIN_T;
                  end else begin
                      sc <= sc + 11'd1;
                  end
              end

              E_DRAIN_T: begin
                  if (dcnt == (DRAIN_CYC - 1)) begin
                      if (tile == (mode_q ? 3'd4 : 3'd0)) begin   // letztes Tile -> Ausgabe
                          rc           <= 11'd0;
                          buf_raddr_o  <= 11'd0;
                          buf_raddr2_o <= 11'd0;
                          pbuf_raddr_o <= 10'd0;
                          state        <= E_RO_G0;
                      end else begin
                          tile  <= tile + 3'd1;
                          state <= E_WADDR;
                      end
                  end else dcnt <= dcnt + 7'd1;
              end

              // Ausgabe Gruppe 0 (Kanaele 0..7). conv1 endet hier (kein G1).
              E_RO_G0: begin
                  if (rc == (mode_q ? 11'd122 : 11'd677)) begin
                      dcnt  <= 7'd0;
                      state <= mode_q ? E_GDRAIN : E_DONE;
                  end else rc <= rc + 11'd1;
              end

              // --- conv2-only ab hier ---
              E_GDRAIN: begin
                  if (dcnt == 7'd6) begin
                      rc    <= 11'd0;
                      state <= E_RO_G1;
                  end else dcnt <= dcnt + 7'd1;
              end

              E_RO_G1: begin
                  if (rc == 11'd122) begin
                      dcnt  <= 7'd0;
                      state <= E_DONE;
                  end else rc <= rc + 11'd1;
              end

              E_DONE: begin
                  if (dcnt == 7'd6) begin
                      state <= E_IDLE;
                  end else dcnt <= dcnt + 7'd1;
              end

              default: state <= E_IDLE;
          endcase
      end
  end

endmodule
