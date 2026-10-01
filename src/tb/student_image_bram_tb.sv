module student_image_bram_tb;

  localparam int N_PIX    = 784;
  localparam int N_STREAM = 810;

  logic       clk, rst_n;
  logic       we;
  logic [9:0] waddr;
  logic [7:0] wdata;
  logic       start;
  logic [7:0] rdata;
  logic       valid, busy;

  always begin clk = 1'b1; #10000; clk = 1'b0; #10000; end

  student_image_bram dut (
      .clk_i  (clk),
      .rst_ni (rst_n),
      .we_i   (we),
      .waddr_i(waddr),
      .wdata_i(wdata),
      .start_i(start),
      .rdata_o(rdata),
      .valid_o(valid),
      .busy_o (busy)
  );

  int errors = 0;

  function automatic logic [7:0] pat(input int img, input int a);
    if (img == 0) return 8'((a*7 + 3) & 255);
    else          return 8'((a*13 + 11) & 255);
  endfunction

  task automatic write_image(input int img);
    for (int a = 0; a < N_PIX; a++) begin
      @(posedge clk); #1;
      we    = 1'b1;
      waddr = 10'(a);
      wdata = pat(img, a);
    end
    @(posedge clk); #1;
    we = 1'b0;
  endtask

  task automatic run_stream(input int img, input string name);
    int k, waitcnt, mism;
    logic [7:0] exp;
    @(posedge clk); #1; start = 1'b1;
    @(posedge clk); #1; start = 1'b0;
    @(negedge clk);
    if (busy !== 1'b1) begin
      $error("%s: busy_o=%b direkt nach start, erwartet 1", name, busy);
      errors++;
    end
    waitcnt = 0;
    while (valid !== 1'b1) begin
      waitcnt++;
      if (waitcnt > 20) begin
        $error("%s: kein valid_o nach start", name);
        errors++;
        return;
      end
      @(negedge clk);
    end
    k = 0; mism = 0;
    while (valid === 1'b1) begin
      exp = (k < N_PIX) ? pat(img, k) : 8'd0;
      if (rdata !== exp) begin
        if (mism < 5)
          $error("%s: Pixel %0d: rdata=0x%02x, erwartet 0x%02x", name, k, rdata, exp);
        mism++;
        errors++;
      end
      if (busy !== 1'b1) begin
        $error("%s: busy_o=0 waehrend Stream (k=%0d)", name, k);
        errors++;
      end
      k++;
      if (k > N_STREAM + 5) break;
      @(negedge clk);
    end
    if (mism > 5) $display("   (%0d weitere Wert-Fehler unterdrueckt)", mism - 5);
    if (k !== N_STREAM) begin
      $error("%s: Streamlaenge %0d, erwartet %0d", name, k, N_STREAM);
      errors++;
    end else if (mism == 0) begin
      $display("PASS %s: %0d Pixel, Reihenfolge und Werte korrekt", name, k);
    end
    repeat (3) @(negedge clk);
    if (busy !== 1'b0) begin
      $error("%s: busy_o haengt nach Streamende", name);
      errors++;
    end
    if (valid !== 1'b0) begin
      $error("%s: valid_o haengt nach Streamende", name);
      errors++;
    end
  endtask

  initial begin
    rst_n = 1'b0; we = 1'b0; waddr = '0; wdata = '0; start = 1'b0;
    repeat (4) @(posedge clk);
    #1; rst_n = 1'b1;
    repeat (2) @(negedge clk);
    if ((busy !== 1'b0) || (valid !== 1'b0)) begin
      $error("nach Reset: busy=%b valid=%b, erwartet 0/0", busy, valid);
      errors++;
    end else begin
      $display("PASS Reset: busy_o/valid_o = 0");
    end

    write_image(0);
    repeat (2) @(negedge clk);
    if (busy !== 1'b0) begin
      $error("busy_o high nach reinem Schreiben");
      errors++;
    end
    run_stream(0, "Stream 1 (Muster A)");

    repeat (5) @(posedge clk);
    run_stream(0, "Stream 2 (Muster A, erneut)");

    write_image(1);
    run_stream(1, "Stream 3 (Muster B)");

    if (errors == 0) $display("\n==== ALLE CHECKS BESTANDEN ====");
    else             $display("\n==== %0d CHECK(S) FEHLGESCHLAGEN ====", errors);
    $finish;
  end

endmodule
