module student_argmax #(
    parameter int N = 10,    // Anzahl Klassen (<= 16)
    parameter int W = 32     // Score-Breite
) (
    input  logic                clk_i,
    input  logic                rst_ni,
    input  logic                start_i,
    input  logic signed [W-1:0] scores_i [0:N-1],
    output logic [3:0]          digit_o,
    output logic                done_o
);

  logic                busy;
  logic [3:0]          idx;    // aktuell gepruefter Index
  logic [3:0]          best;
  logic signed [W-1:0] maxv;

  always_ff @(posedge clk_i, negedge rst_ni) begin
    if (~rst_ni) begin
      busy    <= 1'b0;
      idx     <= '0;
      best    <= '0;
      maxv    <= '0;
      digit_o <= '0;
      done_o  <= 1'b0;
    end else begin
      done_o <= 1'b0;

      if (start_i) begin
        busy <= 1'b1;
        idx  <= 4'd1;
        best <= 4'd0;
        maxv <= scores_i[0];
      end else if (busy) begin
        if (scores_i[idx] > maxv) begin
          maxv <= scores_i[idx];
          best <= idx;
        end
        if (idx == 4'(N - 1)) begin
          busy    <= 1'b0;
          digit_o <= (scores_i[idx] > maxv) ? idx : best;  // letzten Vergleich einrechnen
          done_o  <= 1'b1;
        end else begin
          idx <= idx + 4'd1;
        end
      end
    end
  end

endmodule
