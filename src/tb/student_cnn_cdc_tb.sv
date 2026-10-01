`timescale 1ns/1ps
module student_cnn_cdc_tb;

  logic clk, accel_clk, rst_n, accel_rst_n, irq;
  tlul_pkg::tl_h2d_t bus_h2d, cnn_h2d;
  tlul_pkg::tl_d2h_t bus_d2h, cnn_d2h;

  localparam logic [31:0] ADDR_CTRL   = 32'h0;
  localparam logic [31:0] ADDR_STATUS = 32'h4;
  localparam logic [31:0] ADDR_RESULT = 32'h8;
  localparam logic [31:0] ADDR_PIXEL  = 32'hC;

  // Bus-Takt 50 MHz, Accel-Takt 100 MHz (2:1)
  always begin clk       = 1'b1; #10000; clk       = 1'b0; #10000; end
  always begin accel_clk = 1'b1; #5000;  accel_clk = 1'b0; #5000;  end

  // Accel-Domain-Reset: rst_n (Bus) in accel_clk synchronisieren (async assert,
  // sync deassert) -- Standard-Reset-Synchronizer.
  logic ar_meta;
  always_ff @(posedge accel_clk, negedge rst_n) begin
    if (!rst_n) {accel_rst_n, ar_meta} <= 2'b00;
    else        {accel_rst_n, ar_meta} <= {ar_meta, 1'b1};
  end

  // TL-UL-Host (BFM) auf dem Bus-Takt
  tlul_test_host bus (.clk_i(clk), .rst_no(rst_n), .tl_i(bus_d2h), .tl_o(bus_h2d));

  // CDC: Bus (50 MHz) <-> CNN (100 MHz) ueber das echte async FIFO
  tlul_fifo_async cdc_i (
    .clk_h_i (clk),        .rst_h_ni(rst_n),
    .clk_d_i (accel_clk),  .rst_d_ni(accel_rst_n),
    .tl_h_i  (bus_h2d),    .tl_h_o  (bus_d2h),
    .tl_d_o  (cnn_h2d),    .tl_d_i  (cnn_d2h)
  );

  // DUT auf dem Accel-Takt
  student_cnn DUT (
    .clk_i (accel_clk), .rst_ni(accel_rst_n),
    .tl_i  (cnn_h2d),   .tl_o  (cnn_d2h), .irq_o(irq)
  );

  // Watchdog
  initial begin #(64'd10_000_000_000); $error("TIMEOUT: done nie erreicht"); $finish; end

  logic [7:0] img_vec [0:783];
`ifdef IMAGE_MEM_FILE
  `ifndef STRINGIFY
    `define STRINGIFY(x) `"x`"
  `endif
  initial $readmemh(`STRINGIFY(`IMAGE_MEM_FILE), img_vec);
`else
  initial for (int i = 0; i < 784; i++) img_vec[i] = i & 8'hFF;
`endif

  initial begin
    logic [31:0] rdata, ctot, cl0, cl1, cl2, cl3, ver;
    bus.reset();

    bus.get_word(32'h24, ver);
    $display("### BUILD VERSION = 0x%08h ###", ver);

    $display("--- Bild schreiben (784 Pixel) durch die CDC ---");
    for (int i = 0; i < 784; i++) bus.put_word(ADDR_PIXEL, {24'b0, img_vec[i]});

    $display("--- Start ---");
    bus.put_word(ADDR_CTRL, 32'h1);

    rdata = '0;
    do bus.get_word(ADDR_STATUS, rdata); while (rdata[1] !== 1'b1);
    $display("done erreicht (STATUS=0x%08x)", rdata);

    bus.get_word(ADDR_RESULT, rdata);
    $display("### CNN result digit = %0d ###", rdata[3:0]);

    bus.get_word(32'h10, ctot);
    bus.get_word(32'h14, cl0);
    bus.get_word(32'h18, cl1);
    bus.get_word(32'h1C, cl2);
    bus.get_word(32'h20, cl3);
    $display("### CYCLES total=%0d conv1=%0d conv2=%0d fc1=%0d fc2=%0d argmax=%0d ###",
             ctot, cl0, cl1 - cl0, cl2 - cl1, cl3 - cl2, ctot - cl3);

    $display("### CNN CDC TB DONE ###");
    $finish;
  end

endmodule
