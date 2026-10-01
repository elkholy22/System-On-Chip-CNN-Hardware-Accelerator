module student (
  input logic clk_i,
  input logic rst_ni,
  input logic accel_clk_i,   // schnellerer Takt (100 MHz) fuer den CNN-Beschleuniger

  input  top_pkg::userio_board2fpga_t userio_i,
  output top_pkg::userio_fpga2board_t userio_o,

  output logic irq_o,

  input  tlul_pkg::tl_h2d_t tl_device_peri_i,
  output tlul_pkg::tl_d2h_t tl_device_peri_o,
  input  tlul_pkg::tl_h2d_t tl_device_fast_i,
  output tlul_pkg::tl_d2h_t tl_device_fast_o,

  input  tlul_pkg::tl_d2h_t tl_host_i,
  output tlul_pkg::tl_h2d_t tl_host_o
);

  logic [7:0] led;
  logic       uart_tx;
  logic       o_sdin, o_sclk, o_dc, o_res, o_vbat, o_vdd;  // OLED-Pins (dev 4)

  // On-board USB-UART (Nexys Video FT2232 / PROG-UART-Buchse): FPGA sendet auf
  // uart_rx_out, empfaengt auf uart_tx_in. Richtung ist durch die userio-Structs
  // erzwungen (uart_tx_in nur im Input-Struct, uart_rx_out nur im Output-Struct)
  // -> kann nicht vertauscht werden.
  assign userio_o = '{
    led:         led,
    uart_rx_out: uart_tx,   // FPGA-TX -> Host
    oled_sdin:   o_sdin,
    oled_sclk:   o_sclk,
    oled_dc:     o_dc,
    oled_res:    o_res,
    oled_vbat:   o_vbat,
    oled_vdd:    o_vdd,
    default: '0
  };

  // ------------------------------------------------------------------
  // Peri-Bus per Mux auf mehrere Geraete aufteilen (DEV_AW=20 -> 1 MB):
  //   dev 0: rlight       @ 0x10000000
  //   dev 1: irq_ctrl     @ 0x10100000
  //   dev 2: student_cnn  @ 0x10200000
  //   dev 3: student_uart @ 0x10300000
  //   dev 4: student_oled @ 0x10400000
  // ------------------------------------------------------------------
  localparam int N_PERI = 5;
  // WICHTIG: gleiche Array-Richtung wie die Mux-Ports ([NUM-1:0])!
  // "[N_PERI]" (= [0:2]) wuerde beim Port-Mapping POSITIONSWEISE gespiegelt:
  // Mux-dev2 -> dev_d2h[0] usw. -> CNN-Zugriffe landeten bei rlight.
  tlul_pkg::tl_d2h_t dev_d2h [N_PERI-1:0];
  tlul_pkg::tl_h2d_t dev_h2d [N_PERI-1:0];

  student_tlul_mux #(
    .NUM   (N_PERI),
    .DEV_AW(20)
  ) mux_i (
    .clk_i, .rst_ni,
    .tl_host_i  (tl_device_peri_i),
    .tl_host_o  (tl_device_peri_o),
    .tl_device_o(dev_d2h),   // d2h der Geraete -> in den Mux
    .tl_device_i(dev_h2d)    // Mux treibt h2d der Geraete
  );

  // -- Geraet 0: Lauflicht --
  student_rlight rlight_i (
    .clk_i, .rst_ni,
    .tl_i (dev_h2d[0]),
    .tl_o (dev_d2h[0]),
    .led_o(led)
  );

  // -- IRQ-Quellen: LEDs (Ex5) + CNN-done --
  logic        cnn_irq;
  logic [31:0] irq_sources;
  assign irq_sources = { 29'b0,
                         cnn_irq,              // irq[2]: CNN fertig (done)
                         (led[7] | led[6]),    // irq[1]: linke aeussere LEDs
                         (led[1] | led[0]) };  // irq[0]: rechte aeussere LEDs

  // -- Geraet 1: Interrupt-Controller --
  student_irq_ctrl #(.IRQ_MAX(32)) irq_ctrl_i (
    .clk_i, .rst_ni,
    .tl_i (dev_h2d[1]),
    .tl_o (dev_d2h[1]),
    .irq_i(irq_sources),
    .irq_o(irq_o)
  );

  // -- Geraet 2: CNN-Beschleuniger @ 0x10200000 auf EIGENEM schnellerem Takt --
  //  cnn_i laeuft auf accel_clk_i (100 MHz); die TL-UL-Anbindung kreuzt ueber das
  //  echte tlul_fifo_async vom Peri-Bus (clk_i, 50 MHz) -- exakt das DDR-Muster.
  //  Der schnellere Takt multipliziert ALLE Beschleuniger-Zyklen (~2x Wall-Clock),
  //  ohne CPU/Bus-Frequenz zu aendern. In student_cnn_cdc_tb funktional verifiziert.
  logic accel_rst_n, accel_rst_meta;
  always_ff @(posedge accel_clk_i, negedge rst_ni) begin   // Reset-Synchronizer
    if (!rst_ni) {accel_rst_n, accel_rst_meta} <= 2'b00;
    else         {accel_rst_n, accel_rst_meta} <= {accel_rst_meta, 1'b1};
  end

  tlul_pkg::tl_h2d_t cnn_h2d;
  tlul_pkg::tl_d2h_t cnn_d2h;
  tlul_fifo_async cnn_cdc_i (
    .clk_h_i (clk_i),       .rst_h_ni(rst_ni),          // Host = Peri-Bus (50 MHz)
    .clk_d_i (accel_clk_i), .rst_d_ni(accel_rst_n),     // Device = CNN (100 MHz)
    .tl_h_i  (dev_h2d[2]),  .tl_h_o  (dev_d2h[2]),
    .tl_d_o  (cnn_h2d),     .tl_d_i  (cnn_d2h)
  );

  logic cnn_irq_accel, cnn_irq_meta;
  student_cnn cnn_i (
    .clk_i (accel_clk_i), .rst_ni(accel_rst_n),
    .tl_i  (cnn_h2d),     .tl_o  (cnn_d2h),
    .irq_o (cnn_irq_accel)
  );
  // done-IRQ von accel_clk zurueck auf clk_i synchronisieren (Level, 2-FF).
  always_ff @(posedge clk_i, negedge rst_ni) begin
    if (!rst_ni) {cnn_irq, cnn_irq_meta} <= 2'b00;
    else         {cnn_irq, cnn_irq_meta} <= {cnn_irq_meta, cnn_irq_accel};
  end

  // -- Geraet 3: UART @ 0x10300000 (on-board FT2232 / PROG-UART) --
  student_uart uart_i (
    .clk_i, .rst_ni,
    .tl_i        (dev_h2d[3]),
    .tl_o        (dev_d2h[3]),
    .rx_serial_i (userio_i.uart_tx_in),   // Host-TX -> FPGA-RX
    .tx_serial_o (uart_tx)                // -> userio_o.uart_rx_out
  );

  // -- Geraet 4: OLED-GPIO @ 0x10400000 (SSD1306; Protokoll in SW) --
  student_oled_gpio oled_i (
    .clk_i, .rst_ni,
    .tl_i     (dev_h2d[4]),
    .tl_o     (dev_d2h[4]),
    .oled_sdin(o_sdin), .oled_sclk(o_sclk), .oled_dc(o_dc),
    .oled_res (o_res),  .oled_vbat(o_vbat), .oled_vdd(o_vdd)
  );

  // -- DMA-Host bleibt am fast/host-Bus --
  student_dma dma_i (
    .clk_i, .rst_ni,
    .tl_o (tl_device_fast_o),
    .tl_i (tl_device_fast_i),
    .tl_host_o,
    .tl_host_i
  );

endmodule
