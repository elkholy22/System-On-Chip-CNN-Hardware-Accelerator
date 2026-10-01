module student_ws_weight_bram #(
    parameter int unsigned N = 16
) (
    input  logic                            clk_i,
    input  logic [2:0]                      tile_addr_i,   // Tap-Tile 0..4
    output logic signed [N-1:0][N-1:0][7:0] wtile_o        // 2048-bit gepackt, signed
);

  localparam int unsigned TILE_BITS = N*N*8;   // 2048 bei N=16
  localparam int unsigned NTILES    = 8;        // >= 5 Tap-Tiles; klein gehalten

  localparam int unsigned CONV1_BASE = 5;       // conv1-Tile-Slot (conv2 belegt 0..4)

  (* ram_style = "block" *) logic [TILE_BITS-1:0] mem [0:NTILES-1];

`ifndef STRINGIFY
  `define STRINGIFY(x) `"x`"
`endif
`ifdef CONV2_WS_MEM_FILE
  initial $readmemh(`STRINGIFY(`CONV2_WS_MEM_FILE), mem);              // Slots 0..4 (conv2), DIREKT
`endif
`ifdef CONV1_WS_MEM_FILE
  initial $readmemh(`STRINGIFY(`CONV1_WS_MEM_FILE), mem, CONV1_BASE);  // Slot 5 (conv1), DIREKT
`endif

  // Ein komplettes Tile pro Lesezugriff (registriert, 1-Takt-Latenz).
  always_ff @(posedge clk_i) wtile_o <= mem[tile_addr_i];

endmodule
