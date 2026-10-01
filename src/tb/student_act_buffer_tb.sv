module student_act_buffer_tb;

  localparam int unsigned DATA_W = 8;
  localparam int unsigned DEPTH  = 2048;
  localparam int unsigned AW     = $clog2(DEPTH);

  logic clk, rst_n;
  logic bank_sel;
  logic we;
  logic [AW-1:0] waddr;
  logic signed [DATA_W-1:0] wdata;
  logic [AW-1:0] raddr, raddr2;
  logic signed [DATA_W-1:0] rdata, rdata2;

  always begin clk = 1'b1; #10000; clk = 1'b0; #10000; end

  student_act_buffer #(.DATA_W(DATA_W), .DEPTH(DEPTH)) dut (
      .clk_i(clk), .rst_ni(rst_n),
      .bank_sel_i(bank_sel),
      .we_i(we), .waddr_i(waddr), .wdata_i(wdata),
      .raddr_i(raddr),   .rdata_o(rdata),
      .raddr2_i(raddr2), .rdata2_o(rdata2)
  );

  int errors = 0;

  localparam int NADDR = 5;
  int addrs [NADDR] = '{0, 1, 5, 100, DEPTH-1};

  function automatic logic signed [DATA_W-1:0] pat_a(input int i);
    return DATA_W'(8'h11 + 8'(i*17));
  endfunction
  function automatic logic signed [DATA_W-1:0] pat_b(input int i);
    return DATA_W'(8'hB0 - 8'(i*13));
  endfunction

  task automatic write_word(input int a, input logic signed [DATA_W-1:0] d);
    @(posedge clk); #1;
    we = 1'b1; waddr = AW'(a); wdata = d;
    @(posedge clk); #1;
    we = 1'b0;
  endtask

  task automatic check_read2(input int a1, input int a2,
                             input logic signed [DATA_W-1:0] e1,
                             input logic signed [DATA_W-1:0] e2,
                             input string name);
    @(posedge clk); #1;
    raddr  = AW'(a1);
    raddr2 = AW'(a2);
    @(posedge clk); #1;
    if (rdata !== e1) begin
      $error("FAIL %s: port1 addr %0d: got %02x, expected %02x", name, a1, rdata, e1);
      errors++;
    end else $display("PASS %s: port1 addr %0d = %02x", name, a1, rdata);
    if (rdata2 !== e2) begin
      $error("FAIL %s: port2 addr %0d: got %02x, expected %02x", name, a2, rdata2, e2);
      errors++;
    end else $display("PASS %s: port2 addr %0d = %02x", name, a2, rdata2);
  endtask

  task automatic check_latency(input int a_old, input int a_new,
                               input logic signed [DATA_W-1:0] e_old,
                               input logic signed [DATA_W-1:0] e_new);
    @(posedge clk); #1;
    raddr = AW'(a_old); raddr2 = AW'(a_old);
    @(posedge clk); #1;
    raddr = AW'(a_new); raddr2 = AW'(a_new);
    #5000;
    if (rdata !== e_old || rdata2 !== e_old) begin
      $error("FAIL latency: output changed before clock edge (not registered)");
      errors++;
    end else $display("PASS latency: output stable until next edge");
    @(posedge clk); #1;
    if (rdata !== e_new || rdata2 !== e_new) begin
      $error("FAIL latency: got %02x/%02x, expected %02x one cycle after addr",
             rdata, rdata2, e_new);
      errors++;
    end else $display("PASS latency: new data %02x exactly 1 cycle later", rdata);
  endtask

  initial begin
    rst_n = 1'b0; bank_sel = 1'b0;
    we = 1'b0; waddr = '0; wdata = '0; raddr = '0; raddr2 = '0;
    repeat (4) @(posedge clk);
    #1; rst_n = 1'b1;

    $display("--- fill bank0 (bank_sel=0) ---");
    for (int i = 0; i < NADDR; i++) write_word(addrs[i], pat_a(i));

    $display("--- read bank0 via both ports (bank_sel=1) ---");
    @(posedge clk); #1; bank_sel = 1'b1;
    for (int i = 0; i < NADDR; i++)
      check_read2(addrs[i], addrs[NADDR-1-i], pat_a(i), pat_a(NADDR-1-i), "A");

    $display("--- write bank1 while reading bank0 ---");
    for (int i = 0; i < NADDR; i++) begin
      @(posedge clk); #1;
      we = 1'b1; waddr = AW'(addrs[i]); wdata = pat_b(i);
      raddr = AW'(addrs[i]); raddr2 = AW'(addrs[i]);
      @(posedge clk); #1;
      we = 1'b0;
      if (rdata !== pat_a(i) || rdata2 !== pat_a(i)) begin
        $error("FAIL isolation: addr %0d read %02x/%02x, expected %02x (bank0 corrupted?)",
               addrs[i], rdata, rdata2, pat_a(i));
        errors++;
      end else $display("PASS isolation: addr %0d still %02x during bank1 write", addrs[i], rdata);
    end

    $display("--- read bank1 via both ports (bank_sel=0) ---");
    @(posedge clk); #1; bank_sel = 1'b0;
    for (int i = 0; i < NADDR; i++)
      check_read2(addrs[i], addrs[NADDR-1-i], pat_b(i), pat_b(NADDR-1-i), "B");

    $display("--- bank0 unchanged after bank1 writes (bank_sel=1) ---");
    @(posedge clk); #1; bank_sel = 1'b1;
    for (int i = 0; i < NADDR; i++)
      check_read2(addrs[i], addrs[i], pat_a(i), pat_a(i), "A2");

    $display("--- overwrite check ---");
    write_word(addrs[2], 8'sh5A);
    @(posedge clk); #1; bank_sel = 1'b0;
    check_read2(addrs[2], addrs[2], 8'sh5A, 8'sh5A, "OVR");

    $display("--- read latency ---");
    check_latency(addrs[0], addrs[3], pat_b(0), pat_b(3));

    if (errors == 0) $display("\n==== ALLE CHECKS BESTANDEN ====");
    else             $display("\n==== %0d CHECK(S) FEHLGESCHLAGEN ====", errors);
    $finish;
  end

endmodule
