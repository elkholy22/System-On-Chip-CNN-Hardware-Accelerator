// ============================================================
// Module:  student_uart_tb
// Purpose: Testbench für student_uart (TL-UL Bus-Wrapper um
//          student_uart_core + generierten Register-Block)
//
// WICHTIG - Voraussetzungen zum Kompilieren:
//   - top_pkg                (vom Betreuer, definiert TL_AW/TL_DW/...)
//   - tlul_pkg                (vom Betreuer, siehe hochgeladene Datei)
//   - student_uart_reg_pkg    (von reggen generiert, "flow reggen.generate")
//   - student_uart_reg_top    (von reggen generiert)
//   - student_uart_core       (bereits verifiziert, siehe student_uart_core_tb)
//
// Solange reggen noch nicht gelaufen ist, lässt sich diese TB
// NICHT kompilieren - das ist normal. Die Registeradressen unten
// (ADDR_*) sind PLATZHALTER, geraten aus der Reihenfolge in der
// student_uart.hjson (txdata, rxdata, status, ctrl) unter der
// Annahme wortweiser, sequentieller Adressvergabe ab 0x0. Sobald
// student_uart_reg_pkg existiert, ersetze die localparams unten
// durch die dort tatsächlich generierten Offsets, z.B. sowas wie
//   student_uart_reg_pkg::STUDENT_UART_TXDATA_OFFSET
// (exakter Name hängt von reggen-Version ab - einfach in der
// generierten .sv/.h Datei nachschauen).
//
// Teststrategie: TL-UL Bus-Functional-Model (BFM) als Host:
//   tlul_write(addr, data) / tlul_read(addr, data_out)
// fahren die a_valid/a_ready- und d_valid/d_ready-Handshakes.
// Damit werden CTRL/TXDATA/STATUS/RXDATA wie ein echter Master
// beschrieben bzw. gelesen - inklusive Loopback tx_serial_o ->
// rx_serial_i, um TX+RX gemeinsam über den Bus zu prüfen.
//
// Ziel ist NICHT, den Core nochmal komplett durchzutesten
// (das leistet student_uart_core_tb bereits), sondern die
// Verdrahtung in student_uart.sv (reg2hw/hw2reg <-> core-Ports)
// auf Vertauschungen/Bitbreitenfehler zu prüfen.
// ============================================================

