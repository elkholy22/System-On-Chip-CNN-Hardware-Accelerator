`timescale 1ns/1ps
module student_ws_conv2_engine_tb;

  localparam int PSUM_W = 32;

  `include "ws_engine_gold.svh"   // EN/ENTILE/EP/EIMW/EOH/EOW/EACT_DEPTH,
                                   // eng_act, eng_y, load_engine_golden()

  // ------------------------------------------------------------------ clock
  logic clk, rst_n;
  always begin clk = 1'b1; #5; clk = 1'b0; #5; end   // 100 MHz TB-Takt

  // ------------------------------------------------------------- DUT signals
  logic                          ws_start, ws_busy, ws_done;
  logic                          ws_rp_start, ws_rvalid, ws_grp;
  logic [10:0]                   ws_buf_raddr;
  logic signed [63:0]            buf_rdata;
  logic signed [7:0][PSUM_W-1:0] ws_result;

  // act_buffer Schreibseite (TB laedt bank0 vor; Engine liest bank0)
  logic        ab_bank_sel;
  logic        ab_we;
  logic [10:0] ab_waddr;
  logic signed [63:0] ab_wdata;

  // --------------------------------------------------- geteilter act_buffer
  //  bank_sel=1 -> Schreib-Bank ist bank1, LESE-Bank ist bank0 (wie conv2:
  //  buf_bank=cf_layer[0]=1). Vorladen daher mit bank_sel=0 (schreibt bank0),
  //  danach bank_sel=1 fuer den Lauf (Engine liest bank0, 1-Takt-Read-Latenz).
  student_act_buffer #(.DATA_W(64), .DEPTH(2048)) u_actbuf (
      .clk_i    (clk),
      .rst_ni   (rst_n),
      .bank_sel_i(ab_bank_sel),
      .we_i     (ab_we),
      .waddr_i  (ab_waddr),
      .wdata_i  (ab_wdata),
      .raddr_i  (ws_buf_raddr),     // von der Engine getrieben
      .rdata_o  (buf_rdata)
  );

  // ------------------------------------------------------------- DUT: Engine
  //  Default-Parameter = echte conv2-Masse (N=16, NPOS=121, SPACING=2, NTILE=5,
  //  OH=OW=11, IMW=13, DRAIN_CYC=36, INJ_LEAD=1). Keine Gewichts-Ports: die
  //  interne student_ws_weight_bram laedt conv2_ws_tiles.mem via CONV2_WS_MEM_FILE.
  student_ws_conv2 u_ws (
      .clk_i      (clk),
      .rst_ni     (rst_n),
      .start_i    (ws_start),
      .busy_o     (ws_busy),
      .done_o     (ws_done),
      .buf_raddr_o(ws_buf_raddr),
      .buf_rdata_i(buf_rdata),
      .rp_start_o (ws_rp_start),
      .rvalid_o   (ws_rvalid),
      .grp_o      (ws_grp),
      .result_o   (ws_result)
  );

  // ------------------------------------------------- Scoreboard / Monitor
  //  Passiver getakteter Monitor: zaehlt die rvalid-Pulse je Gruppe. Der
  //  Readout laeuft strikt in Rasterreihenfolge rc=0..120 (grp0 zuerst, dann
  //  grp1), also ist der Pulszaehler == Positionsindex p. Registrierte DUT-
  //  Ausgaben werden am posedge race-frei als "Wert des gerade beendeten
  //  Zyklus" gelesen (Standard-Sampling registrierter Ausgaenge).
  logic monitor_en;
  integer g0n, g1n;
  logic signed [PSUM_W-1:0] cap0 [0:EP-1][0:7];   // grp0: Kanaele 0..7
  logic signed [PSUM_W-1:0] cap1 [0:EP-1][0:7];   // grp1: Kanaele 8..15

  always @(posedge clk) begin      // TB-Monitor (plain always: g0n/g1n auch im initial gesetzt)
    if (rst_n && monitor_en && ws_rvalid) begin
      if (ws_grp == 1'b0) begin
        if (g0n < EP)
          for (int k = 0; k < 8; k++) cap0[g0n][k] <= ws_result[k];
        g0n <= g0n + 1;
      end else begin
        if (g1n < EP)
          for (int k = 0; k < 8; k++) cap1[g1n][k] <= ws_result[k];
        g1n <= g1n + 1;
      end
    end
  end

  // ----------------------------------------------------------------- Stimulus
  integer errors;
  integer printed;

  task automatic preload_actbuf();
    // bank_sel=0 -> Schreibpfad geht in bank0; ein Wort/Takt.
    ab_bank_sel = 1'b0;
    for (int a = 0; a < EACT_DEPTH; a++) begin
      ab_we    = 1'b1;
      ab_waddr = a[10:0];
      ab_wdata = eng_act[a];
      @(posedge clk); #1;
    end
    ab_we    = 1'b0;
    ab_waddr = '0;
    ab_wdata = '0;
    // Engine liest bank0 -> Lese-Bank auf bank0 stellen (bank_sel=1).
    ab_bank_sel = 1'b1;
    @(posedge clk); #1;
  endtask

  task automatic wait_done();
    integer guard;
    guard = 0;
    while (!ws_done) begin
      @(posedge clk); #1;
      guard = guard + 1;
      if (guard > 20000) begin
        $error("TIMEOUT: done_o kam nicht (guard=%0d)", guard);
        return;
      end
    end
  endtask

  initial begin
    // Init
    ws_start    = 1'b0;
    monitor_en  = 1'b0;
    ab_bank_sel = 1'b0;
    ab_we       = 1'b0;
    ab_waddr    = '0;
    ab_wdata    = '0;
    g0n         = 0;
    g1n         = 0;
    errors      = 0;
    printed     = 0;
    load_engine_golden();

    // Reset (async active-low, wie die Peers)
    rst_n = 1'b0;
    repeat (4) @(posedge clk);
    @(posedge clk); #1; rst_n = 1'b1;
    @(posedge clk); #1;

    // Aktivierungsbild vorladen
    preload_actbuf();

    // Engine starten (1-Takt-Puls), Monitor scharf schalten
    monitor_en = 1'b1;
    ws_start   = 1'b1;
    @(posedge clk); #1;
    ws_start   = 1'b0;

    if (!ws_busy)
      $display("NOTE: busy_o nach start noch 0 (evtl. 1 Takt spaeter) -- ok.");

    // Auf Abschluss warten
    wait_done();
    @(posedge clk); #1;   // die letzten Monitor-Captures settlen lassen

    // --------------------------------------------------------- Vergleich
    if (g0n !== EP) begin
      $error("grp0: %0d rvalid-Pulse, erwartet %0d", g0n, EP);
      errors = errors + 1;
    end
    if (g1n !== EP) begin
      $error("grp1: %0d rvalid-Pulse, erwartet %0d", g1n, EP);
      errors = errors + 1;
    end

    for (int p = 0; p < EP; p++) begin
      for (int k = 0; k < 8; k++) begin
        // grp0 -> Ausgabekanal k
        if (cap0[p][k] !== eng_y[p][k]) begin
          if (printed < 40)
            $error("grp0 pos %0d (oh=%0d,ow=%0d) ch %0d: got=%0d exp=%0d",
                   p, p / EOW, p % EOW, k,
                   $signed(cap0[p][k]), $signed(eng_y[p][k]));
          errors  = errors + 1;
          printed = printed + 1;
        end
        // grp1 -> Ausgabekanal 8+k
        if (cap1[p][k] !== eng_y[p][8 + k]) begin
          if (printed < 40)
            $error("grp1 pos %0d (oh=%0d,ow=%0d) ch %0d: got=%0d exp=%0d",
                   p, p / EOW, p % EOW, 8 + k,
                   $signed(cap1[p][k]), $signed(eng_y[p][8 + k]));
          errors  = errors + 1;
          printed = printed + 1;
        end
      end
    end

    if (errors == 0)
      $display("### WS-CONV2 ENGINE TB PASSED (%0d Positionen x %0d Kanaele, 2 Gruppen) ###",
               EP, EN);
    else
      $display("### WS-CONV2 ENGINE TB FAILED (%0d Fehler) ###", errors);
    $finish;
  end

  // -------------------------------------------------------------- Watchdog
  initial begin
    #300000;
    $error("GLOBAL TIMEOUT");
    $finish;
  end

endmodule
