module student_relu_pool #(
    parameter int unsigned IN_W      = 32,   // incoming psum width (array PSUM_W)
    parameter int unsigned OUT_W     = 8,    // outgoing activation width (int8)
    parameter int unsigned IMG_W_MAX = 26,   // MAX feature-map width
    parameter int unsigned IMG_H_MAX = 26    // MAX feature-map height
) (
    input  logic clk_i,
    input  logic rst_ni,

    // Reset the spatial position counter for a new feature map.
    input  logic start_i,

    // Laufzeit-Bildmaße (conv1=26, conv2=11). <= IMG_W_MAX/IMG_H_MAX.
    input  logic [5:0] img_w_i,
    input  logic [5:0] img_h_i,

    // Modes
    input  logic relu_en_i,
    input  logic pool_en_i,

    // Requantize controls
    input  logic signed [31:0] requant_multiplier_i,
    input  logic        [5:0]  requant_shift_i,

    // Input pixel stream (one pixel per position for THIS channel).
    input  logic                    valid_i,
    output logic                    ready_o,
    input  logic signed [IN_W-1:0]  pixel_i,

    // Output pooled/activated pixel stream.
    input  logic                    ready_i,
    output logic                    valid_o,
    output logic signed [OUT_W-1:0] act_o
);

    localparam int unsigned POOL_W = IMG_W_MAX/2;

    // ---- output register (VOR erster Nutzung deklariert) ----
    logic                    out_pending_q;
    logic signed [OUT_W-1:0] out_data_q;

    // ---- handshake ----
    logic input_fire, output_fire;
    assign input_fire  = valid_i && ready_o;
    assign output_fire = valid_o && ready_i;
    assign ready_o     = ~out_pending_q || output_fire;

    // ---- requant, in 2 Stufen gesplittet (Timing: DSP-Produkt wird registriert) ----
    // Stufe A: Produkt + Rundung (+0.5 LSB, wie PyTorch)
    function automatic logic signed [63:0] requant_product
            (input logic signed [IN_W-1:0] psum,
             input logic signed [31:0]     multiplier,
             input logic [5:0]             shift);
        logic signed [63:0] product;
    begin
        product = psum * multiplier;
        if (shift != 0) product = product + (64'sd1 <<< (shift - 1));
        return product;
    end
    endfunction

    // Stufe B: Shift + ReLU + Saettigung
    function automatic logic signed [OUT_W-1:0] shift_relu_sat
            (input logic signed [63:0] product,
             input logic [5:0]         shift,
             input logic               relu_en);
        logic signed [63:0] shifted;
        logic signed [OUT_W-1:0] result;
    begin
        shifted = product >>> shift;
        if (relu_en && (shifted < 0)) shifted = 0;
        if (shifted > 127)            result = 8'sd127;
        else if (shifted < -128)      result = -8'sd128;
        else                          result = shifted[OUT_W-1:0];
        return result;
    end
    endfunction

    // ---- Pipeline-Stufe: Produkt registrieren (DSP-Ausgangsregister),
    //  fire um 1 Takt verzoegert -> Pooling/Zaehler laufen synchron dazu.
    logic signed [63:0] prod_q;
    logic               fire_q;

    function automatic logic signed [OUT_W-1:0] max2
            (input logic signed [OUT_W-1:0] a, input logic signed [OUT_W-1:0] b);
        max2 = (a > b) ? a : b;
    endfunction

    // ---- spatial counters (auf MAX dimensioniert) ----
    logic [$clog2(IMG_W_MAX)-1:0] col_q;
    logic [$clog2(IMG_H_MAX)-1:0] row_q;

    // ---- pooling state ----
    logic signed [OUT_W-1:0] hmax_buf [POOL_W];
    logic signed [OUT_W-1:0] h_pair_q;

    assign valid_o = out_pending_q;
    assign act_o   = out_data_q;

    // Pipeline-Stufe A: Produkt + Rundung registrieren
    always_ff @(posedge clk_i, negedge rst_ni) begin
        if (~rst_ni) begin
            prod_q <= '0;
            fire_q <= 1'b0;
        end else begin
            fire_q <= input_fire;
            if (input_fire)
                prod_q <= requant_product(pixel_i, requant_multiplier_i, requant_shift_i);
        end
    end

    // Stufe B kombinatorisch aus dem registrierten Produkt
    logic signed [OUT_W-1:0] q_pix;
    always_comb begin
        q_pix = shift_relu_sat(prod_q, requant_shift_i, relu_en_i);
    end

    always_ff @(posedge clk_i, negedge rst_ni) begin
        if (~rst_ni) begin
            col_q         <= '0;
            row_q         <= '0;
            h_pair_q      <= '0;
            out_pending_q <= 1'b0;
            out_data_q    <= '0;
            for (int k = 0; k < POOL_W; k++) hmax_buf[k] <= '0;
        end else begin
            if (output_fire) out_pending_q <= 1'b0;

            if (start_i) begin
                col_q <= '0;
                row_q <= '0;
            end else if (fire_q) begin

                if (!pool_en_i) begin
                    out_data_q    <= q_pix;
                    out_pending_q <= 1'b1;
                end else begin
                    logic is_odd_col; logic is_odd_row; logic signed [OUT_W-1:0] hmax;
                    is_odd_col = col_q[0];
                    is_odd_row = row_q[0];

                    if (!is_odd_col) begin
                        h_pair_q <= q_pix;
                    end else begin
                        hmax = max2(h_pair_q, q_pix);
                        if (!is_odd_row) begin
                            hmax_buf[col_q >> 1] <= hmax;
                        end else begin
                            out_data_q    <= max2(hmax_buf[col_q >> 1], hmax);
                            out_pending_q <= 1'b1;
                        end
                    end
                end

                // advance position (row-major), Laufzeit-Maße
                if (col_q == img_w_i - 6'd1) begin
                    col_q <= '0;
                    row_q <= (row_q == img_h_i - 6'd1) ? '0 : (row_q + 1);
                end else begin
                    col_q <= col_q + 1;
                end
            end
        end
    end

endmodule