module student_uart_tb;

  // --------------------------------------------------------
  // Parameter
  // --------------------------------------------------------
  localparam int BAUD_DIV   = 20;            // klein gewählt für schnelle Sim
  localparam int BIT_CYCLES = BAUD_DIV + 1;  // ein Bit dauert baud_div_i+1 Takte im Core
  localparam int POLL_MAX   = 2000;          // max. Anzahl Bus-Polls beim Warten auf ein Statusbit

  // PLATZHALTER-Adressen (siehe Kommentar oben) - anpassen sobald
  // student_uart_reg_pkg generiert ist!
  localparam logic [top_pkg::TL_AW-1:0] ADDR_TXDATA = 'h0;
  localparam logic [top_pkg::TL_AW-1:0] ADDR_RXDATA = 'h4;
  localparam logic [top_pkg::TL_AW-1:0] ADDR_STATUS = 'h8;
  localparam logic [top_pkg::TL_AW-1:0] ADDR_CTRL   = 'hC;

  // Bitpositionen laut student_uart.hjson
  localparam int STATUS_BIT_TX_BUSY  = 0;
  localparam int STATUS_BIT_RX_VALID = 1;
  localparam int CTRL_BIT_ENABLE     = 0;
  // ctrl.baud_div liegt auf bits[31:16]

  localparam int unsigned FULL_SIZE = $clog2(top_pkg::TL_DBW); // Wortgröße für a_size

  // --------------------------------------------------------
  // Signale
  // --------------------------------------------------------
  logic          clk_i;
  logic          rst_ni;

  tlul_pkg::tl_h2d_t tl_i;
  tlul_pkg::tl_d2h_t tl_o;

  logic          rx_serial_i;
  logic          tx_serial_o;

  // --------------------------------------------------------
  // Testbench-interne Hilfssignale (Loopback wie in student_uart_core_tb)
  // --------------------------------------------------------
  logic loopback_en;
  logic rx_line_manual;
  int   errors;

  assign rx_serial_i = loopback_en ? tx_serial_o : rx_line_manual;

  // --------------------------------------------------------
  // DUT (Device Under Test)
  // --------------------------------------------------------
  student_uart dut (
    .clk_i       (clk_i),
    .rst_ni      (rst_ni),
    .tl_i        (tl_i),
    .tl_o        (tl_o),
    .rx_serial_i (rx_serial_i),
    .tx_serial_o (tx_serial_o)
  );

  // --------------------------------------------------------
  // Taktgenerator: 100 MHz -> 10 ns Periode
  // --------------------------------------------------------
  initial clk_i = 1'b0;
  always #5 clk_i = ~clk_i;

  // --------------------------------------------------------
  // Hilfstask: ein Takt weiter, mit kleinem Delta-Delay NACH
  // der Flanke, um Race-Conditions beim Lesen von tl_o/DUT-
  // internen Signalen kurz nach der Flanke zu vermeiden.
  // --------------------------------------------------------
  task automatic tick();
    @(posedge clk_i);
    #1;
  endtask

  // --------------------------------------------------------
  // TL-UL Bus-Functional-Model: Write
  // --------------------------------------------------------
  task automatic tlul_write(input logic [top_pkg::TL_AW-1:0] addr,
                             input logic [top_pkg::TL_DW-1:0] data);
    tl_i.a_valid   <= 1'b1;
    tl_i.a_opcode  <= tlul_pkg::PutFullData;
    tl_i.a_param   <= 3'b0;
    tl_i.a_size    <= FULL_SIZE;
    tl_i.a_source  <= '0;
    tl_i.a_address <= addr;
    tl_i.a_mask    <= '1;
    tl_i.a_data    <= data;
    tl_i.a_user    <= '0;
    tl_i.d_ready   <= 1'b1;
    tick();
    // auf a_ready warten (Slave übernimmt den Request)
    while (!tl_o.a_ready) tick();
    tl_i.a_valid <= 1'b0;
    // auf d_valid warten (Antwort des Slaves)
    while (!tl_o.d_valid) tick();
    if (tl_o.d_error) begin
      $display("[TL-WRITE] Takt=%0t  FAIL: d_error gesetzt bei Adresse 0x%0h", $time, addr);
      errors++;
    end
    tick();
    tl_i.d_ready <= 1'b0;
  endtask

  // --------------------------------------------------------
  // TL-UL Bus-Functional-Model: Read
  // --------------------------------------------------------
  task automatic tlul_read(input  logic [top_pkg::TL_AW-1:0] addr,
                            output logic [top_pkg::TL_DW-1:0] data_out);
    tl_i.a_valid   <= 1'b1;
    tl_i.a_opcode  <= tlul_pkg::Get;
    tl_i.a_param   <= 3'b0;
    tl_i.a_size    <= FULL_SIZE;
    tl_i.a_source  <= '0;
    tl_i.a_address <= addr;
    tl_i.a_mask    <= '1;
    tl_i.a_data    <= '0;
    tl_i.a_user    <= '0;
    tl_i.d_ready   <= 1'b1;
    tick();
    while (!tl_o.a_ready) tick();
    tl_i.a_valid <= 1'b0;
    while (!tl_o.d_valid) tick();
    data_out = tl_o.d_data;
    if (tl_o.d_error) begin
      $display("[TL-READ]  Takt=%0t  FAIL: d_error gesetzt bei Adresse 0x%0h", $time, addr);
      errors++;
    end
    tick();
    tl_i.d_ready <= 1'b0;
  endtask

  // --------------------------------------------------------
  // Hilfstask: auf ein Statusbit über den Bus pollen
  // --------------------------------------------------------
  task automatic wait_status_bit(input  int  bit_idx,
                                  input  bit  want_value,
                                  output bit  success);
    logic [top_pkg::TL_DW-1:0] rd;
    int tries;
    success = 1'b0;
    for (tries = 0; tries < POLL_MAX; tries++) begin
      tlul_read(ADDR_STATUS, rd);
      if (rd[bit_idx] == want_value) begin
        success = 1'b1;
        break;
      end
    end
  endtask

  // --------------------------------------------------------
  // Hilfstask: Byte per Hand auf rx_serial_i "bit-bangen"
  // (identisch zur Core-TB) - für den RX-Standalone/Framing-
  // Error-Test, unabhängig vom TX-Pfad
  // --------------------------------------------------------
  task automatic bitbang_rx_byte(input logic [7:0] data, input bit bad_stop);
    $display("[RX-BITBANG] Takt=%0t  sende Byte=0x%02h (bad_stop=%0d)", $time, data, bad_stop);
    rx_line_manual = 1'b0; // Startbit
    repeat (BIT_CYCLES) tick();
    for (int i = 0; i < 8; i++) begin
      rx_line_manual = data[i];
      repeat (BIT_CYCLES) tick();
    end
    rx_line_manual = bad_stop ? 1'b0 : 1'b1; // Stopbit
    repeat (BIT_CYCLES) tick();
    rx_line_manual = 1'b1;
  endtask

  // --------------------------------------------------------
  // Hilfstask: ein Byte über den Bus senden und die komplette
  // Übertragung (TX fertig, RX-Valid, RXDATA-Inhalt) prüfen.
  // Setzt loopback_en=1 voraus.
  // --------------------------------------------------------
  task automatic send_and_check_via_bus(input logic [7:0] data);
    logic [top_pkg::TL_DW-1:0] rd;
    bit ok;

    $display("[TX-SEND] Takt=%0t  schreibe TXDATA=0x%02h", $time, data);
    tlul_write(ADDR_TXDATA, {24'b0, data});

    wait_status_bit(STATUS_BIT_TX_BUSY, 1'b0, ok);
    if (!ok) begin
      $display("[STATUS-CHECK] Takt=%0t  FAIL: tx_busy wurde nicht rechtzeitig 0", $time);
      errors++;
    end

    wait_status_bit(STATUS_BIT_RX_VALID, 1'b1, ok);
    if (!ok) begin
      $display("[STATUS-CHECK] Takt=%0t  FAIL: rx_valid wurde nicht rechtzeitig 1", $time);
      errors++;
      return;
    end

    tlul_read(ADDR_RXDATA, rd);
    if (rd[7:0] == data) begin
      $display("[RX-CHECK] Takt=%0t  PASS  erwartet=0x%02h erhalten=0x%02h", $time, data, rd[7:0]);
    end else begin
      $display("[RX-CHECK] Takt=%0t  FAIL  erwartet=0x%02h erhalten=0x%02h", $time, data, rd[7:0]);
      errors++;
    end

    // RXDATA-Lesen muss laut hjson (rxdata.re -> rx_clear_i) das Valid-Flag löschen
    tlul_read(ADDR_STATUS, rd);
    if (rd[STATUS_BIT_RX_VALID] == 1'b0) begin
      $display("[STATUS-CHECK] Takt=%0t  PASS  rx_valid nach RXDATA-Lesen korrekt geloescht", $time);
    end else begin
      $display("[STATUS-CHECK] Takt=%0t  FAIL  rx_valid blieb nach RXDATA-Lesen gesetzt", $time);
      errors++;
    end
  endtask

  // --------------------------------------------------------
  // Stimulus
  // --------------------------------------------------------
  initial begin
    logic [top_pkg::TL_DW-1:0] rd;
    bit ok;

    rst_ni         = 1'b0;
    loopback_en    = 1'b1;
    rx_line_manual = 1'b1;
    errors         = 0;

    tl_i.a_valid   = 1'b0;
    tl_i.a_opcode  = tlul_pkg::PutFullData;
    tl_i.a_param   = 3'b0;
    tl_i.a_size    = '0;
    tl_i.a_source  = '0;
    tl_i.a_address = '0;
    tl_i.a_mask    = '0;
    tl_i.a_data    = '0;
    tl_i.a_user    = '0;
    tl_i.d_ready   = 1'b0;

    $display("[RESET] Start");
    repeat (5) tick();
    rst_ni = 1'b1;
    $display("[RESET] Ende");
    repeat (2) tick();

    // --- CTRL konfigurieren: enable=1, baud_div=BAUD_DIV ---
    $display("\n=== TEST 1: CTRL schreiben (enable=1, baud_div=%0d) ===", BAUD_DIV);
    tlul_write(ADDR_CTRL, {BAUD_DIV[15:0], 15'b0, 1'b1});
    tlul_read(ADDR_CTRL, rd);
    if (rd[CTRL_BIT_ENABLE] == 1'b1 && rd[31:16] == BAUD_DIV[15:0]) begin
      $display("[CTRL-CHECK] Takt=%0t  PASS  CTRL=0x%08h", $time, rd);
    end else begin
      $display("[CTRL-CHECK] Takt=%0t  FAIL  CTRL=0x%08h (erwartet enable=1, baud_div=%0d)", $time, rd, BAUD_DIV);
      errors++;
    end

    // --- Test 2: Bus-Loopback mit mehreren Bytes ---
    $display("\n=== TEST 2: TXDATA -> Loopback -> RXDATA (ueber den Bus) ===");
    loopback_en = 1'b1;
    send_and_check_via_bus(8'h00);
    send_and_check_via_bus(8'hFF);
    send_and_check_via_bus(8'h55);
    send_and_check_via_bus(8'hAA);
    send_and_check_via_bus(8'h3C);

    // --- Test 3: RX Standalone (Bit-Banging), Empfang ueber den Bus auslesen ---
    $display("\n=== TEST 3: RX Standalone (Bit-Banging) + Bus-Lesen ===");
    loopback_en = 1'b0;
    bitbang_rx_byte(8'h5A, 1'b0);
    wait_status_bit(STATUS_BIT_RX_VALID, 1'b1, ok);
    if (ok) begin
      tlul_read(ADDR_RXDATA, rd);
      if (rd[7:0] == 8'h5A)
        $display("[RX-CHECK] Takt=%0t  PASS  erwartet=0x5a erhalten=0x%02h", $time, rd[7:0]);
      else begin
        $display("[RX-CHECK] Takt=%0t  FAIL  erwartet=0x5a erhalten=0x%02h", $time, rd[7:0]);
        errors++;
      end
    end else begin
      $display("[RX-CHECK] Takt=%0t  FAIL  rx_valid nie gesetzt", $time);
      errors++;
    end

    // --- Test 4: Framing-Error - darf NICHT als gueltiges Byte ankommen ---
    $display("\n=== TEST 4: Framing-Error (falsches Stopbit) ueber den Bus geprueft ===");
    bitbang_rx_byte(8'h42, 1'b1);
    wait_status_bit(STATUS_BIT_RX_VALID, 1'b1, ok);
    if (!ok) begin
      $display("[STATUS-CHECK] Takt=%0t  PASS  kein rx_valid nach Framing-Error (korrekt verworfen)", $time);
    end else begin
      $display("[STATUS-CHECK] Takt=%0t  FAIL  rx_valid gesetzt trotz Framing-Error", $time);
      errors++;
    end

    // --- Test 5: enable=0 mitten in der Uebertragung, ueber den Bus geschrieben ---
    $display("\n=== TEST 5: CTRL.enable=0 waehrend TX (ueber den Bus) ===");
    loopback_en = 1'b1;
    tlul_write(ADDR_TXDATA, {24'b0, 8'hE7});
    repeat (3) tick(); // irgendwo mitten in der Uebertragung
    tlul_write(ADDR_CTRL, {BAUD_DIV[15:0], 15'b0, 1'b0}); // enable=0
    tick();
    tlul_read(ADDR_STATUS, rd);
    if (rd[STATUS_BIT_TX_BUSY] == 1'b0) begin
      $display("[ENABLE-CHECK] Takt=%0t  PASS  tx_busy sofort 0 nach enable=0", $time);
    end else begin
      $display("[ENABLE-CHECK] Takt=%0t  FAIL  tx_busy=%0d nach enable=0", $time, rd[STATUS_BIT_TX_BUSY]);
      errors++;
    end
    // enable wieder aktivieren fuer eventuelle weitere Tests
    tlul_write(ADDR_CTRL, {BAUD_DIV[15:0], 15'b0, 1'b1});
    repeat (5) tick();

    // --- Zusammenfassung ---
    if (errors == 0)
      $display("\n[SUMMARY] Alle Tests erfolgreich (0 Fehler).");
    else
      $display("\n[SUMMARY] %0d Fehler aufgetreten!", errors);

    $display("[DONE] Simulation fertig.");
    $finish;
  end

endmodule