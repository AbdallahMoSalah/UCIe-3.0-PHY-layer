

module CLK_PATTERN_DETECTOR_RX_tb;

  // -------------------------
  // Easy parameters to change
  // -------------------------
  localparam int TOGGLE_CYCLES = 16;     // toggle for 16 cycles
  localparam int ZERO_CYCLES   = 8;      // then hold 0 for 8 cycles
  localparam int REPEAT_TIMES  = 16;     // repeat enough times to reach 16 "good blocks"

  localparam time CLK_PERIOD   = 10ns;   // i_clk period
  localparam time PHASE_DELAY  = 5ns;    // clk_n delayed from clk_p by 5ns

  // -------------------------
  // Signals
  // -------------------------
  logic i_clk;
  logic i_rst_n;
  logic clk_detector_en;

  logic clk_p;
  logic clk_n;
  logic track;

  logic clk_p_pattern_error;
  logic clk_n_pattern_error;
  logic track_pattern_error;

  // -------------------------
  // DUT
  // -------------------------
  CLK_PATTERN_DETECTOR_RX dut (
    .i_clk(i_clk),
    .i_rst_n(i_rst_n),
    .clk_detector_en(clk_detector_en),
    .clk_p(clk_p),
    .clk_n(clk_n),
    .track(track),
    .clk_p_pattern_error(clk_p_pattern_error),
    .clk_n_pattern_error(clk_n_pattern_error),
    .track_pattern_error(track_pattern_error)
  );

  // -------------------------
  // 1) i_clk toggles forever
  // -------------------------
  initial begin
    i_clk = 1'b0;
    forever #(CLK_PERIOD/2) i_clk = ~i_clk;
  end

  // -------------------------
  // 2) clk_n is delayed version of clk_p
  // -------------------------
  assign #(PHASE_DELAY) clk_n = clk_p;

  // -------------------------
  // 3) Stimulus
  // -------------------------
  initial begin
    int rep, i;

    // init
    i_rst_n         = 1'b0;
    clk_detector_en = 1'b0;
    clk_p           = 1'b0;
    track           = 1'b0;

    // reset for a few cycles
    repeat (3) @(posedge i_clk);
    i_rst_n = 1'b1;

    // enable detector
    @(posedge i_clk);
    clk_detector_en = 1'b1;
for (rep = 0; rep < 1; rep++) begin

     // extra 2 toggle
      for (i = 0; i < 18; i++) begin
      @(posedge i_clk);
        clk_p  <= 1'b1;
        track  <= 1'b1;
        
        @(negedge i_clk);
        clk_p  <= 1'b0;
        track  <= 1'b0;
          
        
      end
      clk_p <= 1'b0;
      track <= 1'b0;
      repeat (ZERO_CYCLES) @(posedge i_clk);
    end


    for (rep = 0; rep < 1; rep++) begin

     
      for (i = 0; i < TOGGLE_CYCLES; i++) begin
      @(posedge i_clk);
        clk_p  <= 1'b1;
        track  <= 1'b1;
        
        @(negedge i_clk);
        clk_p  <= 1'b0;
        track  <= 1'b0;
          
        
      end

      //extra 2 zeros
      clk_p <= 1'b0;
      track <= 1'b0;
      repeat (10) @(posedge i_clk);
    end
     

    // generate pattern blocks
    for (rep = 0; rep < REPEAT_TIMES; rep++) begin

      // A) toggle for TOGGLE_CYCLES (make clk_p and track toggle every half cycle)
      for (i = 0; i < TOGGLE_CYCLES; i++) begin
      @(posedge i_clk);
        clk_p  <= 1'b1;
        track  <= 1'b1;
        
        @(negedge i_clk);
        clk_p  <= 1'b0;
        track  <= 1'b0;
          
        
      end

      // B) hold low for ZERO_CYCLES full cycles
      clk_p <= 1'b0;
      track <= 1'b0;
      repeat (ZERO_CYCLES) @(posedge i_clk);
    end

    // let DUT settle a bit
    repeat (5) @(posedge i_clk);

    // simple check / print
    $display("clk_p_pattern_error   = %0b", clk_p_pattern_error);
    $display("clk_n_pattern_error   = %0b", clk_n_pattern_error);
    $display("track_pattern_error   = %0b", track_pattern_error);

    if ((clk_p_pattern_error === 1'b0) &&
        (clk_n_pattern_error === 1'b0) &&
        (track_pattern_error === 1'b0)) begin
      $display("PASS: all pattern_error signals deasserted (0).");
    end else begin
      $display("FAIL: one or more pattern_error signals still asserted (1).");
    end

    $stop;
  end

endmodule