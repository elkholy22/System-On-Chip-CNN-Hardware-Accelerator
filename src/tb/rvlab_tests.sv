// SPDX-License-Identifier: SHL-2.1
// SPDX-FileCopyrightText: 2024 RVLab Contributors

module rvlab_tests (
         jtag_master jtag,
  input  logic       clk_i
);

  import rvlab_tap_pkg::*;

  rvlab_test_utils tu (jtag);

  // Test IDCODE
  // -----------

  task test_idcode();
    bit [31:0] idcode_read;
    int errcnt;

    errcnt = 0;
    tu.test_start("test_idcode");

    jtag.reset();
    jtag.set_ir(IDCODE);

    jtag.cycle_dr_32(idcode_read, '0);

    if (idcode_read != IdcodeValue) begin
      $error("IDCODE incorrect!");
      errcnt++;
    end

    tu.test_end("test_idcode", errcnt);
  endtask


  // Test RISC-V Debug Module
  // ------------------------

  task test_dtmcs();
    int errcnt;
    rvlab_tap_pkg::dtmcs_t dtmcs;

    tu.test_start("test_dtmcs");

    jtag.reset();
    jtag.set_ir(DTMCSR);
    jtag.cycle_dr_32(dtmcs, '0);
    $display("version: %d, dmistat: %d, idle: %d, abits: %d", dtmcs.version, dtmcs.dmistat, dtmcs.idle, dtmcs.abits);

    if(dtmcs.version != 1) begin
      $error("debug spec 0.13 not supported (dtmcs.version != 1).");
      errcnt++;
    end

    if(dtmcs.dmistat != 0) begin
      $error("dmistat = %d, indicating error.", dtmcs.dmistat);
      errcnt++;
    end

    if(dtmcs.idle != 1) begin
      $error("dtmcs.idle expected 1, read %d", dtmcs.idle);
      errcnt++;
    end

    tu.test_end("test_dtmcs", errcnt);
  endtask

  // Load Software via RV Debug Module
  // ---------------------------------

  task test_sw(input string sw_mem_filename);
    int errcnt;
    bit [31:0] rdata;
    localparam bit [15:0] DPC = 16'h7b1; // Debug PC

    errcnt = 0;

    tu.test_start("test_sw");


    jtag.reset();

    tu.dm_start(errcnt);

    tu.dm_halt(errcnt);
  
    $display("Loading memory...");
    tu.dm_load_delta(sw_mem_filename, errcnt);
    $display("Starting program...");
    tu.dm_write_cpureg(DPC, 32'h00000080, errcnt);
    tu.dm_resume(errcnt);
    
    $display("Waiting for program to finish...");
    tu.wait_prog(errcnt);
    
    tu.test_end("test_sw", errcnt);
  endtask
endmodule
