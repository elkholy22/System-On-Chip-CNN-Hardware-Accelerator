module student_cnn #(
    parameter int unsigned N = 8
) (
    input  logic              clk_i,
    input  logic              rst_ni,
    input  tlul_pkg::tl_h2d_t tl_i,
    output tlul_pkg::tl_d2h_t tl_o,
    output logic              irq_o
);

  // ---- TL-UL Registerinterface: reggen-generierter Block (student_cnn.hjson) ----
  //  Map unveraendert: ctrl 0x0, status 0x4, result 0x8, pixel 0xC (+cycle_count 0x10)
  import student_cnn_reg_pkg::*;

  student_cnn_reg2hw_t reg2hw;
  student_cnn_hw2reg_t hw2reg;

  student_cnn_reg_top u_reg_top (
      .clk_i, .rst_ni, .tl_i, .tl_o,
      .reg2hw, .hw2reg,
      .devmode_i(1'b1)
  );

  logic       busy, done;
  logic [3:0] result_digit;

  // start/clear als Ein-Takt-Pulse: qe pulst beim SW-Schreiben, q ist der Wert
  logic start_pulse, clear_pulse;
  assign start_pulse = reg2hw.ctrl.start.qe && reg2hw.ctrl.start.q;
  assign clear_pulse = reg2hw.ctrl.clear.qe && reg2hw.ctrl.clear.q;

  logic [9:0] wr_ptr;
  always_ff @(posedge clk_i, negedge rst_ni) begin
    if (~rst_ni)              wr_ptr <= '0;
    else if (clear_pulse)     wr_ptr <= '0;
    else if (reg2hw.pixel.qe) wr_ptr <= wr_ptr + 1'b1;
  end

  logic       img_we;
  logic [9:0] img_waddr;
  logic [7:0] img_wdata;
  assign img_we    = reg2hw.pixel.qe;
  assign img_wdata = reg2hw.pixel.q[7:0];
  assign img_waddr = wr_ptr;

  // Zyklen pro Inferenz (fuer Performance-Messung in SW/Bericht)
  logic [31:0] cyc_cnt;
  always_ff @(posedge clk_i, negedge rst_ni) begin
    if (~rst_ni)          cyc_cnt <= '0;
    else if (start_pulse) cyc_cnt <= '0;
    else if (busy)        cyc_cnt <= cyc_cnt + 32'd1;
  end

  // Status/Result kombinatorisch an den Registerblock (hwext)
  assign hw2reg.status.busy.d  = busy;
  assign hw2reg.status.done.d  = done;
  assign hw2reg.result.d       = result_digit;
  assign hw2reg.cycle_count.d  = cyc_cnt;

  // Per-Schicht-Zyklen-Snapshots: siehe DEBUG-Block weiter unten (nach cf_layer/
  // layer_done-Deklaration). hw2reg.cycle_layer{0..3} werden dort getrieben.

  assign irq_o = done;

  // ---- Quelle: image_bram -> im2col ----
  logic       img_start;
  logic [7:0] img_rdata;
  logic       img_valid;
  logic       img_busy;

  student_image_bram u_img (
      .clk_i, .rst_ni,
      .we_i(img_we), .waddr_i(img_waddr), .wdata_i(img_wdata),
      .start_i(img_start), .rdata_o(img_rdata), .valid_o(img_valid),
      .busy_o(img_busy)
  );

  logic       patch_valid;
  logic [7:0] patch [0:8];

  im2col #(.IMG_W(28), .IMG_H(28), .KER_W(3), .KER_H(3)) u_im2col (
      .clk_i, .rst_ni,
      .clear_i(img_start),          // pro Bild nullen -> Multi-Inferenz ohne Reset
      .valid_i(img_valid), .pixel_i(img_rdata),
      .valid_o(patch_valid), .patch_o(patch)
  );

  // ---- gelatchter Patch fuer eine Treiber-Operation ----
  logic signed [7:0] patch_lat [0:8];

  // ---- Treiber <-> Array ----
  // per-wavefront banking: Bank-Index ist BW Bit breit (NBANK=8 -> 3).
  localparam int unsigned NBANK = 8;
  localparam int unsigned BW    = $clog2(NBANK);
  logic                       a_start, a_mode, a_wload;
  logic [BW-1:0]              a_lbank, a_ubank;
  logic [8:0]                 a_nsteps;
  logic                       a_avalid, a_ready, a_rvalid;
  // fc-Feeder N=16 (Input-Widening): 16 Eingaenge/Schritt. Ausgaenge
  // bleiben 8/Gruppe (obere 8 Array-Zeilen = 0) -> Readout unveraendert 8 breit.
  logic signed [15:0][15:0][7:0]    a_wtile;
  logic signed [15:0][7:0]          a_arow;
  logic signed [15:0][31:0]         a_result;

  // ---- Treiber-Kommando (Sequencer) ----
  logic        op_start, op_busy, op_rvalid;
  logic [8:0]  op_nsteps;
  logic [11:0] op_wbase;
  logic signed [15:0][31:0] op_result;   // fc-Feeder N=16 (16 echte Ausgaben)
  logic signed [15:0][31:0] op_result_q; // gelatchte Op-Ausgabe fuer 2x8-Readout
  logic                     fc_sub;      // fc1-Readout-Halbwahl (0=Kanaele 0-7, 1=8-15)
  logic                     fc_ro_vld;   // fc-Readout-Puls (= ostate==O_FC_RO)

  // ---- WEIGHT-STATIONARY N=16 conv2-Engine + eff_*-Muxe (nur cf_layer==1) ----
  // Nur conv2 laeuft ueber die WS-Engine; conv1/fc bleiben auf dem N=8-Pfad.
  // Die geteilten Netze (op_result/op_rvalid/rp_start/grp/buf_raddr) werden per
  // eff_* auf conv2_active gemuxt; die O_C2_*-Zustaende sind dann ungenutzt.
  logic                    conv2_active;
  logic                    ws_active;                 // conv1 ODER conv2 laeuft ueber die WS-Engine
  logic                    ws_start, ws_busy, ws_done, ws_rvalid, ws_grp, ws_rp_start;
  logic [10:0]             ws_buf_raddr;
  logic [10:0]             ws_buf_raddr2;             // conv2 Tap-B-Adresse (2. act_buffer-Port)
  logic signed [63:0]      buf_rd_data2;              // act_buffer Port-2-Daten (conv2 Tap B)
  logic [9:0]              ws_pbuf_raddr;             // conv1: pbuf-Leseadresse von der Engine
  logic [71:0]             pbuf_rd;                   // frueh deklariert (u_ws liest sie)
  logic signed [7:0][31:0] ws_result;

  // Stage-1: GETEILTES N=16 systolic array. conv treibt
  // es hier ueber ws_a_* (route mode); der rechte Rand geht zurueck als ws_a_rpsum.
  logic                          ws_a_start, ws_a_wload, ws_a_avalid;
  logic signed [15:0][15:0][7:0] ws_a_wtile;
  logic signed [15:0][7:0]       ws_a_arow;
  logic signed [15:0][31:0]      ws_a_rpsum;
  logic                    eff_op_rvalid, eff_rp_start;
  logic [3:0]              eff_grp;
  logic [10:0]             eff_buf_raddr;
  logic signed [31:0]      eff_op_result [0:7];
  logic [3:0]              grp;   // Filtergruppe -- frueh deklariert (eff_grp-Mux liest sie)

  // ---- Weight-BRAM (Kachel) -- fc N=16 (16x16-Kacheln, weights_tiles16.mem) ----
  logic [11:0]                      wtile_addr;
  logic signed [15:0][15:0][7:0]    wtile;

  // ---- Aktivierungs-Vektor pro Schritt: 16 Kanaele aus stepvec (fc, N=16) ----
  //  fc1: stepvec[S][0..15] = 16 Eingaenge an Pool-Pos S (2 act_buffer-Woerter).
  //  fc2: stepvec[S][0..15] = 16 fc1-Ausgaben (2 Woerter). max 25 Schritte (fc1).
  logic [8:0]                astep;
  logic                      av_req;
  logic signed [15:0][7:0]   avec;
  logic signed [7:0]         stepvec [0:24][0:15];   // 25 Schritte x 16 Kanaele
  always_comb begin
    for (int c = 0; c < 16; c++) avec[c] = '0;
    if (astep <= 9'd24)
      for (int c = 0; c < 16; c++) avec[c] = stepvec[astep][c];
  end

  student_weight_bram #(.N(16)) u_wgt (
      .clk_i, .rst_ni,
      .we_i(1'b0), .waddr_i('0), .wdata_i('0),
      .tile_addr_i(wtile_addr), .wtile_o(wtile)
  );

  student_systolic_array_feeder #(.N(16), .NBANK(NBANK)) u_feed (
      .clk_i, .rst_ni,
      .op_start_i(op_start), .op_nsteps_i(op_nsteps), .op_wbase_i(op_wbase),
      .op_busy_o(op_busy), .op_rvalid_o(op_rvalid), .op_result_o(op_result),
      .wtile_addr_o(wtile_addr), .wtile_i(wtile),
      .astep_o(astep), .av_req_o(av_req), .avec_i(avec),
      .a_start_o(a_start), .a_mode_o(a_mode), .a_nsteps_o(a_nsteps),
      .a_wload_o(a_wload), .a_lbank_o(a_lbank), .a_ubank_o(a_ubank),
      .a_wtile_o(a_wtile), .a_avalid_o(a_avalid), .a_ready_i(a_ready),
      .a_arow_o(a_arow), .a_rvalid_i(a_rvalid), .a_result_i(a_result)
  );

  // fc laeuft ueber das geteilte u_array16 (genullt-erweitert).
  // a_ready/a_rvalid/a_result werden von u_array16 getrieben.

  // ---- relu_pool: EINE Lane pro Array-Kanal (per-channel pixel stream) ----
  //  Das Array liefert pro Position N Kanaele gleichzeitig (op_result[0..N-1]).
  //  Jede Lane requantisiert + ReLU und baut ihr 2x2-Pooling ueber die Zeit auf.
  //  ready_i=1: der act_buffer nimmt immer an (Producer ist viel langsamer).
  logic               rp_start, rp_vld;
  logic               relu_en, pool_en;
  logic signed [31:0] rp_mult  [0:7];   // per-Lane (per-Kanal) Requant
  logic [5:0]         rp_shift [0:7];
  logic               rp_ready [N];
  logic               rp_vld_n [N];
  logic signed [7:0]  rp_act   [N];

  // ---- Bias/Offset pro Ausgangskanal (aus export_bias.py -> bias.mem) ----
  //  op_biased = MAC + Offset, VOR dem Requant. Deklaration hier (vor der
  //  relu_pool-Instanz); der Wert wird weiter unten (nach cf_layer) berechnet.
  localparam int NBIAS = 128;                // >= 98 (conv1 8 + conv2 16 + fc1 64 + fc2 10) + Padding
  logic signed [31:0] bias_mem  [0:NBIAS-1]; // per-Kanal Offset
  logic signed [31:0] mult_mem  [0:NBIAS-1]; // per-Kanal Requant-Multiplikator
  logic        [5:0]  shift_mem [0:NBIAS-1]; // per-Kanal Requant-Shift
  logic signed [31:0] op_biased [0:7];
