// ============================================================
// Module:  im2col
// Purpose: Extrahiert KER_H x KER_W Patches aus einem
//          seriellen IMG_H x IMG_W Pixelstrom (1 Pixel/Takt).
//          Implementiert als Sliding Window mit Line Buffern.
//
// Inputs:  clk_i   - Takt
//          rst_ni  - asynchroner Reset, aktiv-low
//          valid_i - high wenn pixel_i gültig
//          pixel_i - uint8 Pixelwert, zeilenweise von (0,0)
//                    bis (IMG_H-1, IMG_W-1)
//
// Outputs: valid_o - high wenn patch_o gültig
//          patch_o - KER_H*KER_W Pixel des aktuellen Fensters,
//                    zeilenweise geflattened:
//
// Latenz:  erstes valides patch_o wenn row >= KER_H und col = 0
// ============================================================
module im2col #(
    parameter IMG_W = 28,
    parameter IMG_H = 28,
    parameter KER_W = 3,
    parameter KER_H = 3
) (
    input  logic        clk_i,
    input  logic        rst_ni,
    input  logic        clear_i,   // NEU: Zaehler/ready fuer ein neues Bild nullen
    input  logic        valid_i,
    input  logic [7:0]  pixel_i,
    output logic        valid_o,
    output logic [7:0]  patch_o [0:KER_W*KER_H-1]
);

    // --------------------------------------------------------
    // Zähler: verfolgt aktuelle Position im Bildstrom
    //
    // row     - aktuelle Zeile (0..IMG_H-1)
    // col     - aktuelle Spalte (0..IMG_W-1)
    // row_end - kombinatorisch, high beim letzten Pixel
    //           einer Zeile (col == IMG_W-1)
    // ready   - wird high sobald genug Zeilen im Line Buffer
    //           sind um einen validen Patch zu bilden.
    //           Wird nur bei Ender der Zeile aktualisiert.
    // --------------------------------------------------------
    logic [$clog2(IMG_H)-1:0] row = 0;
    logic [$clog2(IMG_W)-1:0] col = 0;

    logic row_end;
    assign row_end = valid_i & (col == IMG_W - 1);

    logic ready = 0;

    always_ff @(posedge clk_i, negedge rst_ni) begin : posCounter
        if (~rst_ni) begin
            row   <= 0;
            col   <= 0;
            ready <= 0;
        end else if (clear_i) begin
            // Neues Bild: Position + ready nullen. line_buf muss NICHT geleert
            // werden -- ready=0 unterdrueckt Patches, bis 3 frische Zeilen
            // eingeschoben sind (alte Zeilen werden dabei rausgeschoben).
            row   <= 0;
            col   <= 0;
            ready <= 0;
        end else if (valid_i) begin
            if (col == IMG_W - 1) begin
                col <= '0;
                row <= (row == IMG_H - 1) ? '0 : row + 1;
                // ready wird nur bei Ende der Zeile geprüft.
                // row hat hier noch den alten Wert (non-blocking),
                // also entspricht row >= KER_H - 1 dem Abschluss
                // von Zeile KER_H - 1, d.h. ab Zeile KER_H sind
                // genug Zeilen im Buffer.
                if (row >= KER_H - 1) begin
                    ready <= 1;
                end else begin
                    ready <= 0;
                end
            end else begin
                col <= col + 1;
            end
        end
    end

    // --------------------------------------------------------
    // Line Buffer: speichert die letzten KER_H Zeilen
    //
    // line_buf[0]       - write buffer, aktuelle Zeile wird
    //                     hier Pixel für Pixel reingeschrieben
    // line_buf[1]       - neueste fertige Zeile (row-1)
    // line_buf[2]       - mittlere fertige Zeile (row-2)
    // line_buf[KER_H]   - älteste fertige Zeile (row-KER_H)
    //                     -> wird als erste Zeile im Patch verwendet
    //
    // Bei row_end werden alle fertigen Zeilen um eine Stufe
    // weitergerückt (line_buf[i] <= line_buf[i-1]).
    //
    // Non-blocking Sonderfall: line_buf[0][col] wird im selben
    // Takt geschrieben wie der Shift passiert. Da non-blocking
    // die RHS mit alten Werten auswertet, fehlt das letzte Pixel
    // in line_buf[1] nach dem Shift. Deshalb wird es direkt
    // nochmals in line_buf[1][col] geschrieben - bei mehreren
    // Assignments auf dasselbe Register gewinnt das letzte.
    // --------------------------------------------------------
    logic [7:0] line_buf [0:KER_H][0:IMG_W-1];

    always_ff @(posedge clk_i, negedge rst_ni) begin : lineBuffer
        if (~rst_ni) begin
            line_buf <= '{default: '0};
        end else if (valid_i) begin
            // Aktuelles Pixel in write buffer schreiben
            line_buf[0][col] <= pixel_i;

            if (row_end) begin
                // Fertige Zeilen um eine Stufe weiterrücken
                for (int i = KER_H; i > 0; i--) begin
                    line_buf[i] <= line_buf[i-1];
                end
                // Letztes Pixel direkt in line_buf[1] korrigieren
                line_buf[1][col] <= pixel_i;
            end
        end
    end

    // --------------------------------------------------------
    // Patch Ausgabe: kombinatorisch aus Line Buffer
    //
    // Patch ist gültig wenn:
    //   ready              - genug Zeilen im Buffer
    //   col <= IMG_W-KER_W - Fenster geht nicht über rechten Rand
    //
    // Indexierung:
    //   i=0 -> line_buf[KER_H]   (älteste Zeile → patch Zeile 0)
    //   i=1 -> line_buf[KER_H-1]
    //   i=2 -> line_buf[1]       (neueste Zeile → patch Zeile 2)
    //
    //   col + j greift auf Spalten col, col+1, col+2 zu.
    //   col <= IMG_W-KER_W stellt sicher dass col+2 <= IMG_W-1.
    //   Dadurch zwei Takte mit nicht validen Patches zwischen validen Patches.
    // --------------------------------------------------------
    always_comb begin : makePatch
        patch_o = '{default: '0};
        valid_o = 1'b0;
        if (valid_i & ready & (col <= IMG_W - KER_W)) begin
            valid_o = 1'b1;
            for (int i = 0; i < KER_H; i++) begin
                for (int j = 0; j < KER_W; j++) begin
                    patch_o[KER_W * i + j] = line_buf[KER_H - i][col + j];
                end
            end
        end
    end

endmodule