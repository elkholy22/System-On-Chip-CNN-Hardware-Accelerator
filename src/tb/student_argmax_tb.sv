module student_argmax_tb;

  localparam int N = 10;
  localparam int W = 32;

  logic               clk, rst_n;
  logic               start, done;
  logic [3:0]         digit;
  logic signed [W-1:0] scores [0:N-1];

  always begin clk = 1'b1; #10000; clk = 1'b0; #10000; end

  student_argmax #(.N(N), .W(W)) dut (
      .clk_i(clk), .rst_ni(rst_n),
      .start_i(start), .scores_i(scores),
      .digit_o(digit), .done_o(done)
  );

  task automatic run_case(input int max_idx, input string name);
    // Scores setzen: max_idx ist der groesste
    for (int i = 0; i < N; i++) scores[i] = i;      // 0..9 aufsteigend
    scores[max_idx] = 32'sd1000;                    // klarer Maximalwert
    @(posedge clk); #1; start = 1'b1;               // start #1 nach der Flanke setzen
    @(posedge clk); #1; start = 1'b0;
    // SEQUENZIELLES argmax: auf done_o warten (N-1 Takte)
    do begin @(posedge clk); #1; end while (done !== 1'b1);
    if (digit !== max_idx[3:0])
      $error("%s: digit=%0d != erwartet %0d", name, digit, max_idx);
    else
      $display("ok  %s: digit=%0d", name, digit);
  endtask

  initial begin
    rst_n = 1'b0; start = 1'b0;
    for (int i = 0; i < N; i++) scores[i] = '0;
    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);

    run_case(0, "max@0");
    run_case(7, "max@7");
    run_case(9, "max@9");
    run_case(3, "max@3");

    $display("### ARGMAX TB DONE ###");
    $finish;
  end

endmodule
