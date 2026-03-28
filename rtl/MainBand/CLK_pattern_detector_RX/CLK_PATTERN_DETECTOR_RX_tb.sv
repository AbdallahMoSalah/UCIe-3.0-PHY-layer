module CLK_PATTERN_DETECTOR_RX_tb;

  // -------------------------
  // Easy parameters to change
  // -------------------------
  localparam int TOGGLE_CYCLES = 16;    // toggle clk_p for 16 cycles
  localparam int ZERO_CYCLES   = 8;     // then keep clk_p=0 for 8 cycles
  localparam int REPEAT_TIMES  = 128;   // repeat the whole pattern 128 times

  localparam time CLK_PERIOD   = 10ns;  // i_clk period
  localparam time PHASE_DELAY  = 5ns;   // clk_n delayed from clk_p by 5ns

  // -------------------------
  // Signals
  // -------------------------
  logic i_clk;
  logic i_rst_n;
  logic clk_detector_en;

  logic clk_p;
  logic clk_n;
  logic track;

  logic clk_check_done;
  logic clk_pattern_error;

  // -------------------------
  // DUT (Device Under Test)
  // -------------------------
  CLK_PATTERN_DETECTOR_RX dut (
    .i_clk(i_clk),
    .i_rst_n(i_rst_n),
    .clk_detector_en(clk_detector_en),
    .clk_p(clk_p),
    .clk_n(clk_n),
    .track(track),
    .clk_check_done(clk_check_done),
    .clk_pattern_error(clk_pattern_error)
  );

  // -------------------------
  // 1) Make i_clk toggle forever
  // -------------------------
  initial begin
    i_clk = 1'b0;
    forever #(CLK_PERIOD/2) i_clk = ~i_clk;
  end

  // -------------------------
  // 2) Make clk_n = clk_p delayed (phase shift)
  // -------------------------
  assign #(PHASE_DELAY) clk_n = clk_p;

  // -------------------------
  // 3) Main stimulus
  // -------------------------
  initial begin
    int rep;  // counts how many times we repeated the pattern
    int i;    // simple loop counter

    // Start with everything low
    i_rst_n         = 1'b0;
    clk_detector_en = 1'b0;
    clk_p           = 1'b0;
    track           = 1'b0;

    // Hold reset for a few clock cycles
    repeat (3) @(posedge i_clk);
    i_rst_n = 1'b1;  // release reset

    // Enable the detector
    @(posedge i_clk);
    clk_detector_en = 1'b1;

    // Repeat the full pattern up to 128 times (stop early if done)
    for (rep = 0; rep < REPEAT_TIMES; rep++) begin
      if (clk_check_done) break;

      // -------------------------
      // Part A: Toggle for 16 cycles
      // clk_p will behave like i_clk for 16 cycles
      // -------------------------
      for (i = 0; i < TOGGLE_CYCLES; i++) begin
        if (clk_check_done) break;

        @(posedge i_clk);
        clk_p <= 1'b1;
        track <= 1'b1;

        @(negedge i_clk);
        clk_p <= 1'b0;
        track <= 1'b0;
      end

      // -------------------------
      // Part B: Hold zero for 8 cycles
      // clk_p stays 0 for 8 cycles
      // -------------------------
      clk_p <= 1'b0;
      track <= 1'b0;

      for (i = 0; i < ZERO_CYCLES; i++) begin
        if (clk_check_done) break;
        @(posedge i_clk);
      end
    end

    // After we finish, keep clocks low
    clk_p <= 1'b0;
    track <= 1'b0;

    // Disable detector (optional)
    @(posedge i_clk);
    clk_detector_en = 1'b0;

    // Wait a little, then finish simulation
    repeat (5) @(posedge i_clk);
    $stop;
  end

endmodule