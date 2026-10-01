// SPDX-License-Identifier: SHL-2.1
// SPDX-FileCopyrightText: 2024 RVLab Contributors

module rvlab_bram_main (
  input logic clk_i,
  input logic rst_ni,

  // TL-UL interface
  input  tlul_pkg::tl_h2d_t tl_i,
  output tlul_pkg::tl_d2h_t tl_o
);

  logic        req;
  logic        we;
  logic [15:0] addr;
  logic [31:0] wdata;
  logic [31:0] wmask;
  logic [31:0] rdata;
  logic        rvalid;

  localparam int AddrWidth = 16;  // 16 x 32 bit = 256 kB


  tlul_adapter_sram #(
    .SramAw     (AddrWidth),
    .SramDw     (32),
    .Outstanding(1)
  ) adapter_i (
    .clk_i,
    .rst_ni,

    .tl_i,
    .tl_o,

    .req_o   (req),
    .gnt_i   (1'b1),    // Always grant as only one requester exists
    .we_o    (we),
    .addr_o  (addr),
    .wdata_o (wdata),
    .wmask_o (wmask),
    .rdata_i (rdata),
    .rvalid_i(rvalid),
    .rerror_i(2'b00)
  );

  (* ram_style = "block" *) logic [31:0] mem[0:2**AddrWidth];

  always @(posedge clk_i) begin
    rdata <= '0;
    if (req) begin
      if (we) begin
        // Write access:
        if (wmask[0]) mem[addr][7:0] <= wdata[7:0];
        if (wmask[8]) mem[addr][15:8] <= wdata[15:8];
        if (wmask[16]) mem[addr][23:16] <= wdata[23:16];
        if (wmask[24]) mem[addr][31:24] <= wdata[31:24];
      end

      // Read access:
      rdata <= mem[addr];
    end
  end

  always @(posedge clk_i, negedge rst_ni) begin
    if (!rst_ni) begin
      rvalid <= '0;
    end else begin
      rvalid <= (req && !we);
    end
  end

  `define STRINGIFY(x) `"x`"
  initial begin
    $readmemh(`STRINGIFY(`INIT_MEM_FILE), mem);
  end

endmodule
