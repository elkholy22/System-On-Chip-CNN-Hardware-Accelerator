module student_image_bram (
    input  logic        clk_i,
    input  logic        rst_ni,
    input  logic        we_i,
    input  logic [9:0]  waddr_i,
    input  logic [7:0]  wdata_i,
    input  logic        start_i,
    output logic [7:0]  rdata_o,
    output logic        valid_o,
    output logic        busy_o      // high solange gestreamt wird (fuer Sequencer)
);

    (* ram_style = "block" *) logic [7:0] mem [0:783];

    typedef enum logic [0:0] {IDLE, RUN} state_e;
    state_e state;

    logic [9:0] rd_addr;
    logic       running;   // high solange Adressen 0..809 ausgegeben werden

    assign busy_o = (state != IDLE);

    always_ff @(posedge clk_i) begin
        if (we_i) mem[waddr_i] <= wdata_i;
    end

    // Registrierter Read (1 Takt Latenz). Extra-Pixel (rd_addr > 783) sind Dummy 0
    // -> nur damit im2col die letzte conv-Zeile emittiert (Off-by-one-Ausgleich);
    // landen ungenutzt in line_buf[0].
    always_ff @(posedge clk_i) begin
        rdata_o <= (rd_addr <= 10'd783) ? mem[rd_addr] : 8'd0;
    end

    // 1 PIXEL/TAKT: rd_addr laeuft 0..809 (784 echt + 26 Dummy) in
    // aufeinanderfolgenden Takten. valid_o ist der um 1 Takt verzoegerte "issue"
    // und deckt damit exakt die Read-Latenz -> Pixel k erscheint bei Takt k+1.
    // Gleiche 810-Pixel-Sequenz wie zuvor, nur doppelt so schnell (im2col nimmt
    // 1 Pixel/Takt an, kein Backpressure) -> conv1 O_STREAM ~1620 -> ~810 Takte.
    always_ff @(posedge clk_i, negedge rst_ni) begin
        if (~rst_ni) begin
            state   <= IDLE;
            rd_addr <= '0;
            running <= 1'b0;
            valid_o <= 1'b0;
        end else begin
            unique case (state)
                IDLE: begin
                    valid_o <= 1'b0;
                    if (start_i) begin
                        rd_addr <= '0;
                        running <= 1'b1;
                        state   <= RUN;
                    end
                end
                RUN: begin
                    valid_o <= running;                        // letzte Ausgabe ist jetzt gueltig
                    if (running) begin
                        if (rd_addr == 10'd809) running <= 1'b0;   // letzte Adresse ausgegeben
                        else                    rd_addr <= rd_addr + 1'b1;
                    end else begin
                        valid_o <= 1'b0;                        // letztes Pixel praesentiert -> fertig
                        state   <= IDLE;
                    end
                end
            endcase
        end
    end

endmodule
