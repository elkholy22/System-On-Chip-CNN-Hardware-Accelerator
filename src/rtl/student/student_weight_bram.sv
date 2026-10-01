module student_weight_bram #(
    parameter int unsigned N = 8
) (
    input  logic                            clk_i,
    input  logic                            rst_ni,
    input  logic                            we_i,
    input  logic [14:0]                     waddr_i,
    input  logic [7:0]                      wdata_i,
    input  logic [11:0]                     tile_addr_i,
    output logic signed [N-1:0][N-1:0][7:0] wtile_o
);

  localparam int unsigned TILE_BITS = N*N*8;      // 512 bei N=8, 2048 bei N=16
  localparam int unsigned NTILES    = 128;        // fc nutzt Kacheln 0..107; 128 spart BRAM

  // NUR-LESE-ROM (kein Byte-Schreibport: we_i in student_cnn fest 0). Bei
  // N=16 (2048-bit-Wort) hat der Byte-Write [5:0]*8 nur 64 von 256 Bytes abgedeckt
  // -> mixed-width/partielle Abdeckung verhindert breite BRAM-Inferenz -> Vivado
  // zersplitterte das Wort in ~2048 RAMB18 (UTLZ-1 over-util). Ohne Schreibport
  // wird es -- wie student_ws_weight_bram -- als breites ROM sauber gemappt.
  (* rom_style = "block" *) logic [TILE_BITS-1:0] mem [0:NTILES-1];

`ifndef STRINGIFY
  `define STRINGIFY(x) `"x`"
`endif
`ifdef WEIGHTS_MEM_FILE
  initial $readmemh(`STRINGIFY(`WEIGHTS_MEM_FILE), mem);
`endif

  // Eine komplette Kachel pro Lesezugriff (registriert) -> saubere BRAM-Inferenz.
  // Bit-Layout von wtile_o[r][c] = mem[..][ (r*N+c)*8 +: 8 ] -> direkter Kopie.
  always_ff @(posedge clk_i) begin
    wtile_o <= mem[tile_addr_i];
  end

endmodule
