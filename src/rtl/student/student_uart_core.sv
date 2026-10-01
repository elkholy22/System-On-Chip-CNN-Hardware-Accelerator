// uart_core.sv
// Plain UART TX/RX logic — no bus knowledge, just signals in/out.
// Single-rate-counter design (no 16x oversampling) — justified for this
// board: 100 MHz system clock, crystal-based clock sources on both ends,
// per-byte resync via the start bit keeps drift well within margin.

module student_uart_core (
  input  logic        clk_i,
  input  logic        rst_ni,

  input  logic        enable_i,
  input  logic [15:0] baud_div_i,   // clk cycles per bit = clk_hz / baud_rate

  // TX side
  input  logic [7:0]  tx_data_i,
  input  logic        tx_start_i,   // 1-cycle pulse: latch tx_data_i & begin sending
  output logic        tx_busy_o,
  output logic        tx_serial_o,

  // RX side
  input  logic        rx_serial_i,
  output logic [7:0]  rx_data_o,
  output logic        rx_valid_o,
  input  logic        rx_clear_i    // 1-cycle pulse: SW read RXDATA, clear rx_valid
);

  // ---------------------------------------------------------
  // RX input synchronizer (2-FF, guards against metastability
  // since rx_serial_i is fully async to clk_i)
  // ---------------------------------------------------------
  logic rx_sync0, rx_sync1;

  always_ff @(posedge clk_i, negedge rst_ni) begin
    if (!rst_ni) begin
      rx_sync0 <= 1'b1;
      rx_sync1 <= 1'b1;
    end else begin
      rx_sync0 <= rx_serial_i;
      rx_sync1 <= rx_sync0;
    end
  end

  // ---------------------------------------------------------
  // TX state machine
  // ---------------------------------------------------------
  typedef enum logic [1:0] {
    TX_IDLE, TX_START, TX_DATA, TX_STOP
  } tx_state_e;

  tx_state_e   tx_state;
  logic [15:0] tx_cnt;
  logic [2:0]  tx_bit_idx;
  logic [7:0]  tx_shift;
  logic        tx_line;

  assign tx_serial_o = tx_line;
  assign tx_busy_o   = (tx_state != TX_IDLE);

  always_ff @(posedge clk_i, negedge rst_ni) begin
    if (!rst_ni) begin
      tx_state    <= TX_IDLE;
      tx_line     <= 1'b1;      // idle high
      tx_cnt      <= '0;
      tx_bit_idx  <= '0;
      tx_shift    <= '0;
    end else if (!enable_i) begin
      tx_state <= TX_IDLE;
      tx_line  <= 1'b1;
    end else begin
      case (tx_state)

        TX_IDLE: begin
          tx_line <= 1'b1;
          if (tx_start_i) begin
            tx_shift   <= tx_data_i;
            tx_cnt     <= baud_div_i;
            tx_state   <= TX_START;
          end
        end

        TX_START: begin
          tx_line <= 1'b0;               // start bit
          if (tx_cnt == 0) begin
            tx_cnt     <= baud_div_i;
            tx_bit_idx <= '0;
            tx_state   <= TX_DATA;
          end else begin
            tx_cnt <= tx_cnt - 1'b1;
          end
        end

        TX_DATA: begin
          tx_line <= tx_shift[0];
          if (tx_cnt == 0) begin
            tx_cnt   <= baud_div_i;
            tx_shift <= tx_shift >> 1;
            if (tx_bit_idx == 3'd7) begin
              tx_state <= TX_STOP;
            end else begin
              tx_bit_idx <= tx_bit_idx + 1'b1;
            end
          end else begin
            tx_cnt <= tx_cnt - 1'b1;
          end
        end

        TX_STOP: begin
          tx_line <= 1'b1;               // stop bit
          if (tx_cnt == 0) begin
            tx_state <= TX_IDLE;
          end else begin
            tx_cnt <= tx_cnt - 1'b1;
          end
        end

        default: tx_state <= TX_IDLE;
      endcase
    end
  end

  // ---------------------------------------------------------
  // RX state machine
  // Resyncs on every start bit's falling edge; samples each
  // bit at its center by waiting a half period, then full
  // periods thereafter. See error-budget discussion: at 100
  // MHz / typical baud rates, drift-per-byte is orders of
  // magnitude smaller than the safety margin.
  // ---------------------------------------------------------
  typedef enum logic [1:0] {
    RX_IDLE, RX_START, RX_DATA, RX_STOP
  } rx_state_e;

  rx_state_e   rx_state;
  logic [15:0] rx_cnt;
  logic [2:0]  rx_bit_idx;
  logic [7:0]  rx_shift;
  logic [7:0]  rx_data_q;
  logic        rx_valid_q;

  assign rx_data_o  = rx_data_q;
  assign rx_valid_o = rx_valid_q;

  always_ff @(posedge clk_i, negedge rst_ni) begin
    if (!rst_ni) begin
      rx_state   <= RX_IDLE;
      rx_cnt     <= '0;
      rx_bit_idx <= '0;
      rx_shift   <= '0;
      rx_data_q  <= '0;
      rx_valid_q <= 1'b0;
    end else if (!enable_i) begin
      rx_state   <= RX_IDLE;
      rx_valid_q <= 1'b0;
    end else begin

      // Software reading RXDATA clears the valid flag.
      if (rx_clear_i) rx_valid_q <= 1'b0;

      case (rx_state)

        RX_IDLE: begin
          if (!rx_sync1) begin                  // falling edge -> possible start bit
            rx_cnt   <= {1'b0, baud_div_i[15:1]}; // wait half a bit period
            rx_state <= RX_START;
          end
        end

        RX_START: begin
          if (rx_cnt == 0) begin
            if (!rx_sync1) begin                // confirm still low at center
              rx_cnt     <= baud_div_i;
              rx_bit_idx <= '0;
              rx_state   <= RX_DATA;
            end else begin
              rx_state <= RX_IDLE;              // false start / glitch
            end
          end else begin
            rx_cnt <= rx_cnt - 1'b1;
          end
        end

        RX_DATA: begin
          if (rx_cnt == 0) begin
            rx_shift[rx_bit_idx] <= rx_sync1;   // sample at bit center
            rx_cnt <= baud_div_i;
            if (rx_bit_idx == 3'd7) begin
              rx_state <= RX_STOP;
            end else begin
              rx_bit_idx <= rx_bit_idx + 1'b1;
            end
          end else begin
            rx_cnt <= rx_cnt - 1'b1;
          end
        end

        RX_STOP: begin
          if (rx_cnt == 0) begin
            if (rx_sync1) begin                 // valid stop bit
              rx_data_q  <= rx_shift;
              rx_valid_q <= 1'b1;
            end
            // else: framing error, byte dropped silently
            rx_state <= RX_IDLE;
          end else begin
            rx_cnt <= rx_cnt - 1'b1;
          end
        end

        default: rx_state <= RX_IDLE;
      endcase
    end
  end

endmodule