module student_irq_ctrl #(
    parameter int IRQ_MAX = 32          // 1..32 Eingangsleitungen
) (
    input  logic                clk_i,
    input  logic                rst_ni,

    // TL-UL Slave
    output tlul_pkg::tl_d2h_t   tl_o,
    input  tlul_pkg::tl_h2d_t   tl_i,

    // IRQ-Quellen rein, aggregierter IRQ raus
    input  logic [IRQ_MAX-1:0]  irq_i,
    output logic                irq_o
);

  // --- Register-Bus via Adapter (0x00..0x1C -> 5 Adressbits) ---
  logic [4:0]  addr;
  logic        we, re;
  logic [31:0] wdata, rdata;

  tlul_adapter_reg #(.RegAw(5), .RegDw(32)) u_adapter (
      .clk_i, .rst_ni,
      .tl_i,  .tl_o,
      .we_o   (we),
      .re_o   (re),
      .addr_o (addr),
      .wdata_o(wdata),
      .be_o   (),
      .rdata_i(rdata),
      .error_i('0)
  );

  localparam logic [4:0] ADDR_ALL_EN   = 5'h00;
  localparam logic [4:0] ADDR_MASK     = 5'h04;
  localparam logic [4:0] ADDR_MASK_SET = 5'h08;
  localparam logic [4:0] ADDR_MASK_CLR = 5'h0C;
  localparam logic [4:0] ADDR_STATUS   = 5'h10;
  localparam logic [4:0] ADDR_IRQ_NO   = 5'h14;
  localparam logic [4:0] ADDR_TEST     = 5'h18;
  localparam logic [4:0] ADDR_TEST_IRQ = 5'h1C;

  // --- Register ---
  logic                all_en;
  logic [IRQ_MAX-1:0]  mask;
  logic                test;
  logic [IRQ_MAX-1:0]  test_irq;

  // --- Effektive IRQ-Quellen (Test-Mux) ---
  logic [IRQ_MAX-1:0]  eff;
  assign eff = test ? test_irq : irq_i;

  logic [IRQ_MAX-1:0]  masked;
  assign masked = eff & mask;

  // --- Prioritaets-Encoder: niedrigster gesetzter, unmaskierter IRQ ---
  logic [5:0] irq_no;   // 0..IRQ_MAX (IRQ_MAX = "keiner")
  always_comb begin
    irq_no = IRQ_MAX[5:0];
    for (int n = IRQ_MAX - 1; n >= 0; n--) begin
      if (masked[n]) irq_no = n[5:0];   // letzte (niedrigste) Zuweisung gewinnt
    end
  end

  // --- Ausgangs-IRQ ---
  assign irq_o = all_en & (|masked);

  // --- Schreibpfad ---
  always_ff @(posedge clk_i, negedge rst_ni) begin
    if (~rst_ni) begin
      all_en   <= 1'b0;
      mask     <= '0;
      test     <= 1'b0;
      test_irq <= '0;
    end else if (we) begin
      case (addr)
        ADDR_ALL_EN:   all_en   <= wdata[0];
        ADDR_MASK:     mask     <= wdata[IRQ_MAX-1:0];
        ADDR_MASK_SET: mask     <= mask |  wdata[IRQ_MAX-1:0];
        ADDR_MASK_CLR: mask     <= mask & ~wdata[IRQ_MAX-1:0];
        ADDR_TEST:     test     <= wdata[0];
        ADDR_TEST_IRQ: test_irq <= wdata[IRQ_MAX-1:0];
        default: ;
      endcase
    end
  end

  // --- Lesepfad ---
  always_comb begin
    rdata = '0;
    if (re) begin
      case (addr)
        ADDR_ALL_EN:   rdata[0]            = all_en;
        ADDR_MASK:     rdata[IRQ_MAX-1:0]  = mask;
        ADDR_STATUS:   rdata[IRQ_MAX-1:0]  = eff;
        ADDR_IRQ_NO:   rdata[5:0]          = irq_no;
        ADDR_TEST:     rdata[0]            = test;
        ADDR_TEST_IRQ: rdata[IRQ_MAX-1:0]  = test_irq;
        default:       rdata               = '0;
      endcase
    end
  end

endmodule
