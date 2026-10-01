module student_rlight_tb;
  logic clk;
  logic rst_n;
  logic [7:0] led;
  tlul_pkg::tl_d2h_t tl_d2h;
  tlul_pkg::tl_h2d_t tl_h2d;

  // ---- Adressen & Modi (Spiegel der Werte im DUT) ----
  localparam logic [31:0] ADDR_PATTERN = 32'h0;
  localparam logic [31:0] ADDR_MODE    = 32'h4;
  localparam logic [31:0] ADDR_SPEED   = 32'h8;
  localparam logic [31:0] ADDR_STATUS  = 32'hC;

  localparam logic [1:0] MODE_RIGHT = 2'd0;
  localparam logic [1:0] MODE_LEFT  = 2'd1;
  localparam logic [1:0] MODE_PIPO  = 2'd2;
  localparam logic [1:0] MODE_STOP  = 2'd3;

  // ---- Takt: 50 MHz (Periode 20 ns) ----
  always begin
    clk = '1; #10000;
    clk = '0; #10000;
  end

  // ---- DUT ----
  student_rlight DUT (
    .clk_i (clk),
    .rst_ni(rst_n),
    .tl_i  (tl_h2d),
    .tl_o  (tl_d2h),
    .led_o (led)
  );

  // ---- Bus-Modell (BFM): spielt die CPU ----
  tlul_test_host bus(
    .clk_i (clk),
    .rst_no(rst_n),
    .tl_i  (tl_d2h),
    .tl_o  (tl_h2d)
  );

  // ---- Zähler für bestandene/fehlgeschlagene Checks ----
  int errors = 0;

  // ---- Hilfs-Task: liest eine Adresse und vergleicht mit Erwartung ----
  task automatic check_reg(input logic [31:0] addr,
                           input logic [31:0] expected,
                           input string       name);
    logic [31:0] rdata;
    bus.get_word(addr, rdata);
    if (rdata !== expected) begin
      $error("FAIL %s: erwartet 0x%08x, gelesen 0x%08x", name, expected, rdata);
      errors++;
    end else begin
      $display("PASS %s = 0x%08x", name, rdata);
    end
  endtask

  // ---- Der Test-Ablauf ----
  initial begin
    logic [31:0] rdata;

    // Textuelle Spur des Lauflichts: druckt bei jeder LED-Änderung
    $monitor("t=%0t  mode=%0d  led=%b", $time, DUT.mode, led);

    bus.reset();

    // === 1) Reset-Werte prüfen ===
    $display("\n--- Reset-Werte ---");
    check_reg(ADDR_PATTERN, 32'h18, "PATTERN reset");  // 0001_1000
    check_reg(ADDR_MODE,    32'h2,  "MODE reset");     // ping-pong
    check_reg(ADDR_SPEED,   32'hA,  "SPEED reset");    // 10

    // === 2) Jedes Register schreiben + zurücklesen ===
    // Erst in STOP, damit das Licht stillsteht und nichts dazwischenfunkt.
    $display("\n--- Register schreiben/lesen ---");
    bus.put_word(ADDR_MODE,    MODE_STOP);
    bus.put_word(ADDR_SPEED,   32'd25);
    bus.put_word(ADDR_PATTERN, 32'hA5);
    check_reg(ADDR_MODE,    32'h3,  "MODE wr/rd");
    check_reg(ADDR_SPEED,   32'd25, "SPEED wr/rd");
    check_reg(ADDR_STATUS,  32'hA5, "STATUS = neues Muster"); // Pattern-Reload
    check_reg(ADDR_PATTERN, 32'hA5, "PATTERN wr/rd");

    // === 3) Jeden Modus laufen lassen (im Wave-View / Monitor sichtbar) ===
    bus.put_word(ADDR_SPEED,   32'd3);          // klein -> schnell sichtbar
    bus.put_word(ADDR_PATTERN, 32'b0000_0001);

    $display("\n--- MODE_LEFT ---");
    bus.put_word(ADDR_MODE, MODE_LEFT);
    bus.wait_cycles(40);

    $display("\n--- MODE_RIGHT ---");
    bus.put_word(ADDR_PATTERN, 32'b1000_0000);
    bus.put_word(ADDR_MODE, MODE_RIGHT);
    bus.wait_cycles(40);

    $display("\n--- MODE_PINGPONG ---");
    bus.put_word(ADDR_PATTERN, 32'b0001_1000);
    bus.put_word(ADDR_MODE, MODE_PIPO);
    bus.wait_cycles(120);

    $display("\n--- MODE_STOP ---");
    bus.put_word(ADDR_MODE, MODE_STOP);
    bus.wait_cycles(20);

    // === 4) Muster/Tempo IM BETRIEB ändern (Kerntest) ===
    $display("\n--- Änderung im Betrieb ---");
    bus.put_word(ADDR_PATTERN, 32'b0000_0001);
    bus.put_word(ADDR_MODE,  MODE_PIPO);
    bus.put_word(ADDR_SPEED, 32'd10); bus.wait_cycles(60);
    bus.put_word(ADDR_SPEED, 32'd20); bus.wait_cycles(60);   // Tempo ändern
    bus.put_word(ADDR_PATTERN, 32'b1000_0001);               // Muster ändern
    bus.wait_cycles(60);

    // === Abschluss ===
    if (errors == 0) $display("\n==== ALLE CHECKS BESTANDEN ====");
    else             $display("\n==== %0d CHECK(S) FEHLGESCHLAGEN ====", errors);

    $finish;
  end

endmodule