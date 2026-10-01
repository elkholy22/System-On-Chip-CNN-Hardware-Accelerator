module student_dma_tb;

  localparam int MEM_WORDS = 1024;

  localparam logic [31:0] ADDR_STATUS   = 32'h00;
  localparam logic [31:0] ADDR_NOW_DADR = 32'h04;
  localparam logic [31:0] ADDR_CMD      = 32'h08;
  localparam logic [31:0] ADDR_LENGTH   = 32'h0C;
  localparam logic [31:0] ADDR_SRC_ADR  = 32'h10;
  localparam logic [31:0] ADDR_DST_ADR  = 32'h14;

  localparam logic [1:0] ST_IDLE   = 2'd0;
  localparam logic [1:0] ST_DESC   = 2'd1;
  localparam logic [1:0] ST_MEMSET = 2'd2;
  localparam logic [1:0] ST_MEMCPY = 2'd3;

  localparam int SRC_W    = 64;
  localparam int DSTA_W   = 128;
  localparam int DSTB_W   = 192;
  localparam int DSTC_W   = 512;
  localparam int DSTD_W   = 768;
  localparam int DSTE_W   = 800;
  localparam int DESC_A_W = 16;
  localparam int DESC_B_W = 24;
  localparam int DESC_C_W = 28;
  localparam int DESC_D_W = 32;
  localparam int DESC_E_W = 36;
  localparam logic [31:0] DESC_A_ADDR = DESC_A_W * 4;
  localparam logic [31:0] DESC_B_ADDR = DESC_B_W * 4;
  localparam logic [31:0] DESC_C_ADDR = DESC_C_W * 4;
  localparam logic [31:0] DESC_D_ADDR = DESC_D_W * 4;
  localparam logic [31:0] DESC_E_ADDR = DESC_E_W * 4;
  localparam logic [31:0] FILL_B = 32'h5A5A5A5A;
  localparam logic [31:0] FILL_C = 32'h0F0FF0F0;
  localparam logic [31:0] FILL_E = 32'hF00DF00D;

  logic clk;
  logic rst_n;

  tlul_pkg::tl_h2d_t tl_cfg_h2d;
  tlul_pkg::tl_d2h_t tl_cfg_d2h;
  tlul_pkg::tl_h2d_t tl_mem_h2d;
  tlul_pkg::tl_d2h_t tl_mem_d2h;

  int errors = 0;

  always begin
    clk = '1; #10000;
    clk = '0; #10000;
  end

  student_dma dut (
    .clk_i     (clk),
    .rst_ni    (rst_n),
    .tl_i      (tl_cfg_h2d),
    .tl_o      (tl_cfg_d2h),
    .tl_host_i (tl_mem_d2h),
    .tl_host_o (tl_mem_h2d)
  );

  tlul_test_host bus (
    .clk_i (clk),
    .rst_no(rst_n),
    .tl_i  (tl_cfg_d2h),
    .tl_o  (tl_cfg_h2d)
  );

  logic [31:0] mem   [0:MEM_WORDS-1];
  logic [31:0] expmem[0:MEM_WORDS-1];

  logic                       mem_dv;
  tlul_pkg::tl_d_op_e         mem_dop;
  logic [31:0]                mem_dd;
  logic [top_pkg::TL_SZW-1:0] mem_dsize;
  logic [top_pkg::TL_AIW-1:0] mem_dsource;
  logic                       mem_aready;

  assign mem_aready = !mem_dv || tl_mem_h2d.d_ready;

  assign tl_mem_d2h = '{
    d_valid : mem_dv,
    d_opcode: mem_dop,
    d_param : '0,
    d_size  : mem_dsize,
    d_source: mem_dsource,
    d_sink  : '0,
    d_data  : mem_dd,
    d_user  : '0,
    d_error : 1'b0,
    a_ready : mem_aready
  };

  always @(posedge clk) begin
    if (!rst_n) begin
      mem_dv <= 1'b0;
    end else begin
      if (mem_dv && tl_mem_h2d.d_ready) mem_dv <= 1'b0;
      if (tl_mem_h2d.a_valid && mem_aready) begin
        mem_dv      <= 1'b1;
        mem_dsize   <= tl_mem_h2d.a_size;
        mem_dsource <= tl_mem_h2d.a_source;
        if (tl_mem_h2d.a_address[31:12] != '0) begin
          $error("MEM: host access outside 4KB window: 0x%08x", tl_mem_h2d.a_address);
          errors++;
        end
        if (tl_mem_h2d.a_opcode == tlul_pkg::Get) begin
          mem_dop <= tlul_pkg::AccessAckData;
          mem_dd  <= mem[tl_mem_h2d.a_address[11:2]];
        end else begin
          mem_dop <= tlul_pkg::AccessAck;
          mem_dd  <= '0;
          for (int b = 0; b < 4; b++) begin
            if (tl_mem_h2d.a_mask[b])
              mem[tl_mem_h2d.a_address[11:2]][8*b +: 8] <= tl_mem_h2d.a_data[8*b +: 8];
          end
        end
      end
    end
  end

  logic [1:0] dut_status;
  assign dut_status = dut.status;

  logic [1:0] status_prev;
  logic [1:0] status_hist[$];

  always @(posedge clk) begin
    if (!rst_n) begin
      status_prev <= ST_IDLE;
    end else if (dut_status != status_prev) begin
      status_hist.push_back(dut_status);
      status_prev <= dut_status;
    end
  end

  task automatic check_reg(input logic [31:0] addr,
                           input logic [31:0] expected,
                           input string       name);
    logic [31:0] rdata;
    bus.get_word(addr, rdata);
    if (rdata !== expected) begin
      $error("FAIL %s: expected 0x%08x, read 0x%08x", name, expected, rdata);
      errors++;
    end else begin
      $display("PASS %s = 0x%08x", name, rdata);
    end
  endtask

  task automatic wait_idle(input string name);
    logic [31:0] st;
    int n;
    n = 0;
    do begin
      bus.get_word(ADDR_STATUS, st);
      n++;
      if (n > 300) begin
        $error("FAIL %s: timeout waiting for IDLE (status=%0d)", name, st);
        errors++;
        return;
      end
    end while (st != 32'd0);
    $display("PASS %s: DMA back to IDLE (after %0d status poll(s))", name, n);
  endtask

  task automatic check_hist(input logic [1:0] busy_code, input string name);
    if (status_hist.size() != 3 ||
        status_hist[0] !== ST_DESC ||
        status_hist[1] !== busy_code ||
        status_hist[2] !== ST_IDLE) begin
      $error("FAIL %s: bad status sequence (%0d entries)", name, status_hist.size());
      foreach (status_hist[k]) $display("   hist[%0d] = %0d", k, status_hist[k]);
      errors++;
    end else begin
      $display("PASS %s: status 0 -> 1 -> %0d -> 0", name, busy_code);
    end
    status_hist.delete();
  endtask

  task automatic check_mem_image(input string name);
    int bad;
    bad = 0;
    for (int i = 0; i < MEM_WORDS; i++) begin
      if (mem[i] !== expmem[i]) begin
        if (bad < 5)
          $error("FAIL %s: mem[0x%03x] = 0x%08x, expected 0x%08x",
                 name, i*4, mem[i], expmem[i]);
        bad++;
      end
    end
    if (bad != 0) begin
      $error("FAIL %s: %0d mismatching word(s) in memory image", name, bad);
      errors++;
    end else begin
      $display("PASS %s: full memory image OK (%0d words incl. guards)", name, MEM_WORDS);
    end
  endtask

  task automatic check_host_quiet(input int ncyc, input string name);
    int cnt;
    cnt = 0;
    repeat (ncyc) begin
      @(posedge clk);
      if (tl_mem_h2d.a_valid) cnt++;
    end
    if (cnt != 0) begin
      $error("FAIL %s: host port issued %0d request(s)", name, cnt);
      errors++;
    end else begin
      $display("PASS %s: host port quiet for %0d cycles", name, ncyc);
    end
  endtask

  task automatic check_memset_prefix(input int dst_w, input int nwords,
                                     input logic [31:0] fill, input string name);
    int k;
    k = 0;
    while (k < nwords && mem[dst_w+k] === fill) k++;
    for (int i = k; i < nwords; i++) begin
      if (mem[dst_w+i] !== expmem[dst_w+i]) begin
        $error("FAIL %s: word 0x%03x is neither fill nor untouched (0x%08x)",
               name, (dst_w+i)*4, mem[dst_w+i]);
        errors++;
        return;
      end
    end
    if (k == 0 || k == nwords) begin
      $error("FAIL %s: stop was not mid-operation (k=%0d of %0d)", name, k, nwords);
      errors++;
    end else begin
      $display("PASS %s: memset aborted after %0d/%0d words, no overrun", name, k, nwords);
    end
    for (int i = 0; i < k; i++) expmem[dst_w+i] = fill;
  endtask

  function automatic void exp_memcpy(input int src_w, input int dst_w, input int nwords);
    for (int i = 0; i < nwords; i++) expmem[dst_w+i] = expmem[src_w+i];
  endfunction

  function automatic void exp_memset(input logic [31:0] val, input int dst_w, input int nwords);
    for (int i = 0; i < nwords; i++) expmem[dst_w+i] = val;
  endfunction

  task automatic init_mem();
    for (int i = 0; i < MEM_WORDS; i++) begin
      mem[i]    = 32'h10000000 + i;
      expmem[i] = 32'h10000000 + i;
    end
    for (int i = 0; i < 16; i++) mem[SRC_W+i] = 32'hA5A50000 + 32'h101*i;
    mem[DESC_A_W+0] = 32'd1;  mem[DESC_A_W+1] = 32'd64;
    mem[DESC_A_W+2] = SRC_W*4;  mem[DESC_A_W+3] = DSTA_W*4;
    mem[DESC_B_W+0] = 32'd0;  mem[DESC_B_W+1] = 32'd32;
    mem[DESC_B_W+2] = FILL_B;   mem[DESC_B_W+3] = DSTB_W*4;
    mem[DESC_C_W+0] = 32'd0;  mem[DESC_C_W+1] = 32'd512;
    mem[DESC_C_W+2] = FILL_C;   mem[DESC_C_W+3] = DSTC_W*4;
    mem[DESC_D_W+0] = 32'd1;  mem[DESC_D_W+1] = 32'd16;
    mem[DESC_D_W+2] = SRC_W*4;  mem[DESC_D_W+3] = DSTD_W*4;
    mem[DESC_E_W+0] = 32'd0;  mem[DESC_E_W+1] = 32'd512;
    mem[DESC_E_W+2] = FILL_E;   mem[DESC_E_W+3] = DSTE_W*4;
    for (int i = 0; i < MEM_WORDS; i++) expmem[i] = mem[i];
  endtask

  initial begin
    #2_000_000_000;
    $error("GLOBAL TIMEOUT");
    errors++;
    $display("\n==== %0d CHECK(S) FEHLGESCHLAGEN ====", errors);
    $finish;
  end

  initial begin
    logic [31:0] rdata;

    init_mem();
    bus.reset();

    $display("\n--- Reset values ---");
    check_reg(ADDR_STATUS,   32'h0, "STATUS reset");
    check_reg(ADDR_LENGTH,   32'h0, "LENGTH reset");
    check_reg(ADDR_NOW_DADR, 32'h0, "NOW_DADR reset");
    status_hist.delete();

    $display("\n--- Test 1: memcpy 64 bytes 0x100 -> 0x200 ---");
    bus.put_word(ADDR_NOW_DADR, DESC_A_ADDR);
    bus.get_word(ADDR_STATUS, rdata);
    if (rdata == 32'd0) begin
      $error("FAIL memcpy: DMA not busy right after start");
      errors++;
    end else begin
      $display("PASS memcpy: busy after start (status=%0d)", rdata);
    end
    wait_idle("memcpy");
    check_reg(ADDR_NOW_DADR, DESC_A_ADDR, "memcpy NOW_DADR readback");
    check_reg(ADDR_SRC_ADR, SRC_W*4  + 64, "memcpy SRC_ADR final");
    check_reg(ADDR_DST_ADR, DSTA_W*4 + 64, "memcpy DST_ADR final");
    check_hist(ST_MEMCPY, "memcpy status sequence");
    exp_memcpy(SRC_W, DSTA_W, 16);
    check_mem_image("memcpy");

    $display("\n--- Test 2: memset 32 bytes @ 0x300 ---");
    bus.put_word(ADDR_NOW_DADR, DESC_B_ADDR);
    wait_idle("memset");
    check_reg(ADDR_LENGTH, 32'h0, "memset LENGTH final");
    check_reg(ADDR_SRC_ADR, FILL_B, "memset SRC_ADR = fill value");
    check_reg(ADDR_DST_ADR, DSTB_W*4 + 32 - 4, "memset DST_ADR final");
    check_hist(ST_MEMSET, "memset status sequence");
    exp_memset(FILL_B, DSTB_W, 8);
    check_mem_image("memset");

    $display("\n--- Test 3: NOW_DADR write while busy ---");
    bus.put_word(ADDR_NOW_DADR, DESC_C_ADDR);
    wait (dut_status == ST_MEMSET);
    bus.put_word(ADDR_NOW_DADR, DESC_D_ADDR);
    check_reg(ADDR_NOW_DADR, DESC_D_ADDR, "NOW_DADR reg takes value while busy");
    wait_idle("memset-long");
    check_host_quiet(60, "ignored NOW_DADR: no restart");
    check_hist(ST_MEMSET, "memset-long status sequence");
    exp_memset(FILL_C, DSTC_W, 128);
    check_mem_image("memset-long");

    $display("\n--- Test 4: CMD.stop ---");
    bus.put_word(ADDR_NOW_DADR, DESC_E_ADDR);
    wait (dut_status == ST_MEMSET);
    bus.wait_cycles(10);
    bus.put_word(ADDR_CMD, 32'h1);
    check_reg(ADDR_STATUS, 32'h0, "STATUS idle right after stop");
    check_host_quiet(50, "stop: host port quiet");
    check_hist(ST_MEMSET, "stop status sequence");
    check_memset_prefix(DSTE_W, 128, FILL_E, "stop partial memset");
    check_mem_image("stop");

    $display("\n--- Test 5: memcpy after stop ---");
    bus.put_word(ADDR_NOW_DADR, DESC_D_ADDR);
    wait_idle("memcpy-2");
    check_hist(ST_MEMCPY, "memcpy-2 status sequence");
    exp_memcpy(SRC_W, DSTD_W, 4);
    check_mem_image("memcpy-2");

    if (errors == 0) $display("\n==== ALLE CHECKS BESTANDEN ====");
    else             $display("\n==== %0d CHECK(S) FEHLGESCHLAGEN ====", errors);

    $finish;
  end

endmodule
