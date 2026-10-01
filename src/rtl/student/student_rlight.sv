module student_rlight (
  input logic clk_i,
  input logic rst_ni,

  output tlul_pkg::tl_d2h_t tl_o,  //slave output (this module's response)
  input  tlul_pkg::tl_h2d_t tl_i,  //master input (incoming request)

  output logic [7:0] led_o
);

  logic [3:0]  addr;
  logic        we;
  logic        re;
  logic [31:0] wdata;
  logic [31:0] rdata;

  tlul_adapter_reg #(
    .RegAw(4),
    .RegDw(32)
  ) adapter_reg_i (
    .clk_i,
    .rst_ni,
    .tl_i,
    .tl_o,
    .we_o   (we),
    .re_o   (re),
    .addr_o (addr),
    .wdata_o(wdata),
    .be_o   (),
    .rdata_i(rdata),
    .error_i('0)
  );

  // Register addresses
  localparam logic [3:0] ADDR_PATTERN = 4'h0;
  localparam logic [3:0] ADDR_MODE    = 4'h4;
  localparam logic [3:0] ADDR_SPEED   = 4'h8;
  localparam logic [3:0] ADDR_STATUS  = 4'hC;

  // Mode encodings
  localparam logic [1:0] MODE_RIGHT = 2'd0;
  localparam logic [1:0] MODE_LEFT  = 2'd1;
  localparam logic [1:0] MODE_PIPO  = 2'd2;
  localparam logic [1:0] MODE_STOP  = 2'd3;

  logic [7:0]  pattern;
  logic [1:0]  mode;
  logic [31:0] speed;

  // Bus reads
  // ---------
  always_comb begin
    rdata = '0;
    if (re) begin
      case (addr)
        ADDR_PATTERN: rdata[7:0]  = pattern;
        ADDR_MODE:    rdata[1:0]  = mode;
        ADDR_SPEED:   rdata[31:0] = speed;
        ADDR_STATUS:  rdata[7:0]  = led_o;
        default:      rdata       = '0;
      endcase
    end
  end

  // Bus writes
  // ----------
  always_ff @(posedge clk_i, negedge rst_ni) begin
    if (~rst_ni) begin
      pattern <= 8'b0001_1000;   // sichtbares Startmuster
      mode    <= MODE_PIPO;      // nach Reset: ping-pong
      speed   <= 32'd10;         // klein -> gut sichtbar in der Simulation
    end else if (we) begin
      case (addr)
        ADDR_PATTERN: pattern <= wdata[7:0];
        ADDR_MODE:    mode    <= wdata[1:0];
        ADDR_SPEED:   speed   <= wdata[31:0];
        default: ;
      endcase
    end
  end

  // Speed counter: erzeugt alle (speed+1) Takte einen 1-Takt-Puls "step"
  // --------------------------------------------------------------------
  logic [7:0]  led;
  logic [31:0] cnt;
  logic        step;

  always_ff @(posedge clk_i, negedge rst_ni) begin
    if (~rst_ni) begin
      cnt  <= '0;
      step <= 1'b0;
    end else if (cnt == 0) begin
      cnt  <= speed;
      step <= 1'b1;
    end else begin
      cnt  <= cnt - 1;
      step <= 1'b0;
    end
  end

  logic signed [4:0] pos;   
  logic              dir;   

  always_ff @(posedge clk_i, negedge rst_ni) begin
    if (~rst_ni) begin
      led <= 8'b0001_1000;
      pos <= '0;
      dir <= 1'b0;
    end else if (we && addr == ADDR_PATTERN) begin
      led <= wdata[7:0];
      pos <= '0;
      dir <= 1'b0;
    end else if (step) begin
      case (mode)
        MODE_LEFT:  led <= {led[6:0], led[7]};
        MODE_RIGHT: led <= {led[0], led[7:1]};
        MODE_STOP:  led <= led;                  
        MODE_PIPO: begin
          if (pos >= 0) led <= pattern << pos;
          else          led <= pattern >> (-pos);
          if (!dir) begin
            if (pos >= 7) begin dir <= 1'b1; pos <= pos - 1; end
            else                              pos <= pos + 1;
          end else begin
            if (pos <= -7) begin dir <= 1'b0; pos <= pos + 1; end
            else                              pos <= pos - 1;
          end
        end
        default: led <= led;
      endcase
    end
  end

  assign led_o = led;

endmodule