module student_cnn_tb;

  logic clk, rst_n;
  logic irq;
  tlul_pkg::tl_d2h_t tl_d2h;
  tlul_pkg::tl_h2d_t tl_h2d;

  localparam logic [31:0] ADDR_CTRL   = 32'h0;   // [0]=start [1]=clear
  localparam logic [31:0] ADDR_STATUS = 32'h4;   // [0]=busy  [1]=done
  localparam logic [31:0] ADDR_RESULT = 32'h8;   // [3:0]=digit
  localparam logic [31:0] ADDR_PIXEL  = 32'hC;   // write -> ein Pixel (auto-inc)

  // 50 MHz
  always begin clk = 1'b1; #10000; clk = 1'b0; #10000; end

  // ---- DUT ----
  student_cnn DUT (
    .clk_i (clk),
    .rst_ni(rst_n),
    .tl_i  (tl_h2d),
    .tl_o  (tl_d2h),
    .irq_o (irq)
  );

  // ---- Bus-Modell (spielt die CPU) ----
  tlul_test_host bus (
    .clk_i (clk),
    .rst_no(rst_n),
    .tl_i  (tl_d2h),
    .tl_o  (tl_h2d)
  );

  // ---- Timeout-Watchdog: bricht sauber ab, falls done nie kommt ----
  initial begin
    #(64'd5_000_000_000);   // 5 ms Sim-Zeit (conv2+fc real -> laenger)
    $error("TIMEOUT: student_cnn hat done nicht erreicht (haengt vermutlich)");
    $finish;
  end

  // ---- Testbild: aus image.mem (Golden) oder Rampen-Fallback ----
  // image.mem enthaelt 784 int8-Pixel (Hex), erzeugt von golden_model.py.
  // Ohne Define laeuft der alte Rampen-Test (rein strukturell).
  logic [7:0] img_vec [0:783];
`ifdef IMAGE_MEM_FILE
  `ifndef STRINGIFY
    `define STRINGIFY(x) `"x`"
  `endif
  initial $readmemh(`STRINGIFY(`IMAGE_MEM_FILE), img_vec);
`else
  initial for (int i = 0; i < 784; i++) img_vec[i] = i & 8'hFF;  // Rampe
`endif

  // ---- Test-Ablauf ----
  initial begin
    logic [31:0] rdata;
    logic [31:0] ctot, cl0, cl1, cl2, cl3;
    logic [31:0] ver;
    integer      fd;
    bus.reset();

    // Staleness-Guard pruefen (0x24 -> 0xC10000NN)
    bus.get_word(32'h24, ver);
    $display("### BUILD VERSION = 0x%08h ###", ver);

    // Testbild schreiben (784 Pixel, auto-inkrementierendes PIXEL-Register)
    $display("--- Bild schreiben (784 Pixel) ---");
    for (int i = 0; i < 784; i++) begin
      bus.put_word(ADDR_PIXEL, {24'b0, img_vec[i]});
    end

    // Accelerator starten
    $display("--- Start ---");
    bus.put_word(ADDR_CTRL, 32'h1);

    // Auf done pollen (STATUS bit 1)
    rdata = '0;
    do begin
      bus.get_word(ADDR_STATUS, rdata);
    end while (rdata[1] !== 1'b1);
    $display("done erreicht (STATUS=0x%08x)", rdata);

    // Ergebnis lesen
    bus.get_word(ADDR_RESULT, rdata);
    $display("### CNN result digit = %0d ###", rdata[3:0]);

    // Per-Schicht-Zyklen (Profiling): kumulative Snapshots -> Differenzen
    bus.get_word(32'h10, ctot);   // cycle_count  (total)
    bus.get_word(32'h14, cl0);    // cycle_layer0 (conv1)
    bus.get_word(32'h18, cl1);    // cycle_layer1 (conv2)
    bus.get_word(32'h1C, cl2);    // cycle_layer2 (fc1)
    bus.get_word(32'h20, cl3);    // cycle_layer3 (fc2)
    $display("### CYCLES total=%0d conv1=%0d conv2=%0d fc1=%0d fc2=%0d argmax=%0d ###",
             ctot, cl0, cl1 - cl0, cl2 - cl1, cl3 - cl2, ctot - cl3);

    // Ergebnis in Datei schreiben -> compare.py vergleicht mit expected.txt
    fd = $fopen("student_cnn_result.txt", "w");
    $fwrite(fd, "%0d\n", rdata[3:0]);
    $fclose(fd);

    $display("### CNN TB DONE ###");
    $finish;
  end

endmodule
