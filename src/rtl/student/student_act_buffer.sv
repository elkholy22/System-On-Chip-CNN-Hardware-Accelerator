module student_act_buffer #(
    parameter int unsigned DATA_W = 8,    // int8 activations
    parameter int unsigned DEPTH  = 2048  // max elements per bank (>= largest map)
) (
    input  logic clk_i,
    input  logic rst_ni,

    // which physical bank is the WRITE bank (other = READ bank)
    input  logic bank_sel_i,

    // WRITE port (sequential stream from relu_pool)
    input  logic                     we_i,
    input  logic [$clog2(DEPTH)-1:0] waddr_i,
    input  logic signed [DATA_W-1:0] wdata_i,

    // READ port 1 (random access: im2col / fc / conv2 tap A)
    input  logic [$clog2(DEPTH)-1:0] raddr_i,
    output logic signed [DATA_W-1:0] rdata_o,

    // READ port 2 (conv2 tap B -> ermoeglicht SPACING=1: beide Tap-Woerter
    // einer Position im selben Takt lesen). Liest dieselbe Read-Bank wie Port 1.
    input  logic [$clog2(DEPTH)-1:0] raddr2_i,
    output logic signed [DATA_W-1:0] rdata2_o
);

    // Two banks, JE mit Spiegel-Kopie fuer den 2. Read-Port. So ist jedes Array
    // 1-Write-1-Read (saubere Simple-Dual-Port-BRAM-Inferenz). EIN gemeinsames
    // Array mit 2 Read-Adressen + Write laesst sich NICHT als BRAM abbilden ->
    // Vivado explodierte es sonst in ~2048 RAMB18 (UTLZ-1 over-util). Die Kopie
    // haelt identische Daten (gleicher Write) -> Port 2 liest denselben Inhalt.
    (* ram_style = "block" *) logic signed [DATA_W-1:0] bank0   [DEPTH];
    (* ram_style = "block" *) logic signed [DATA_W-1:0] bank1   [DEPTH];
    (* ram_style = "block" *) logic signed [DATA_W-1:0] bank0_b [DEPTH];
    (* ram_style = "block" *) logic signed [DATA_W-1:0] bank1_b [DEPTH];

    // WRITE geht in die gewaehlte Write-Bank UND deren Spiegel (identische Daten).
    always_ff @(posedge clk_i) begin
        if (we_i) begin
            if (bank_sel_i) begin bank1[waddr_i] <= wdata_i; bank1_b[waddr_i] <= wdata_i; end
            else            begin bank0[waddr_i] <= wdata_i; bank0_b[waddr_i] <= wdata_i; end
        end
    end

    // READ aus der ANDEREN Bank: Port 1 aus der Haupt-, Port 2 aus der Spiegel-
    // Kopie (registriert, 1 Takt). Jedes Array: 1W/1R -> saubere BRAM.
    always_ff @(posedge clk_i) begin
        if (bank_sel_i) begin
            rdata_o  <= bank0[raddr_i];     // write=1 -> read bank0
            rdata2_o <= bank0_b[raddr2_i];
        end else begin
            rdata_o  <= bank1[raddr_i];     // write=0 -> read bank1
            rdata2_o <= bank1_b[raddr2_i];
        end
    end

endmodule