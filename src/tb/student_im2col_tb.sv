module student_im2col_tb;

  localparam int IMG_W   = 28;
  localparam int IMG_H   = 28;
  localparam int KER_W   = 3;
  localparam int KER_H   = 3;
  localparam int N_DUMMY = IMG_W - KER_W + 1;
  localparam int N_PATCH = (IMG_W-KER_W+1) * (IMG_H-KER_H+1);

  logic       clk, rst_n;
  logic       clear, valid_in;
  logic [7:0] pixel;
  logic       valid_out;
  logic [7:0] patch [0:KER_W*KER_H-1];

  always begin clk = 1'b1; #10000; clk = 1'b0; #10000; end

  im2col #(.IMG_W(IMG_W), .IMG_H(IMG_H), .KER_W(KER_W), .KER_H(KER_H)) dut (
      .clk_i  (clk),
      .rst_ni (rst_n),
      .clear_i(clear),
      .valid_i(valid_in),
      .pixel_i(pixel),
      .valid_o(valid_out),
      .patch_o(patch)
  );

  int errors = 0;
  int npatch;

  function automatic logic [7:0] pix(input int img, input int r, input int c);
    case (img)
      0:       return 8'((r*31 + c) & 255);
      1:       return 8'((r*17 + 3*c + 5) & 255);
      default: return 8'((r*7 + 13*c + 99) & 255);
    endcase
  endfunction

  function automatic int exp_count(input int n, input int ndummy);
    int r, c, cnt;
    cnt = 0;
    for (int k = 0; k < n + ndummy; k++) begin
      if (k < n) begin r = k / IMG_W; c = k % IMG_W; end
      else       begin r = IMG_H;     c = k - n;     end
      if ((r >= KER_H) && (c <= IMG_W - KER_W)) cnt++;
    end
    return cnt;
  endfunction

  task automatic stream_and_check(input int img, input int n, input int ndummy,
                                  output int seen);
    int r, c, tr, tc, total, mism;
    logic [7:0] exp;
    total = n + ndummy;
    seen  = 0;
    mism  = 0;
    for (int k = 0; k < total; k++) begin
      @(posedge clk); #1;
      valid_in = 1'b1;
      if (k < n) begin
        r = k / IMG_W; c = k % IMG_W;
        pixel = pix(img, r, c);
      end else begin
        r = IMG_H; c = k - n;
        pixel = 8'h00;
      end
      @(negedge clk);
      if ((r >= KER_H) && (c <= IMG_W - KER_W)) begin
        if (valid_out !== 1'b1) begin
          $error("img%0d k=%0d (r=%0d c=%0d): valid_o=%b, erwartet 1",
                 img, k, r, c, valid_out);
          errors++;
        end else begin
          tr = r - KER_H; tc = c;
          for (int i = 0; i < KER_H; i++) begin
            for (int j = 0; j < KER_W; j++) begin
              exp = pix(img, tr + i, tc + j);
              if (patch[KER_W*i + j] !== exp) begin
                if (mism < 3)
                  $error("img%0d patch(%0d,%0d)[%0d]: 0x%02x != erwartet 0x%02x",
                         img, tr, tc, KER_W*i + j, patch[KER_W*i + j], exp);
                mism++;
                errors++;
              end
            end
          end
          seen++;
        end
      end else begin
        if (valid_out !== 1'b0) begin
          $error("img%0d k=%0d (r=%0d c=%0d): valid_o=%b, erwartet 0",
                 img, k, r, c, valid_out);
          errors++;
        end
      end
    end
    @(posedge clk); #1;
    valid_in = 1'b0;
    pixel    = '0;
    if (mism > 3) $display("   (%0d weitere Patch-Mismatches unterdrueckt)", mism - 3);
  endtask

  task automatic pulse_clear();
    @(posedge clk); #1; valid_in = 1'b0; clear = 1'b1;
    @(posedge clk); #1; clear = 1'b0;
  endtask

  task automatic check_count(input int got, input int expct, input string name);
    if (got !== expct) begin
      $error("%s: %0d Patches, erwartet %0d", name, got, expct);
      errors++;
    end else begin
      $display("PASS %s: %0d Patches korrekt", name, got);
    end
  endtask

  task automatic check_idle(input string name);
    repeat (2) @(negedge clk);
    if (valid_out !== 1'b0) begin
      $error("%s: valid_o=%b im Leerlauf, erwartet 0", name, valid_out);
      errors++;
    end
  endtask

  initial begin
    rst_n = 1'b0; clear = 1'b0; valid_in = 1'b0; pixel = '0;
    repeat (4) @(posedge clk);
    #1; rst_n = 1'b1;
    check_idle("nach Reset");

    $display("--- Bild 0: %0d Pixel + %0d Dummy ---", IMG_W*IMG_H, N_DUMMY);
    stream_and_check(0, IMG_W*IMG_H, N_DUMMY, npatch);
    check_count(npatch, N_PATCH, "Bild 0");
    check_idle("nach Bild 0");

    pulse_clear();
    $display("--- Bild 1: Abbruch nach 287 Pixeln (10 Zeilen + 7 px) ---");
    stream_and_check(1, 287, 0, npatch);
    check_count(npatch, exp_count(287, 0), "Bild 1 (partiell)");

    pulse_clear();
    $display("--- Bild 2: sauberes Bild nach Mid-Stream-Clear ---");
    stream_and_check(2, IMG_W*IMG_H, N_DUMMY, npatch);
    check_count(npatch, N_PATCH, "Bild 2");
    check_idle("nach Bild 2");

    if (errors == 0) $display("\n==== ALLE CHECKS BESTANDEN ====");
    else             $display("\n==== %0d CHECK(S) FEHLGESCHLAGEN ====", errors);
    $finish;
  end

endmodule
