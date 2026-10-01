// ============================================================
// Module:  student_uart_core_tb
// Purpose: Testbench für student_uart_core (TX/RX UART-Logik)
//
// Teststrategie:
//   1) Loopback-Test:  tx_serial_o wird direkt auf rx_serial_i
//      zurückgeführt. Damit prüft man TX und RX gleichzeitig -
//      wenn RX das gesendete Byte korrekt zurückliefert, war
//      die TX-Wellenform automatisch auch richtig.
//   2) RX-Standalone-Test: rx_serial_i wird per "Bit-Banging"
//      (Task bitbang_rx_byte) manuell mit exaktem Timing
//      beschrieben, unabhängig vom TX-Teil des DUT.
//   3) Framing-Error-Test: bewusst falsches Stopbit -> Byte
//      muss laut Kommentar im DUT still verworfen werden
//      (rx_valid_o bleibt low).
//   4) enable_i-Abbruch: enable_i geht mitten in der Über-
//      tragung auf 0 -> TX muss sofort in Idle zurückspringen.
//   5) Back-to-back: zwei Bytes direkt hintereinander senden.
// ============================================================

module student_uart_core_tb;

  // --------------------------------------------------------
  // Parameter
  // --------------------------------------------------------
  localparam int BAUD_DIV   = 20;            // klein gewählt für schnelle Sim
  localparam int BIT_CYCLES = BAUD_DIV + 1;  // ein Bit dauert baud_div_i+1 Takte im DUT
  localparam int RX_TIMEOUT = 15 * BIT_CYCLES + 100; // Sicherheitsfenster fürs Warten auf rx_valid_o

  // --------------------------------------------------------
  // Signale
  // --------------------------------------------------------
  logic        clk_i;
  logic        rst_ni;
  logic        enable_i;
  logic [15:0] baud_div_i;

  logic [7:0]  tx_data_i;
  logic        tx_start_i;
  logic        tx_busy_o;
  logic        tx_serial_o;

  logic        rx_serial_i;
  logic [7:0]  rx_data_o;
  logic        rx_valid_o;
  logic        rx_clear_i;

  // --------------------------------------------------------
  // Testbench-interne Hilfssignale
  // --------------------------------------------------------
  logic loopback_en;     // 1 = rx_serial_i <= tx_serial_o, 0 = manuelles Bit-Banging
  logic rx_line_manual;  // Pegel für manuelles Bit-Banging (Ruhelage = 1)
  int   errors;

  assign rx_serial_i = loopback_en ? tx_serial_o : rx_line_manual;

  logic [7:0] test_bytes [0:5];

  // --------------------------------------------------------
  // DUT (Device Under Test)
  // --------------------------------------------------------
  student_uart_core dut (
    .clk_i       (clk_i),
    .rst_ni      (rst_ni),
    .enable_i    (enable_i),
    .baud_div_i  (baud_div_i),
    .tx_data_i   (tx_data_i),
    .tx_start_i  (tx_start_i),
    .tx_busy_o   (tx_busy_o),
    .tx_serial_o (tx_serial_o),
    .rx_serial_i (rx_serial_i),
    .rx_data_o   (rx_data_o),
    .rx_valid_o  (rx_valid_o),
    .rx_clear_i  (rx_clear_i)
  );

  // --------------------------------------------------------
  // Taktgenerator: 100 MHz -> 10 ns Periode
  // --------------------------------------------------------
  initial clk_i = 1'b0;
  always #5 clk_i = ~clk_i;

  // --------------------------------------------------------
  // Hilfstask: ein Takt weiter, aber mit kleinem Delta-Delay
  // NACH der Flanke. Sonst gibt es eine klassische Race-
  // Condition: direkt nach @(posedge clk_i) sind die
  // Non-Blocking-Updates im DUT (z.B. tx_state) noch nicht
  // durchgesickert, man würde also den alten Wert lesen.
  // --------------------------------------------------------
  task automatic tick();
    @(posedge clk_i);
    #1;
  endtask

  // --------------------------------------------------------
  // Hilfstask: ein Byte über tx_start_i/tx_data_i senden
  // und warten bis tx_busy_o wieder low ist
  // --------------------------------------------------------
  task automatic send_tx_byte(input logic [7:0] data);
    tick();
    tx_data_i  <= data;
    tx_start_i <= 1'b1;
    $display("[TX-SEND] Takt=%0t  Byte=0x%02h", $time, data);
    tick();
    tx_start_i <= 1'b0;
    wait (tx_busy_o == 1'b0);
    $display("[TX-DONE] Takt=%0t  Byte=0x%02h fertig gesendet", $time, data);
  endtask

  // --------------------------------------------------------
  // Hilfstask: Byte per Hand auf rx_serial_i "bit-bangen"
  // (Start-, 8 Daten- (LSB zuerst), Stopbit)
  // bad_stop=1 -> Stopbit wird bewusst falsch (0) gesendet,
  // um einen Framing-Error zu provozieren
  // --------------------------------------------------------
  task automatic bitbang_rx_byte(input logic [7:0] data, input bit bad_stop);
    $display("[RX-BITBANG] Takt=%0t  sende Byte=0x%02h (bad_stop=%0d)", $time, data, bad_stop);
    // Startbit
    rx_line_manual = 1'b0;
    repeat (BIT_CYCLES) tick();
    // Datenbits, LSB zuerst
    for (int i = 0; i < 8; i++) begin
      rx_line_manual = data[i];
      repeat (BIT_CYCLES) tick();
    end
    // Stopbit
    rx_line_manual = bad_stop ? 1'b0 : 1'b1;
    repeat (BIT_CYCLES) tick();
    rx_line_manual = 1'b1; // zurück in Ruhelage
  endtask

  // --------------------------------------------------------
  // Hilfstask: auf rx_valid_o warten und Ergebnis prüfen
  // expect_valid=1 -> es wird ein gültiges Byte erwartet
  // expect_valid=0 -> es darf KEIN Byte ankommen (z.B. Framing-Error)
  // --------------------------------------------------------
  task automatic check_rx_result(input logic [7:0] expected, input bit expect_valid);
    int timeout;
    timeout = 0;
    while (!rx_valid_o && timeout < RX_TIMEOUT) begin
      tick();
      timeout++;
    end

    if (expect_valid) begin
      if (rx_valid_o && rx_data_o == expected) begin
        $display("[RX-CHECK] Takt=%0t  PASS  erwartet=0x%02h erhalten=0x%02h", $time, expected, rx_data_o);
      end else begin
        $display("[RX-CHECK] Takt=%0t  FAIL  erwartet=0x%02h erhalten=0x%02h valid=%0d", $time, expected, rx_data_o, rx_valid_o);
        errors++;
      end
      tick();
      rx_clear_i <= 1'b1;
      tick();
      rx_clear_i <= 1'b0;
    end else begin
      if (!rx_valid_o) begin
        $display("[RX-CHECK] Takt=%0t  PASS  (kein Byte erwartet, Frame korrekt verworfen)", $time);
      end else begin
        $display("[RX-CHECK] Takt=%0t  FAIL  unerwartetes Byte empfangen: 0x%02h", $time, rx_data_o);
        errors++;
        tick();
        rx_clear_i <= 1'b1;
        tick();
        rx_clear_i <= 1'b0;
      end
    end
  endtask

  // --------------------------------------------------------
  // Stimulus
  // --------------------------------------------------------
  initial begin
    rst_ni         = 1'b0;
    enable_i       = 1'b0;
    baud_div_i     = BAUD_DIV;
    tx_data_i      = 8'h00;
    tx_start_i     = 1'b0;
    rx_clear_i     = 1'b0;
    loopback_en    = 1'b1;
    rx_line_manual = 1'b1;
    errors         = 0;

    test_bytes[0] = 8'h00;
    test_bytes[1] = 8'hFF;
    test_bytes[2] = 8'h55;
    test_bytes[3] = 8'hAA;
    test_bytes[4] = 8'h3C;
    test_bytes[5] = 8'h81;

    $display("[RESET] Start");
    repeat (5) tick();
    rst_ni   = 1'b1;
    enable_i = 1'b1;
    $display("[RESET] Ende");
    repeat (2) tick();

    // --- Test 1: Loopback (TX -> RX) ---
    $display("\n=== TEST 1: Loopback (TX -> RX) ===");
    loopback_en = 1'b1;
    for (int i = 0; i < 6; i++) begin
      send_tx_byte(test_bytes[i]);
      check_rx_result(test_bytes[i], 1'b1);
    end

    // --- Test 2: RX Standalone (Bit-Banging) ---
    $display("\n=== TEST 2: RX Standalone (Bit-Banging) ===");
    loopback_en = 1'b0;
    bitbang_rx_byte(8'h5A, 1'b0);
    check_rx_result(8'h5A, 1'b1);

    bitbang_rx_byte(8'hC3, 1'b0);
    check_rx_result(8'hC3, 1'b1);

    // --- Test 3: Framing-Error Erkennung ---
    $display("\n=== TEST 3: Framing-Error Erkennung (falsches Stopbit) ===");
    bitbang_rx_byte(8'h42, 1'b1);
    check_rx_result(8'h00, 1'b0);

    // --- Test 4: enable_i mitten in der Übertragung deaktivieren ---
    $display("\n=== TEST 4: enable_i Abbruch waehrend TX ===");
    loopback_en = 1'b1;
    tick();
    tx_data_i  <= 8'hE7;
    tx_start_i <= 1'b1;
    tick();
    tx_start_i <= 1'b0;
    repeat (3) tick(); // irgendwo mitten im Startbit/ersten Datenbit
    enable_i <= 1'b0;
    tick();
    if (tx_busy_o == 1'b0 && tx_serial_o == 1'b1) begin
      $display("[ENABLE-CHECK] Takt=%0t  PASS: TX sofort in Ruhelage nach enable_i=0", $time);
    end else begin
      $display("[ENABLE-CHECK] Takt=%0t  FAIL: tx_busy_o=%0d tx_serial_o=%0d", $time, tx_busy_o, tx_serial_o);
      errors++;
    end
    enable_i <= 1'b1;
    repeat (5) tick();

    // --- Test 5: Back-to-back Übertragung ---
    $display("\n=== TEST 5: Back-to-back Uebertragung ===");
    loopback_en = 1'b1;
    send_tx_byte(8'h11);
    check_rx_result(8'h11, 1'b1);
    send_tx_byte(8'h22);
    check_rx_result(8'h22, 1'b1);

    repeat (10) tick();

    // --- Zusammenfassung ---
    if (errors == 0)
      $display("\n[SUMMARY] Alle Tests erfolgreich (0 Fehler).");
    else
      $display("\n[SUMMARY] %0d Fehler aufgetreten!", errors);

    $display("[DONE] Simulation fertig.");
    $finish;
  end

  // --------------------------------------------------------
  // Monitor: meldet automatisch jede steigende Flanke von
  // rx_valid_o (ähnlich zum print_patch-Monitor der Vorlage)
  // --------------------------------------------------------
  logic rx_valid_prev;
  always_ff @(posedge clk_i) rx_valid_prev <= rx_valid_o;

  always @(posedge clk_i) begin
    if (rx_valid_o && !rx_valid_prev)
      $display("[MONITOR] Takt=%0t  rx_valid_o gesetzt, rx_data_o=0x%02h", $time, rx_data_o);
  end

endmodule