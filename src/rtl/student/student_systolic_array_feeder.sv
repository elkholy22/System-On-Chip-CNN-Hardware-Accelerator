module student_systolic_array_feeder #(
    parameter  int unsigned N      = 8,
    parameter  int unsigned ACT_W  = 8,
    parameter  int unsigned W_W    = 8,
    parameter  int unsigned PSUM_W = 32,
    parameter  int unsigned NBANK  = 8,               // Gewichts-Banks (per-wavefront)
    localparam int unsigned BW     = $clog2(NBANK)    // Bank-Index-Breite (NBANK=8 -> 3)
) (
    input  logic clk_i,
    input  logic rst_ni,

    // Kommando (vom Sequencer)
    input  logic                             op_start_i,
    input  logic [8:0]                        op_nsteps_i,
    input  logic [11:0]                       op_wbase_i,
    output logic                              op_busy_o,
    output logic                              op_rvalid_o,
    output logic signed [N-1:0][PSUM_W-1:0]   op_result_o,

    // Gewichtsquelle (weight_bram, gepackte Kachel)
    output logic [11:0]                       wtile_addr_o,
    input  logic signed [N-1:0][N-1:0][W_W-1:0] wtile_i,

    // Aktivierungsquelle (ein Vektor pro Schritt)
    output logic [8:0]                        astep_o,
    output logic                              av_req_o,
    input  logic signed [N-1:0][ACT_W-1:0]    avec_i,

    // zum Array
    output logic                              a_start_o,
    output logic                              a_mode_o,
    output logic [8:0]                         a_nsteps_o,
    output logic                              a_wload_o,
    output logic [BW-1:0]                     a_lbank_o,
    output logic [BW-1:0]                     a_ubank_o,
    output logic signed [N-1:0][N-1:0][W_W-1:0] a_wtile_o,
    output logic                              a_avalid_o,
    input  logic                              a_ready_i,
    output logic signed [N-1:0][ACT_W-1:0]    a_arow_o,
    input  logic                              a_rvalid_i,
    input  logic signed [N-1:0][PSUM_W-1:0]   a_result_i
);

  typedef enum logic [2:0] {S_IDLE, S_WADDR, S_WLAT, S_WGET, S_FEED, S_WAIT} st_e;
  st_e         st;
  logic [8:0]  step;
  logic [8:0]  nsteps_q;
  logic [11:0] wbase_q;

  assign a_mode_o   = 1'b0;            // accumulate
  assign a_nsteps_o = nsteps_q;
  assign op_busy_o  = (st != S_IDLE);

  always_ff @(posedge clk_i, negedge rst_ni) begin
    if (~rst_ni) begin
      st           <= S_IDLE;
      step         <= '0;
      nsteps_q     <= '0;
      wbase_q      <= '0;
      a_start_o    <= 1'b0;
      a_wload_o    <= 1'b0;
      a_lbank_o    <= '0;
      a_ubank_o    <= '0;
      a_avalid_o   <= 1'b0;
      av_req_o     <= 1'b0;
      op_rvalid_o  <= 1'b0;
      wtile_addr_o <= '0;
      astep_o      <= '0;
      op_result_o  <= '0;
      a_wtile_o    <= '0;
      a_arow_o     <= '0;
    end else begin
      a_start_o   <= 1'b0;
      a_wload_o   <= 1'b0;
      a_avalid_o  <= 1'b0;
      av_req_o    <= 1'b0;
      op_rvalid_o <= 1'b0;

      case (st)
        S_IDLE: if (op_start_i) begin
          nsteps_q  <= op_nsteps_i;
          wbase_q   <= op_wbase_i;
          step      <= '0;
          a_start_o <= 1'b1;
          st        <= S_WADDR;
        end

        S_WADDR: begin
          wtile_addr_o <= wbase_q + step;
          astep_o      <= step;           // FRUEH setzen: avec_i muss beim ersten
                                          // FEED-Takt schon den richtigen Schritt
                                          // zeigen (sonst speist Schritt 0 der
                                          // Folge-Op den stale stepvec der Vor-Op)
          st           <= S_WLAT;         // 1 Takt: Adresse wird gueltig (Register)
        end

        S_WLAT: begin
          st <= S_WGET;                   // 1 Takt: BRAM-Lese-Latenz abwarten
        end

        S_WGET: begin
          a_wtile_o <= wtile_i;           // gueltige Kachel fuer wbase+step
          a_wload_o <= 1'b1;
          a_lbank_o <= step[BW-1:0];      // per-wavefront Bank = step mod NBANK
          a_ubank_o <= step[BW-1:0];      // (NBANK=8 -> step[2:0]); haengt der Welle nach
          st        <= S_FEED;
        end

        S_FEED: begin
          av_req_o   <= 1'b1;
          astep_o    <= step;
          a_arow_o   <= avec_i;
          a_avalid_o <= 1'b1;
          if (a_ready_i) begin
            if (step == nsteps_q - 1) st <= S_WAIT;
            else begin step <= step + 1'b1; st <= S_WADDR; end
          end
        end

        S_WAIT: if (a_rvalid_i) begin
          op_result_o <= a_result_i;
          op_rvalid_o <= 1'b1;
          st          <= S_IDLE;
        end

        default: st <= S_IDLE;
      endcase
    end
  end

endmodule
