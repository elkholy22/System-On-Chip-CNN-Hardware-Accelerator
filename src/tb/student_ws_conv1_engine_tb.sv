`timescale 1ns/1ps
module student_ws_conv1_engine_tb;

  localparam int PSUM_W = 32;

  `include "ws_conv1_gold.svh"    // C1_GP/C1_IMW/C1_OH/C1_OW/C1_DEPTH,
                                   // c1_pbuf, c1_exp, load_conv1_golden()

  // ------------------------------------------------------------------ clock
  logic clk, rst_n;
  always begin clk = 1'b1; #5; clk = 1'b0; #5; end   // 100 MHz TB-Takt

  // ------------------------------------------------------------- DUT signals
  logic                          ws_start, ws_busy, ws_done;
  logic                          ws_rp_start, ws_rvalid, ws_grp;
  logic [10:0]                   ws_buf_raddr;    // conv2-act-Port (hier ungenutzt)
  logic [9:0]                    ws_pbuf_raddr;   // conv1-pbuf-Adresse (registriert)
  logic [71:0]                   pbuf_rd;         // pbuf-Lesewort (registriert)
  logic signed [7:0][PSUM_W-1:0] ws_result;

  // ---------------------------------------------------------- pbuf-Modell
  //  Die Engine registriert pbuf_raddr_o; der Speicher registriert seinen Read
  //  -> pbuf_rd = pbuf[Adresse, die im Vor-Takt an pbuf_raddr_o lag] (1-Takt-
  //  Latenz), EXAKT das vom Sequencer erwartete Read-Modell (wie act_buffer).
  //  1024 tief (pbuf_raddr_o ist 10b); nur 0..675 werden benutzt/gefuellt.
  logic [71:0] pbuf [0:1023];
  always_ff @(posedge clk) pbuf_rd <= pbuf[ws_pbuf_raddr];

  // ------------------------------------------------------------- DUT: Engine
  //  Generische WS-Engine im conv1-Modus. buf_rdata_i (conv2-act_buffer) = 0.
  //  Die INTERNE student_ws_weight_bram laedt Slot CONV1_BASE(5) via
  //  CONV1_WS_MEM_FILE; in conv1-Modus adressiert die Engine tile 5.
  student_ws_conv #(.N(16)) u_e (
      .clk_i        (clk),
      .rst_ni       (rst_n),
      .start_i      (ws_start),
      .mode_i       (1'b0),          // conv1
      .busy_o       (ws_busy),
      .done_o       (ws_done),
      .buf_raddr_o  (ws_buf_raddr),
      .buf_rdata_i  (64'sd0),        // conv2-Quelle abgeklemmt
      .pbuf_raddr_o (ws_pbuf_raddr),
      .pbuf_rdata_i (pbuf_rd),
      .rp_start_o   (ws_rp_start),
      .rvalid_o     (ws_rvalid),
      .grp_o        (ws_grp),
      .result_o     (ws_result)
  );

  // ------------------------------------------------- Scoreboard / Monitor
  //  Passiver getakteter Monitor: zaehlt die rvalid-Pulse. Der conv1-Readout
  //  laeuft strikt in Rasterreihenfolge (rc=1..676, grp_o==0), also ist der
  //  Pulszaehler gn == Positionsindex p (die p-te rvalid-Position liefert
  //  result_o == ac_acc der Position p). Registrierte DUT-Ausgaben werden am
  //  posedge race-frei als "Wert des gerade beendeten Zyklus" gelesen.
  logic monitor_en;
  integer gn;
  logic signed [PSUM_W-1:0] cap [0:C1_GP-1][0:7];

  always @(posedge clk) begin
    if (rst_n && monitor_en && ws_rvalid) begin
      if (gn < C1_GP)
        for (int k = 0; k < 8; k++) cap[gn][k] <= ws_result[k];
      gn <= gn + 1;
    end
  end

  // ----------------------------------------------------------------- Stimulus
  integer errors;
  integer printed;

  task automatic preload_pbuf();
    for (int a = 0; a < 1024; a++) pbuf[a] = 72'd0;         // Reste (676..1023) = 0
    for (int p = 0; p < C1_GP; p++) pbuf[p] = c1_pbuf[p];   // Patch je Position
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
    ws_start   = 1'b0;
    monitor_en = 1'b0;
    gn         = 0;
    errors     = 0;
    printed    = 0;
    load_conv1_golden();

    // Reset (async active-low, wie die Peers)
    rst_n = 1'b0;
    repeat (4) @(posedge clk);
    @(posedge clk); #1; rst_n = 1'b1;
    @(posedge clk); #1;

    // Patch-Bild in die pbuf laden
    preload_pbuf();

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
    if (gn !== C1_GP) begin
      $error("conv1: %0d rvalid-Pulse, erwartet %0d", gn, C1_GP);
      errors = errors + 1;
    end

    for (int p = 0; p < C1_GP; p++) begin
      for (int k = 0; k < 8; k++) begin
        if (cap[p][k] !== c1_exp[p][k]) begin
          if (printed < 40)
            $error("pos %0d (oh=%0d,ow=%0d) ch %0d: got=%0d exp=%0d",
                   p, p / C1_OW, p % C1_OW, k,
                   $signed(cap[p][k]), $signed(c1_exp[p][k]));
          errors  = errors + 1;
          printed = printed + 1;
        end
      end
    end

    if (errors == 0)
      $display("### WS-CONV1 ENGINE TB PASSED (%0d Positionen x 8 Kanaele, 1 Gruppe) ###",
               C1_GP);
    else
      $display("### WS-CONV1 ENGINE TB FAILED (%0d Fehler) ###", errors);
    $finish;
  end

  // -------------------------------------------------------------- Watchdog
  initial begin
    #400000;
    $error("GLOBAL TIMEOUT");
    $finish;
  end

endmodule
