module student_tlul_mux #(
    parameter int NUM    = 2,
    parameter int DEV_AW = 4   // Adressbits pro Geraet (TB: 16-Byte-Fenster; real: 20 = 1 MB)
) (
    input logic clk_i,
    input logic rst_ni,

    output tlul_pkg::tl_d2h_t tl_host_o,
    input  tlul_pkg::tl_h2d_t tl_host_i,

    input  tlul_pkg::tl_d2h_t  tl_device_o [NUM-1:0],
    output tlul_pkg::tl_h2d_t  tl_device_i [NUM-1:0]
);

  localparam int AW = $bits(tl_host_i.a_address);

  // Welches Geraet meint der Host? 4 Selektionsbits oberhalb des Geraetefensters.
  logic [3:0] sel;
  assign sel = tl_host_i.a_address[DEV_AW +: 4];

  always_comb begin
    // ---------- A-Kanal: Host -> Geraete ----------
    for (int d = 0; d < NUM; d++) begin
      tl_device_i[d]         = tl_host_i;                        // alle Request-Felder kopieren
      tl_device_i[d].a_valid = tl_host_i.a_valid && (sel == d);  // nur das Ziel sieht valid
      tl_device_i[d].a_address[AW-1:DEV_AW] = '0;                // obere Bits strippen -> lokaler Offset
      tl_device_i[d].d_ready = 1'b0;                             // Default, unten gesetzt
    end

    // ---------- D-Kanal: Geraete -> Host ----------
    tl_host_o = '0;
    for (int d = 0; d < NUM; d++) begin
      if (tl_device_o[d].d_valid) begin
        tl_host_o              = tl_device_o[d];          // Antwort dieses Geraets zum Host
        tl_device_i[d].d_ready = tl_host_i.d_ready;       // host-ready an den Antwortenden
      end
    end

    // a_ready gehoert zum A-Ziel (nicht zum D-Antwortenden) -> ganz zuletzt setzen.
    // WICHTIG (X-Sicherheit): mit a_valid gaten! Ohne Request ist a_address (und
    // damit sel) undefiniert -> "(sel < NUM)" waere X -> a_ready X -> der peri-Xbar
    // (prim_fifo assert WreadyKnown_A) wird vergiftet und alle Zugriffe korrupt.
    tl_host_o.a_ready = tl_host_i.a_valid
                      ? ((sel < NUM) ? tl_device_o[sel].a_ready : 1'b0)
                      : 1'b0;
  end

endmodule