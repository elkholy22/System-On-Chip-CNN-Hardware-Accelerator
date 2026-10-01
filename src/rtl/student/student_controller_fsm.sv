module student_controller_fsm (
  input  logic clk_i,
  input  logic rst_ni,

  input  logic start_i,
  input  logic clear_i,

  input  logic layer_done_i,

  output logic busy_o,
  output logic done_o,
  output logic error_o,
  output logic [2:0] state_o,

  output logic [2:0] layer_sel_o,
  output logic [1:0] feeder_sel_o,

  output logic [3:0] in_ch_o,
  output logic [7:0] depth_steps_o,

  output logic       use_pool_o,
  output logic       use_relu_o,
  output logic       argmax_en_o,

  output logic       layer_start_o,
  output logic       clear_acc_o,

  output logic [31:0] relu_pool_num_in_o
);

  localparam logic [2:0] LAYER_CONV1  = 3'd0;
  localparam logic [2:0] LAYER_CONV2  = 3'd1;
  localparam logic [2:0] LAYER_FC1    = 3'd2;
  localparam logic [2:0] LAYER_FC2    = 3'd3;
  localparam logic [2:0] LAYER_ARGMAX = 3'd4;

  localparam logic [1:0] FEED_IM2COL = 2'd0;
  localparam logic [1:0] FEED_FC     = 2'd1;

  typedef enum logic [2:0] {
    S_IDLE,
    S_CONV1,
    S_CONV2,
    S_FC1,
    S_FC2,
    S_ARGMAX,
    S_DONE,
    S_ERROR
  } state_e;

  state_e state_q, state_d;

  assign state_o = state_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= S_IDLE;
    end else begin
      state_q <= state_d;
    end
  end

//next state logic
  always_comb begin
    state_d = state_q;

    if (clear_i) begin
      state_d = S_IDLE;
    end else begin
      unique case (state_q)

        S_IDLE: begin
          if (start_i) begin
            state_d = S_CONV1;
          end
        end

        S_CONV1: begin
          if (layer_done_i) begin
            state_d = S_CONV2;
          end
        end

        S_CONV2: begin
          if (layer_done_i) begin
            state_d = S_FC1;
          end
        end

        S_FC1: begin
          if (layer_done_i) begin
            state_d = S_FC2;
          end
        end

        S_FC2: begin
          if (layer_done_i) begin
            state_d = S_ARGMAX;
          end
        end

        S_ARGMAX: begin
          if (layer_done_i) begin
            state_d = S_DONE;
          end
        end

        S_DONE: begin
          // Wait until software releases start_i.
          if (!start_i) begin
            state_d = S_IDLE;
          end
        end

        S_ERROR: begin
          state_d = S_ERROR;
        end

        default: begin
          state_d = S_ERROR;
        end

      endcase
    end
  end

  // Status outputs
  always_comb begin
    busy_o  = 1'b0;
    done_o  = 1'b0;
    error_o = 1'b0;

    unique case (state_q)

      S_IDLE: begin
        busy_o = 1'b0;
      end

      S_CONV1,
      S_CONV2,
      S_FC1,
      S_FC2,
      S_ARGMAX: begin
        busy_o = 1'b1;
      end

      S_DONE: begin
        busy_o = 1'b0;
        done_o = 1'b1;
      end

      S_ERROR: begin
        busy_o  = 1'b0;
        error_o = 1'b1;
      end

      default: begin
        error_o = 1'b1;
      end

    endcase
  end

  // One-cycle layer-start pulse
  // High for one cycle when entering a new compute layer.
  always_comb begin
    layer_start_o = 1'b0;
    clear_acc_o   = 1'b0;

    if (state_q != state_d) begin
      unique case (state_d)

        S_CONV1,
        S_CONV2,
        S_FC1,
        S_FC2,
        S_ARGMAX: begin
          layer_start_o = 1'b1;
        end

        default: begin
          layer_start_o = 1'b0;
        end

      endcase
    end

    // Accumulator only needs clearing for layers using the systolic array.
    if ((state_q != state_d) &&
        ((state_d == S_CONV1) ||
         (state_d == S_CONV2) ||
         (state_d == S_FC1)   ||
         (state_d == S_FC2))) begin
      clear_acc_o = 1'b1;
    end
  end

  // Layer configuration outputs
  // are stable during the whole active layer
  // every module can read these signals
  always_comb begin
    // Defaults
    layer_sel_o        = LAYER_CONV1;
    feeder_sel_o       = FEED_IM2COL;
    in_ch_o            = 4'd0;
    depth_steps_o      = 8'd0;
    use_pool_o         = 1'b0;
    use_relu_o         = 1'b0;
    argmax_en_o        = 1'b0;
    relu_pool_num_in_o = 32'd0;

    unique case (state_q)

      S_CONV1: begin
        layer_sel_o        = LAYER_CONV1;
        feeder_sel_o       = FEED_IM2COL;

        in_ch_o            = 4'd1;
        depth_steps_o      = 8'd2;
        use_pool_o         = 1'b1;
        use_relu_o         = 1'b1;
        argmax_en_o        = 1'b0;
        relu_pool_num_in_o = 32'd1352;
      end

      S_CONV2: begin
        layer_sel_o        = LAYER_CONV2;
        feeder_sel_o       = FEED_IM2COL;

        in_ch_o            = 4'd8;
        depth_steps_o      = 8'd9;
        use_pool_o         = 1'b1;
        use_relu_o         = 1'b1;
        argmax_en_o        = 1'b0;
        relu_pool_num_in_o = 32'd400;
      end

      S_FC1: begin
        layer_sel_o        = LAYER_FC1;
        feeder_sel_o       = FEED_FC;

        in_ch_o            = 4'd0;
        depth_steps_o      = 8'd25;   // 16-breit: 400 Eingaenge / 16 = 25 Schritte

        use_pool_o         = 1'b0;
        use_relu_o         = 1'b1;
        argmax_en_o        = 1'b0;

        // FC1 produces 64 psums.
        // relu_pool uses scalar mode: pool_en_i = 0, only psum_i[0].
        relu_pool_num_in_o = 32'd64;
      end

      S_FC2: begin
        layer_sel_o        = LAYER_FC2;
        feeder_sel_o       = FEED_FC;

        in_ch_o            = 4'd0;
        depth_steps_o      = 8'd4;    // 16-breit: 64 Eingaenge / 16 = 4 Schritte

        use_pool_o         = 1'b0;
        use_relu_o         = 1'b0;

        // FC2 produces 10 scores.
        // these should go directly to argmax.
        argmax_en_o        = 1'b0;
        relu_pool_num_in_o = 32'd10;
      end

      S_ARGMAX: begin
        layer_sel_o        = LAYER_ARGMAX;
        feeder_sel_o       = FEED_FC;

        in_ch_o            = 4'd0;
        depth_steps_o      = 8'd0;

        use_pool_o         = 1'b0;
        use_relu_o         = 1'b0;
        argmax_en_o        = 1'b1;
        relu_pool_num_in_o = 32'd0;
      end

      default: begin
        layer_sel_o        = LAYER_CONV1;
        feeder_sel_o       = FEED_IM2COL;
        in_ch_o            = 4'd0;
        depth_steps_o      = 8'd0;
        use_pool_o         = 1'b0;
        use_relu_o         = 1'b0;
        argmax_en_o        = 1'b0;
        relu_pool_num_in_o = 32'd0;
      end

    endcase
  end

endmodule