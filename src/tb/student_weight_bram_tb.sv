module student_weight_bram_tb;

  localparam int unsigned N         = 16;
  localparam int unsigned TILE_BITS = N*N*8;
  localparam int unsigned NTILES    = 128;
  localparam int unsigned NINIT     = 108;

  logic clk, rst_n;
  logic we;
  logic [14:0] waddr;
  logic [7:0]  wdata;
  logic [11:0] tile_addr;
  logic signed [N-1:0][N-1:0][7:0] wtile;

  always begin clk = 1'b1; #10000; clk = 1'b0; #10000; end

  student_weight_bram #(.N(N)) dut (
      .clk_i(clk), .rst_ni(rst_n),
      .we_i(we), .waddr_i(waddr), .wdata_i(wdata),
      .tile_addr_i(tile_addr), .wtile_o(wtile)
  );

  logic [TILE_BITS-1:0] ref_mem [0:NTILES-1];

`ifndef STRINGIFY
  `define STRINGIFY(x) `"x`"
`endif
`ifdef WEIGHTS_MEM_FILE
  initial $readmemh(`STRINGIFY(`WEIGHTS_MEM_FILE), ref_mem);
`endif

  int errors = 0;

  task automatic check_tile(input int a, input string name);
    logic [TILE_BITS-1:0] got, exp;
    @(posedge clk); #1;
    tile_addr = 12'(a);
    @(posedge clk); #1;
    got = wtile;
    exp = ref_mem[a];
    if (got !== exp) begin
      $error("FAIL %s: tile %0d mismatch: got[31:0]=%08x exp[31:0]=%08x",
             name, a, got[31:0], exp[31:0]);
      errors++;
    end else $display("PASS %s: tile %0d matches mem file", name, a);
    if (wtile[0][0] !== exp[7:0] || wtile[N-1][N-1] !== exp[TILE_BITS-1 -: 8]) begin
      $error("FAIL %s: byte mapping wrong at tile %0d", name, a);
      errors++;
    end
  endtask

  task automatic check_b2b(input int a1, input int a2);
    logic [TILE_BITS-1:0] got;
    @(posedge clk); #1;
    tile_addr = 12'(a1);
    @(posedge clk); #1;
    tile_addr = 12'(a2);
    got = wtile;
    if (got !== ref_mem[a1]) begin
      $error("FAIL b2b: 1st read tile %0d mismatch", a1);
      errors++;
    end else $display("PASS b2b: tile %0d in cycle 1", a1);
    @(posedge clk); #1;
    got = wtile;
    if (got !== ref_mem[a2]) begin
      $error("FAIL b2b: 2nd read tile %0d mismatch", a2);
      errors++;
    end else $display("PASS b2b: tile %0d in cycle 2", a2);
  endtask

  initial begin
    rst_n = 1'b0; we = 1'b0; waddr = '0; wdata = '0; tile_addr = '0;
    repeat (4) @(posedge clk);
    #1; rst_n = 1'b1;

    if ($isunknown(ref_mem[0])) begin
      $error("FAIL: WEIGHTS_MEM_FILE not defined/loaded - test is void");
      errors++;
    end else $display("PASS mem file loaded, tile0[31:0]=%08x", ref_mem[0][31:0]);

    $display("--- single tile reads ---");
    check_tile(0,         "first ");
    check_tile(1,         "second");
    check_tile(NINIT/2,   "middle");
    check_tile(NINIT-1,   "last  ");

    $display("--- back-to-back reads ---");
    check_b2b(3, 4);
    check_b2b(NINIT-1, 0);
    check_b2b(10, 10);

    if (errors == 0) $display("\n==== ALLE CHECKS BESTANDEN ====");
    else             $display("\n==== %0d CHECK(S) FEHLGESCHLAGEN ====", errors);
    $finish;
  end

endmodule
