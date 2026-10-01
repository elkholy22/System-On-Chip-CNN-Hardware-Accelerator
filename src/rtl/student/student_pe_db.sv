module student_pe_db #(
    parameter  int unsigned ACT_W  = 8,
    parameter  int unsigned W_W    = 8,
    parameter  int unsigned PSUM_W = 32,
    parameter  int unsigned NBANK  = 8,               // Gewichts-Banks (per-wavefront)
    localparam int unsigned BW     = $clog2(NBANK)    // Bank-Tag-Breite (NBANK=8 -> 3)
) (
    input  logic clk_i,
    input  logic rst_ni,

    // Weight load into a SELECTED bank.
    //   load_weight_i : capture weight_i this cycle
    //   load_bank_i   : which bank (0..NBANK-1) to write
    input  logic                  load_weight_i,
    input  logic [BW-1:0]         load_bank_i,
    input  logic signed [W_W-1:0] weight_i,

    // per-wavefront banking: die Bank folgt der Aktivierung durch das
    // Array (statt globalem use_bank). Mit NBANK Banks koennen NBANK Tiles
    // gleichzeitig in-flight sein -> spacing 4 (Feeder-Floor) statt 2N-1. bank_i
    // haengt MIT act_i nach unten. NBANK=8 gibt >=2x Drain-Marge (8*4=32 vs ~2N).
    input  logic [BW-1:0]         bank_i,    // Bank der aktuellen Aktivierung
    output logic [BW-1:0]         bank_o,    // haengt mit act_o nach unten

    // Pipeline-Register leeren (pro Op).
    input  logic                  clear_i,

    // Streaming data in
    input  logic signed [ACT_W-1:0]  act_i,     // activation from ABOVE
    input  logic signed [PSUM_W-1:0] psum_i,    // partial sum from the LEFT

    // Streaming data out (registered)
    output logic signed [ACT_W-1:0]  act_o,     // activation to BELOW
    output logic signed [PSUM_W-1:0] psum_o     // partial sum to the RIGHT
);

    // NBANK stationary weight banks.
    logic signed [W_W-1:0] weight_q [NBANK];

    always_ff @(posedge clk_i, negedge rst_ni) begin
        if (~rst_ni) begin
            for (int b = 0; b < NBANK; b++) weight_q[b] <= '0;
        end else if (load_weight_i) begin
            weight_q[load_bank_i] <= weight_i;
        end
    end

    // Combinational MAC against the ACTIVE bank.
    logic signed [W_W-1:0]    w_active;
    logic signed [PSUM_W-1:0] mac_result;
    always_comb begin
        w_active   = weight_q[bank_i];   // Bank der AKTUELLEN Aktivierung
        mac_result = psum_i + (PSUM_W'(signed'(act_i) * signed'(w_active)));
    end

    // Register the outputs so data advances exactly one PE per cycle.
    always_ff @(posedge clk_i, negedge rst_ni) begin
        if (~rst_ni) begin
            act_o  <= '0;
            psum_o <= '0;
            bank_o <= '0;
        end else if (clear_i) begin
            act_o  <= '0;
            psum_o <= '0;
            bank_o <= '0;
        end else begin
            act_o  <= act_i;       // activation hops DOWN
            psum_o <= mac_result;  // partial sum hops RIGHT (accumulated)
            bank_o <= bank_i;      // Bank haengt mit der Aktivierung nach unten
        end
    end

endmodule