`ifndef STRINGIFY
  `define STRINGIFY(x) `"x`"
`endif
  initial begin
    for (int i = 0; i < NBIAS; i++) begin
      bias_mem[i]  = '0;
      mult_mem[i]  = 32'sd1;
      shift_mem[i] = 6'd0;
    end
`ifdef BIAS_MEM_FILE
    $readmemh(`STRINGIFY(`BIAS_MEM_FILE), bias_mem);
`endif
`ifdef MULT_MEM_FILE
    $readmemh(`STRINGIFY(`MULT_MEM_FILE), mult_mem);
`endif
`ifdef SHIFT_MEM_FILE
    $readmemh(`STRINGIFY(`SHIFT_MEM_FILE), shift_mem);
`endif
  end

  // Pooling-Bildmaße pro Schicht (Zuweisung weiter unten, nach cf_layer).
  logic [5:0] rp_imgw, rp_imgh;

  // ---- Timing-Pipeline Stufe 1: Bias-Addition + Requant-Parameter registrieren
  //  (bricht den 40-Level-Pfad: Bias-Add | DSP-Multiplikation | Shift/Sat/Pool).
  //  Werte werden bei op_rvalid mit der Konfiguration der AKTUELLEN Op gelatcht
  //  (grp/cf_layer aendern sich erst danach) -> funktional identisch, +1 Takt.
  logic               rp_v_q;
  logic signed [31:0] ob_q    [0:7];
  logic signed [31:0] mult_q  [0:7];
  logic [5:0]         shift_q [0:7];
  always_ff @(posedge clk_i, negedge rst_ni) begin
    if (~rst_ni) begin
      rp_v_q <= 1'b0;
      for (int k = 0; k < 8; k++) begin
        ob_q[k] <= '0; mult_q[k] <= 32'sd1; shift_q[k] <= '0;
      end
    end else begin
      rp_v_q <= eff_op_rvalid;
      if (eff_op_rvalid) begin
        for (int k = 0; k < 8; k++) begin
          ob_q[k]    <= op_biased[k];
          mult_q[k]  <= rp_mult[k];
          shift_q[k] <= rp_shift[k];
        end
      end
    end
  end

  genvar li;
  generate
    for (li = 0; li < N; li++) begin : g_relu
      student_relu_pool #(.IN_W(32), .OUT_W(8), .IMG_W_MAX(26), .IMG_H_MAX(26)) u_relu (
          .clk_i, .rst_ni,
          .start_i             (eff_rp_start),
          .img_w_i             (rp_imgw),
          .img_h_i             (rp_imgh),
          .relu_en_i           (relu_en),
          .pool_en_i           (pool_en),
          .requant_multiplier_i(mult_q[li]),
          .requant_shift_i     (shift_q[li]),
          .valid_i             (rp_v_q),
          .ready_o             (rp_ready[li]),
          .pixel_i             (ob_q[li]),
          .ready_i             (1'b1),
          .valid_o             (rp_vld_n[li]),
          .act_o               (rp_act[li])
      );
    end
  endgenerate
  assign rp_vld = rp_vld_n[0];   // alle Lanes laufen synchron

  // ---- act_buffer: Ping-Pong-Puffer zwischen Schichten -------------------
  //  Scaffold: sequenzieller Schreibzeiger, Bank kippt pro Schicht (buf_swap).
  //  Es wird vorerst nur Kanal 0 gespeichert; Lesepfad (act_buffer->im2col)
  //  und Mehrkanal-Ablage sind der naechste Korrektheitsschritt.
  //  Ping-Pong-Bank = Layer-Paritaet (aus controller_fsm). Schreibzeiger laeuft
  //  sequenziell, wird bei jedem Schichtwechsel (layer_start_d) genullt.
  // ---- Steuerungs-Signale (controller_fsm): VOR erster Nutzung deklariert ----
  logic        cf_busy, cf_done, cf_error;
  logic [2:0]  cf_state, cf_layer;
  logic [1:0]  cf_feeder;
  logic [3:0]  cf_in_ch;
  logic [7:0]  cf_depth;
  logic        cf_use_pool, cf_use_relu, cf_argmax_en, cf_layer_start, cf_clear_acc;
  logic [31:0] cf_num_in;
  logic        layer_done;
  logic        layer_start_d;

  logic               buf_bank;
  logic [10:0]        buf_waddr;
  logic [10:0]        buf_raddr;
  logic signed [63:0] buf_rd_data;

  assign buf_bank = cf_layer[0];

  // ---- generische WS-Engine (conv1 mode_i=0, conv2 mode_i=1) + eff_*-Muxe ----
  assign conv2_active = (cf_layer == 3'd1);
  assign ws_active    = (cf_layer == 3'd0) || (cf_layer == 3'd1);
  student_ws_conv u_ws (
      .clk_i, .rst_ni,
      .start_i      (ws_start),
      .mode_i       (conv2_active),      // 1=conv2, 0=conv1
      .busy_o       (ws_busy),
      .done_o       (ws_done),
      .buf_raddr_o  (ws_buf_raddr),
      .buf_rdata_i  (buf_rd_data),
      .buf_raddr2_o (ws_buf_raddr2),
      .buf_rdata2_i (buf_rd_data2),
      .pbuf_raddr_o (ws_pbuf_raddr),
      .pbuf_rdata_i (pbuf_rd),
      .rp_start_o   (ws_rp_start),
      .rvalid_o     (ws_rvalid),
      .grp_o        (ws_grp),
      .result_o     (ws_result),
      .a_start_o    (ws_a_start),
      .a_wload_o    (ws_a_wload),
      .a_avalid_o   (ws_a_avalid),
      .a_wtile_o    (ws_a_wtile),
      .a_arow_o     (ws_a_arow),
      .a_rpsum_i    (ws_a_rpsum)
  );

  // ===== EIN geteiltes N=16 systolic array fuer ALLE 4 Schichten =====
  //  conv1/conv2 -> route mode (volle 16 Kanaele). fc1/fc2 -> accumulate mode,
  //  auf die untere 8x8-Ecke genullt-erweitert (feeder ist N=8). Mux per ws_active.
  logic                          arr_start, arr_mode, arr_wload, arr_avalid;
  logic [8:0]                    arr_nsteps;
  logic [2:0]                    arr_lbank, arr_ubank;
  logic signed [15:0][15:0][7:0] arr_wtile;
  logic signed [15:0][7:0]       arr_arow;
  logic signed [15:0][31:0]      arr_result;    // Array-Ergebnis (untere 8 -> fc)

  always_comb begin
    if (ws_active) begin                       // conv: WS-Treiber, route mode
      arr_start  = ws_a_start;  arr_mode  = 1'b1;   arr_nsteps = 9'd0;
      arr_wload  = ws_a_wload;  arr_lbank = 3'd0;   arr_ubank  = 3'd0;
      arr_avalid = ws_a_avalid;
      arr_wtile  = ws_a_wtile;
      arr_arow   = ws_a_arow;
    end else begin                             // fc: Feeder (nativ N=16), accumulate
      arr_start  = a_start;     arr_mode  = a_mode;  arr_nsteps = a_nsteps;
      arr_wload  = a_wload;     arr_lbank = a_lbank; arr_ubank  = a_ubank;
      arr_avalid = a_avalid;
      arr_wtile  = a_wtile;
      arr_arow   = a_arow;
    end
  end

  student_systolic_array #(.N(16), .ACT_W(8), .W_W(8), .PSUM_W(32), .NBANK(8)) u_array16 (
      .clk_i, .rst_ni,
      .start_i        (arr_start),
      .mode_route_i   (arr_mode),
      .num_steps_i    (arr_nsteps),
      .weight_load_i  (arr_wload),
      .load_bank_i    (arr_lbank),
      .use_bank_i     (arr_ubank),
      .weight_tile_i  (arr_wtile),
      .act_valid_i    (arr_avalid),
      .ready_o        (a_ready),         // fc-Feeder-Backpressure (conv route: =1, ignoriert)
      .act_row_i      (arr_arow),
      .result_valid_o (a_rvalid),        // fc-Ergebnis-Puls
      .result_o       (arr_result),
      .right_psum_o   (ws_a_rpsum)        // conv-Anti-Diagonale -> u_ws-Akkumulator
  );
  // fc-Feeder ist N=16 -> volles Array-Ergebnis zurueck (nur untere 8 sind echt).
  assign a_result = arr_result;
  // op_rvalid/rp_start/op_result auf ws_active (conv1 UND conv2) muxen;
  // grp/buf_raddr bleiben conv2_active (conv1: grp=0, liest pbuf statt act_buffer).
  // fc: Readout 2x8 aus der gelatchten 16-Op-Ausgabe (fc_sub waehlt Haelfte);
  //     eff_op_rvalid pulst je Halb-Pass (= ostate==O_FC_RO).
  assign eff_op_rvalid = ws_active   ? ws_rvalid   : fc_ro_vld;
  assign eff_rp_start  = ws_active   ? ws_rp_start : rp_start;
  assign eff_grp       = conv2_active ? {3'b0, ws_grp} : grp;
  assign eff_buf_raddr = conv2_active ? ws_buf_raddr : buf_raddr;
  always_comb for (int k = 0; k < 8; k++)
    eff_op_result[k] = ws_active ? ws_result[k] : op_result_q[fc_sub ? (k+8) : k];

  // Alle 8 Kanaele (Lanes) zu EINEM 64-bit-Wort packen -> pro Position 1 Eintrag.
  logic [63:0] rp_word;
  always_comb for (int k = 0; k < 8; k++) rp_word[k*8 +: 8] = rp_act[k];

  always_ff @(posedge clk_i, negedge rst_ni) begin
    if      (~rst_ni)       buf_waddr <= '0;
    else if (layer_start_d) buf_waddr <= '0;
    else if (rp_vld)        buf_waddr <= buf_waddr + 1'b1;
  end

  student_act_buffer #(.DATA_W(64), .DEPTH(2048)) u_actbuf (
      .clk_i, .rst_ni,
      .bank_sel_i(buf_bank),
      .we_i      (rp_vld),
      .waddr_i   (buf_waddr),
      .wdata_i   (rp_word),
      .raddr_i   (eff_buf_raddr),
      .rdata_o   (buf_rd_data),
      .raddr2_i  (ws_buf_raddr2),   // conv2 Tap-B-Port (sonst don't-care)
      .rdata2_o  (buf_rd_data2)
  );

  // ---- argmax: fc2_scores werden vom Sequencer waehrend fc2 gelatcht ----
  logic signed [31:0] fc2_scores [0:9];
  logic               argmax_start, argmax_done;

  student_argmax #(.N(10)) u_argmax (
      .clk_i, .rst_ni,
      .start_i(argmax_start), .scores_i(fc2_scores),
      .digit_o(result_digit), .done_o(argmax_done)
  );

  // ==========================================================================
  //  Schicht-Steuerung: student_controller_fsm = Gehirn (CONV1..FC2..ARGMAX).
  //  Ein kleiner Op-Sequencer speist pro Schicht num_in Positionen ins Array
  //  und meldet layer_done zurueck. Ping-Pong ueber Layer-Paritaet.
  //
  //  KORREKT PER KONSTRUKTION: Schichtreihenfolge + Ping-Pong + Konfiguration.
  //  NOCH PLATZHALTER (in Questa zu verifizieren): pro Position wird der zuletzt
  //  gelatchte Patch wiederverwendet; argmax liest op_result direkt; nur Kanal 0
  //  wird gepuffert; Lesepfad act_buffer->im2col fuer Schicht >=1 fehlt.
  // ==========================================================================

  student_controller_fsm u_ctrl (
      .clk_i, .rst_ni,
      .start_i           (start_pulse),
      .clear_i           (1'b0),
      .layer_done_i      (layer_done),
      .busy_o            (cf_busy),
      .done_o            (cf_done),
      .error_o           (cf_error),
      .state_o           (cf_state),
      .layer_sel_o       (cf_layer),
      .feeder_sel_o      (cf_feeder),
      .in_ch_o           (cf_in_ch),
      .depth_steps_o     (cf_depth),
      .use_pool_o        (cf_use_pool),
      .use_relu_o        (cf_use_relu),
      .argmax_en_o       (cf_argmax_en),
      .layer_start_o     (cf_layer_start),
      .clear_acc_o       (cf_clear_acc),
      .relu_pool_num_in_o(cf_num_in)
  );

  // layer_start um 1 Takt verzoegert: dann ist state_q (und damit die
  // Konfiguration) schon die der NEUEN Schicht.
  always_ff @(posedge clk_i, negedge rst_ni) begin
    if (~rst_ni) layer_start_d <= 1'b0;
    else         layer_start_d <= cf_layer_start;
  end

  // ---- Konfiguration aus dem controller_fsm ----
  assign relu_en   = cf_use_relu;
  assign pool_en   = cf_use_pool;

  // conv2/fc-Rücklese-Zustand (vor op_wbase/bias_base genutzt)
  // grp ist oben (frueh) deklariert -- fuer den eff_grp-Mux.
  logic [3:0] orow, ocol;       // conv2-Ausgabeposition 0..10
  logic [5:0] ri;               // Lesindex: conv2 Tap 0..8, fc Wort 0..49

  // MAC + Bias/Offset + PER-KANAL Requant-Parameter. bias_base = Start des
  // Schicht-Blocks in den Tabellen (conv1=0, conv2=8, fc1=24, fc2=88, + Gruppe*8).
  // Lane k -> Kanal bias_base+k.
  logic [7:0] bias_base;
  always_comb begin
    case (cf_layer)
      3'd0:    bias_base = 8'd0;                   // conv1
      3'd1:    bias_base = 8'd8  + eff_grp*8'd8;   // conv2 (eff_grp = ws_grp)
      3'd2:    bias_base = 8'd24 + grp*8'd16 + (fc_sub ? 8'd8 : 8'd0);  // fc1 (4 Grp x 16 Ausg, 2x8)
      default: bias_base = 8'd88 + grp*8'd8;       // fc2
    endcase
    for (int k = 0; k < 8; k++) begin
      op_biased[k] = $signed(eff_op_result[k]) + bias_mem[bias_base + k];
      rp_mult[k]   = mult_mem[bias_base + k];
      rp_shift[k]  = shift_mem[bias_base + k];
    end
  end

  // Pooling-Bildmaße pro Schicht (rp_imgw/rp_imgh oben deklariert).
  always_comb begin
    case (cf_layer)
      3'd0:    begin rp_imgw = 6'd26; rp_imgh = 6'd26; end  // conv1
      3'd1:    begin rp_imgw = 6'd11; rp_imgh = 6'd11; end  // conv2
      default: begin rp_imgw = 6'd1;  rp_imgh = 6'd1;  end  // fc (pool_en=0)
    endcase
  end
  assign op_nsteps = {1'b0, cf_depth};   // depth_steps[7:0] -> nsteps[8:0]
  assign busy      = cf_busy;            // rp_start wird vom Sequencer getrieben

  // Kachel-Basis pro Schicht -- passend zum Layout aus reorder_weights.py:
  //  conv1 base 0 (2 Kacheln), conv2 base 2 (18), fc1 base 20 (400), fc2 base 420 (16).
  always_comb begin
    // weights_tiles16.mem (16x16-Kacheln): fc1 = 8 Gruppen x 25, fc2 = 2 Gruppen x 4.
    case (cf_layer)
      3'd0:    op_wbase = 12'd0;                    // CONV1 (ungenutzt, WS-Engine)
      3'd1:    op_wbase = 12'd0;                    // CONV2 (ungenutzt, WS-Engine)
      3'd2:    op_wbase = grp*12'd25;               // FC1 (4 Gruppen x 25 -> Kacheln 0..99)
      3'd3:    op_wbase = 12'd100 + grp*12'd4;      // FC2 (Kacheln 100..107)
      default: op_wbase = 12'd0;
    endcase
  end

  // done haelt bis zum naechsten Start (controller_fsm S_DONE ist nur 1 Takt).
  logic done_sticky;
  always_ff @(posedge clk_i, negedge rst_ni) begin
    if      (~rst_ni)     done_sticky <= 1'b0;
    else if (start_pulse) done_sticky <= 1'b0;
    else if (cf_done)     done_sticky <= 1'b1;
  end
  assign done = done_sticky;

  // ---- Per-Schicht-Zyklen (DEBUG-Instrumentierung) --------------------------
  //  Kumulativer cyc_cnt zum layer_done JEDER Schicht, erfasst auf STEIGENDER
  //  Flanke von layer_done -> genau 1 Snapshot pro Schicht (pulsbreiten-robust).
  //  cf_layer haelt beim layer_done noch die abschliessende Schicht (der
  //  controller_fsm schaltet erst im Folgetakt weiter). ARGMAX (cf_layer==4)
  //  wird ausgeblendet -> dessen Anteil = cycle_count - cycle_layer3.
  //  SW-Auswertung:  conv1=L0, conv2=L1-L0, fc1=L2-L1, fc2=L3-L2, argmax=tot-L3.
  logic [31:0] cyc_layer [0:3];
  logic        layer_done_q;
  always_ff @(posedge clk_i, negedge rst_ni) begin
    if (~rst_ni) begin
      layer_done_q <= 1'b0;
      for (int i = 0; i < 4; i++) cyc_layer[i] <= '0;
    end else begin
      layer_done_q <= layer_done;
      if (start_pulse) begin
        for (int i = 0; i < 4; i++) cyc_layer[i] <= '0;
      end else if (layer_done & ~layer_done_q & (cf_layer < 3'd4)) begin
        cyc_layer[cf_layer[1:0]] <= cyc_cnt;
      end
    end
  end
  assign hw2reg.cycle_layer0.d = cyc_layer[0];
  assign hw2reg.cycle_layer1.d = cyc_layer[1];
  assign hw2reg.cycle_layer2.d = cyc_layer[2];
  assign hw2reg.cycle_layer3.d = cyc_layer[3];

  // Staleness-Guard: konstante Build-Kennung (0xC10000NN). Bei JEDER RTL-Aenderung
  // NN erhoehen. SW liest 0x24 -> stimmt der Wert, ist der Build frisch (nicht stale).
  assign hw2reg.version.d      = 32'hC100_000A;

  // ---- Patch-Puffer: erfasst ALLE gueltigen Patches aus im2col (kein Verlust).
  //  SYNTHESE: als 72-bit-BRAM (1 Patch/Wort, registrierter Read) statt
  //  Register-Array (waere ~50k FFs). Read-Latenz deckt der Zustand O_FEEDW ab.
  localparam int unsigned MAXP = 700;        // >= 26*26 = 676 conv1-Positionen
  (* ram_style = "block" *) logic [71:0] pbuf [0:MAXP-1];
  // pbuf_rd ist oben (frueh) deklariert -- fuer den u_ws-pbuf-Port.
  logic [15:0] wp;                            // Anzahl erfasster Patches

  // Schreibport: 1 Patch (9 Bytes) pro Wort
  always_ff @(posedge clk_i) begin
    if (patch_valid && (wp < MAXP))
      pbuf[wp[9:0]] <= {patch[8], patch[7], patch[6], patch[5], patch[4],
                        patch[3], patch[2], patch[1], patch[0]};
  end

  always_ff @(posedge clk_i, negedge rst_ni) begin
    if (~rst_ni)            wp <= '0;
    else if (layer_start_d) wp <= '0;         // pro Schicht neu erfassen
    else if (patch_valid && (wp < MAXP)) wp <= wp + 16'd1;
  end

  // ---- Op-Sequencer:
  //  conv1/fc  -> Patch-Stream (O_STREAM/O_SETTLE/O_FEED/O_WAITOP), avec aus stepvec (8+1).
  //  conv2     -> act_buffer-Rücklesen (O_C2_*): pro Ausgabeposition 9 Fenster-Woerter
  //               lesen (8 Kanaele je Tap) -> stepvec -> Op; 2 Filtergruppen, 2 Pool-Pässe.
  typedef enum logic [4:0] {O_IDLE, O_STREAM, O_SETTLE, O_FEEDW, O_FEED, O_WAITOP, O_ARG,
                            O_C2_PRE, O_C2_RDW, O_C2_RD, O_C2_OP, O_C2_WAIT,
                            O_FC_PRE, O_FC_RDW, O_FC_RD, O_FC_OP, O_FC_WAIT, O_FC_RO,
                            O_DRAIN, O_C2_GDRAIN, O_C2_WS} o_e;
  o_e          ostate;
  logic [15:0] pos, nptot;
  logic [2:0]  scnt;
  logic [2:0]  dcnt;    // Drain: Requant-Pipeline (~3 Takte) vor layer_done leeren
  logic [3:0]  last_grp;
  assign last_grp = (cf_layer == 3'd2) ? 4'd3 : 4'd1;   // fc1: 4 Gruppen (x16 Ausg), fc2: 2
  assign fc_ro_vld = (ostate == O_FC_RO);               // fc-Requant-Puls je Halb-Pass

  // pbuf-Leseport: registriert (BRAM), Adresse = aktuelle Position pos
  always_ff @(posedge clk_i) begin
    pbuf_rd <= pbuf[(cf_layer == 3'd0) ? ws_pbuf_raddr[9:0] : pos[9:0]];
  end

  always_ff @(posedge clk_i, negedge rst_ni) begin
    if (~rst_ni) begin
      ostate       <= O_IDLE;
      pos          <= '0;
      nptot        <= '0;
      scnt         <= '0;
      dcnt         <= '0;
      grp          <= 4'd0;
      orow         <= '0;
      ocol         <= '0;
      ri           <= '0;
      buf_raddr    <= '0;
      img_start    <= 1'b0;
      op_start     <= 1'b0;
      rp_start     <= 1'b0;
      argmax_start <= 1'b0;
      layer_done   <= 1'b0;
      ws_start     <= 1'b0;
      fc_sub       <= 1'b0;
      for (int i = 0; i < 10; i++) fc2_scores[i] <= '0;
    end else begin
      img_start    <= 1'b0;
      op_start     <= 1'b0;
      rp_start     <= 1'b0;
      argmax_start <= 1'b0;
      layer_done   <= 1'b0;
      ws_start     <= 1'b0;

      case (ostate)
        O_IDLE: if (layer_start_d) begin   // neue Schicht (Konfig stabil)
          pos <= '0;
          if (cf_argmax_en) begin
            argmax_start <= 1'b1;                        // Argmax-Schicht
            ostate       <= O_ARG;
          end else if (cf_layer == 3'd0) begin          // conv1: im2col->pbuf, dann WS-Engine
            img_start <= 1'b1; ostate <= O_STREAM;       // rp_start treibt die Engine (ws_rp_start)
          end else if (cf_layer == 3'd1) begin          // conv2: WEIGHT-STATIONARY-Engine
            ws_start <= 1'b1; ostate <= O_C2_WS;
          end else begin                                // fc1/fc2: lineares Rücklesen
            grp <= 4'd0; rp_start <= 1'b1; ostate <= O_FC_PRE;
          end
        end

        // ---- conv1: OVERLAP -- WS-Engine starten, sobald genug Patches gepuffert
        //  sind; im2col-Stream + pbuf-Write laufen autonom (unabhaengig von ostate)
        //  waehrend O_C2_WS weiter. Die Engine liest pbuf-Positionen 0..675 linear
        //  (1/Takt); im2col schreibt sie linear (~0.93/Takt), also HOLT der Consumer
        //  auf -> die Luecke schrumpft monoton, die LETZTE Position (675) bindet.
        //  WATERMARK=96 -> Stream-Start ~t188, letzte Lesung ~t870 > Producer-Ende
        //  ~t813 (~57 Takte Marge). Timing ist DATENUNABHAENGIG (Bild-/im2col-Kadenz
        //  fest) -> xsim digit=7 auf einem Bild verifiziert es fuer alle.
        O_STREAM: if (wp >= 16'd96) begin
          nptot    <= 16'd676;
          ws_start <= 1'b1;
          ostate   <= O_C2_WS;
        end
        // O_SETTLE: fuer conv1 ungenutzt (Overlap ersetzt "warte auf vollen
        // Stream + settle"). Bleibt im Enum.
        O_SETTLE: if (scnt == 3'd3) begin
          nptot   <= wp;
          ws_start <= 1'b1;
          ostate  <= O_C2_WS;
        end else scnt <= scnt + 3'd1;
        O_FEEDW: ostate <= O_FEED;                      // 1 Takt pbuf-BRAM-Leselatenz
        O_FEED: begin                                   // stepvec aus Patch (8+1-Split)
          for (int c = 0; c < 8; c++) stepvec[0][c] <= $signed(pbuf_rd[c*8 +: 8]);
          stepvec[1][0] <= $signed(pbuf_rd[71:64]);
          for (int c = 1; c < 8; c++) stepvec[1][c] <= '0;
          op_start <= 1'b1;
          ostate   <= O_WAITOP;
        end
        O_WAITOP: if (op_rvalid) begin
          if (pos == nptot - 16'd1) begin
            dcnt   <= '0;
            ostate <= O_DRAIN;   // Pipeline leeren, DANN layer_done
          end else begin
            pos    <= pos + 16'd1;
            ostate <= O_FEEDW;
          end
        end

        // ---- conv2: pro Position 9 Fenster-Woerter lesen, dann eine Op ----
        O_C2_PRE: begin
          ri        <= '0;
          buf_raddr <= (orow) * 11'd13 + (ocol);        // Tap (kh=0,kw=0)
          ostate    <= O_C2_RDW;
        end
        O_C2_RDW: ostate <= O_C2_RD;                    // 1 Takt BRAM-Latenz
        O_C2_RD: begin
          for (int c = 0; c < 8; c++) stepvec[ri][c] <= buf_rd_data[c*8 +: 8];
          if (ri == 6'd8) begin
            ostate <= O_C2_OP;
          end else begin
            ri        <= ri + 6'd1;                     // naechster Tap
            buf_raddr <= (orow + ((ri + 6'd1) / 6'd3)) * 11'd13
                       + (ocol + ((ri + 6'd1) % 6'd3));
            ostate    <= O_C2_RDW;
          end
        end
        O_C2_OP: begin
          op_start <= 1'b1;                             // op_wbase/bias_base folgen grp
          ostate   <= O_C2_WAIT;
        end
        O_C2_WAIT: if (op_rvalid) begin
          if (orow == 4'd10 && ocol == 4'd10) begin     // letzte Position der Gruppe
            if (grp == 4'd1) begin
              dcnt   <= '0;                              // conv2 fertig -> drain
              ostate <= O_DRAIN;
            end else begin
              dcnt   <= '0;                              // Gruppenwechsel: ERST Pipeline
              ostate <= O_C2_GDRAIN;                     // leeren, DANN rp_start (sonst
            end                                          // verrutscht das Pooling-Raster)
          end else begin
            if (ocol == 4'd10) begin ocol <= '0; orow <= orow + 4'd1; end
            else                     ocol <= ocol + 4'd1;
            ostate <= O_C2_PRE;
          end
        end

        // Drain am conv2-Gruppenwechsel: letzter Gruppe-0-Wert muss durch die
        // Requant-Pipeline, BEVOR rp_start die Pooling-Zaehler nullt.
        O_C2_GDRAIN: if (dcnt == 3'd6) begin
          grp      <= 4'd1;                              // zweite Filtergruppe
          orow     <= '0; ocol <= '0;
          rp_start <= 1'b1;                              // relu_pool fuer Gruppe 1
          ostate   <= O_C2_PRE;
        end else dcnt <= dcnt + 3'd1;

        // WS-conv2-Engine: auf Abschluss warten, dann die gemeinsame Requant/
        // relu_pool-Pipeline ueber O_DRAIN leeren, bevor layer_done Bank/Zeiger
        // umschaltet. (Die O_C2_PRE..GDRAIN-Zustaende oben sind fuer conv2 ungenutzt.)
        O_C2_WS: if (ws_done) begin
          dcnt   <= 3'd0;
          ostate <= O_DRAIN;
        end

        // ---- fc1/fc2: pro Gruppe cf_depth Woerter linear lesen -> 1 Op ----
        O_FC_PRE: begin ri <= '0; buf_raddr <= '0; ostate <= O_FC_RDW; end
        O_FC_RDW: ostate <= O_FC_RD;
        // 16-BREIT: pro Schritt 2 act_buffer-Woerter (ri = gelesenes Wort 0..2*depth-1).
        //  fc1 paart (S, S+25) -> Kanalgruppen 0-7 / 8-15 (act_buffer: 25 Pos ch0-7,
        //    dann 25 Pos ch8-15). fc2 paart (2S, 2S+1) -> fc1-Ausgaben sequentiell.
        O_FC_RD: begin
          for (int c = 0; c < 8; c++) begin
            if (cf_layer == 3'd2) begin                    // fc1
              if (ri < 6'd25) stepvec[ri][c]           <= buf_rd_data[c*8 +: 8];
              else            stepvec[ri - 6'd25][c+8]  <= buf_rd_data[c*8 +: 8];
            end else begin                                 // fc2
              if (~ri[0])     stepvec[ri[5:1]][c]       <= buf_rd_data[c*8 +: 8];
              else            stepvec[ri[5:1]][c+8]     <= buf_rd_data[c*8 +: 8];
            end
          end
          if (ri == ((cf_depth[5:0] << 1) - 6'd1)) begin   // 2*depth Woerter gelesen
            ostate <= O_FC_OP;
          end else begin
            ri        <= ri + 6'd1;
            buf_raddr <= {5'd0, (ri + 6'd1)};              // naechstes Wort
            ostate    <= O_FC_RDW;
          end
        end
        O_FC_OP: begin op_start <= 1'b1; ostate <= O_FC_WAIT; end
        O_FC_WAIT: if (op_rvalid) begin
          op_result_q <= op_result;      // 16 Ausgaben latchen -> 2x8-Readout
          fc_sub      <= 1'b0;
          ostate      <= O_FC_RO;
        end
        // 2x8-Readout: fc1 = zwei Halb-Paesse (Kanaele 0-7, dann 8-15) durch die
        // 8-Lane-Requant/relu-Pipeline; fc2 = ein Pass (Scores latchen). fc_ro_vld
        // (=O_FC_RO) triggert die Requant-Pipeline (eff_op_result = op_result_q-
        // Halbwahl per fc_sub, bias_base folgt grp/fc_sub).
        O_FC_RO: begin
          if (cf_layer == 3'd3) begin                    // fc2: ein Pass, Scores latchen
            if (grp == 4'd0) for (int k = 0; k < 8; k++) fc2_scores[k] <= op_biased[k];
            else begin fc2_scores[8] <= op_biased[0]; fc2_scores[9] <= op_biased[1]; end
            if (grp == last_grp) begin dcnt <= '0; ostate <= O_DRAIN; end
            else begin grp <= grp + 4'd1; ostate <= O_FC_PRE; end
          end else begin                                 // fc1: zwei Halb-Paesse
            if (fc_sub == 1'b0) begin
              fc_sub <= 1'b1;                             // 2. Pass (Kanaele 8-15) naechster Takt
            end else begin
              if (grp == last_grp) begin dcnt <= '0; ostate <= O_DRAIN; end
              else begin grp <= grp + 4'd1; ostate <= O_FC_PRE; end
            end
          end
        end

        // Requant-Pipeline (Stufe1 + Produktregister + relu_pool) leeren,
        // damit der LETZTE gepoolte Wert noch in die RICHTIGE Bank/Adresse
        // geschrieben wird, bevor layer_done Bank/Zeiger umschaltet.
        O_DRAIN: if (dcnt == 3'd6) begin
          layer_done <= 1'b1;
          ostate     <= O_IDLE;
        end else dcnt <= dcnt + 3'd1;

        O_ARG: if (argmax_done) begin
          layer_done <= 1'b1;
          ostate     <= O_IDLE;
        end

        default: ostate <= O_IDLE;
      endcase
    end
  end

endmodule
