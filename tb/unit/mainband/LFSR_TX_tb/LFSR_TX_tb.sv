

module LFSR_TX_tb;

  localparam int WIDTH = 32;

  // States (match DUT)
  localparam logic [1:0] IDLE        = 2'b00;
  localparam logic [1:0] CLEAR_LFSR   = 2'b01;
  localparam logic [1:0] PATTERN_LFSR = 2'b10;
  localparam logic [1:0] PER_LANE_IDE = 2'b11;

  // Degrade modes (match DUT)
    localparam NONE_DEGRADE           = 3'b000;
    localparam DEGRADE_LANES_0_TO_7   = 3'b001;
    localparam DEGRADE_LANES_8_TO_15  = 3'b010;
    localparam DEGRADE_LANES_0_TO_15  = 3'b011;
    localparam DEGRADE_LANES_0_TO_3   = 3'b100;
    localparam DEGRADE_LANES_4_TO_7   = 3'b101;

  logic i_clk, i_rst_n;
  logic [1:0] i_state;
  logic scramble_en;
  logic [2:0] i_width_deg_lfsr;
  logic reversal_en;

  logic [WIDTH-1:0] i_lane_0,  i_lane_1,  i_lane_2,  i_lane_3;
  logic [WIDTH-1:0] i_lane_4,  i_lane_5,  i_lane_6,  i_lane_7;
  logic [WIDTH-1:0] i_lane_8,  i_lane_9,  i_lane_10, i_lane_11;
  logic [WIDTH-1:0] i_lane_12, i_lane_13, i_lane_14, i_lane_15;

  wire [WIDTH-1:0] o_lane_0,  o_lane_1,  o_lane_2,  o_lane_3;
  wire [WIDTH-1:0] o_lane_4,  o_lane_5,  o_lane_6,  o_lane_7;
  wire [WIDTH-1:0] o_lane_8,  o_lane_9,  o_lane_10, o_lane_11;
  wire [WIDTH-1:0] o_lane_12, o_lane_13, o_lane_14, o_lane_15;

  wire o_Lfsr_tx_done;
  wire valid_frame_en;

  // DUT
  LFSR_TX #(.WIDTH(WIDTH)) dut (
    .i_clk(i_clk),
    .i_rst_n(i_rst_n),
    .i_state(i_state),
    .scramble_en(scramble_en),
    .i_width_deg_lfsr(i_width_deg_lfsr),
    .reversal_en(reversal_en),

    .i_lane_0(i_lane_0),   .i_lane_1(i_lane_1),
    .i_lane_2(i_lane_2),   .i_lane_3(i_lane_3),
    .i_lane_4(i_lane_4),   .i_lane_5(i_lane_5),
    .i_lane_6(i_lane_6),   .i_lane_7(i_lane_7),
    .i_lane_8(i_lane_8),   .i_lane_9(i_lane_9),
    .i_lane_10(i_lane_10), .i_lane_11(i_lane_11),
    .i_lane_12(i_lane_12), .i_lane_13(i_lane_13),
    .i_lane_14(i_lane_14), .i_lane_15(i_lane_15),

    .o_lane_0(o_lane_0),   .o_lane_1(o_lane_1),
    .o_lane_2(o_lane_2),   .o_lane_3(o_lane_3),
    .o_lane_4(o_lane_4),   .o_lane_5(o_lane_5),
    .o_lane_6(o_lane_6),   .o_lane_7(o_lane_7),
    .o_lane_8(o_lane_8),   .o_lane_9(o_lane_9),
    .o_lane_10(o_lane_10), .o_lane_11(o_lane_11),
    .o_lane_12(o_lane_12), .o_lane_13(o_lane_13),
    .o_lane_14(o_lane_14), .o_lane_15(o_lane_15),

    .o_Lfsr_tx_done(o_Lfsr_tx_done),
    .valid_frame_en(valid_frame_en)
  );

  // Clock: 10 ns period
  initial i_clk = 0;
  always #5 i_clk = ~i_clk;


  // Stimulus
  initial begin
    // Defaults
    i_state = IDLE;
    scramble_en = 0;
    i_width_deg_lfsr = DEGRADE_LANES_0_TO_15;
    reversal_en = 0;

    // Simple lane inputs
    i_lane_0  = 32'h0000_0000; i_lane_1  = 32'h1111_1111;
    i_lane_2  = 32'h2222_2222; i_lane_3  = 32'h3333_3333;
    i_lane_4  = 32'h4444_4444; i_lane_5  = 32'h5555_5555;
    i_lane_6  = 32'h6666_6666; i_lane_7  = 32'h7777_7777;
    i_lane_8  = 32'h8888_8888; i_lane_9  = 32'h9999_9999;
    i_lane_10 = 32'hAAAA_AAAA; i_lane_11 = 32'hBBBB_BBBB;
    i_lane_12 = 32'hCCCC_CCCC; i_lane_13 = 32'hDDDD_DDDD;
    i_lane_14 = 32'hEEEE_EEEE; i_lane_15 = 32'hFFFF_FFFF;

    // Reset
    i_rst_n = 0;
    repeat (3) @(posedge i_clk);         //idle
      i_rst_n = 1; i_state = IDLE; scramble_en=0;
    repeat (1) @(posedge i_clk);
     i_rst_n = 1; i_state = CLEAR_LFSR; scramble_en=0; //clear lfsr
    repeat (1) @(posedge i_clk);
    i_rst_n = 1; i_state = IDLE; scramble_en=0; //idle
    @(posedge i_clk);
    i_rst_n = 1; i_state = PATTERN_LFSR; scramble_en=0; // pattern_lfsr scr
    repeat (128) @(posedge i_clk);
    i_rst_n = 1; i_state = IDLE; scramble_en=0;  // idle
    @(posedge i_clk);
     i_rst_n = 1; i_state = CLEAR_LFSR; scramble_en=0; //clear lfsr
    repeat (1) @(posedge i_clk);
    i_rst_n = 1; i_state = IDLE; scramble_en=0;  // idle
    @(posedge i_clk);
    i_rst_n = 1; i_state = PATTERN_LFSR; scramble_en=1;  //pattern lfsr
    repeat (32) @(posedge i_clk);
    i_rst_n = 1; i_state = IDLE; scramble_en=1;
    repeat (1) @(posedge i_clk);
     i_rst_n = 1; i_state = CLEAR_LFSR; scramble_en=1; //clear lfsr
    repeat (1) @(posedge i_clk);
    i_rst_n = 1; i_state = IDLE; scramble_en=0; //idle
    @(posedge i_clk);
    i_rst_n = 1; i_state = PER_LANE_IDE; scramble_en=0; //per lane ide
    repeat (64) @(posedge i_clk);
 
   i_rst_n = 1;reversal_en = 1;          /////////////// reversal
    repeat (3) @(posedge i_clk);         //idle
      i_rst_n = 1; i_state = IDLE; scramble_en=0;
    repeat (1) @(posedge i_clk);
     i_rst_n = 1; i_state = CLEAR_LFSR; scramble_en=0; //clear lfsr
    repeat (1) @(posedge i_clk);
    i_rst_n = 1; i_state = IDLE; scramble_en=0; //idle
    @(posedge i_clk);
    i_rst_n = 1; i_state = PATTERN_LFSR; scramble_en=0; // pattern_lfsr scr
    repeat (128) @(posedge i_clk);
    i_rst_n = 1; i_state = IDLE; scramble_en=0;  // idle
    @(posedge i_clk);
     i_rst_n = 1; i_state = CLEAR_LFSR; scramble_en=0; //clear lfsr
    repeat (1) @(posedge i_clk);
    i_rst_n = 1; i_state = IDLE; scramble_en=0;  // idle
    @(posedge i_clk);
    i_rst_n = 1; i_state = PATTERN_LFSR; scramble_en=1;  //pattern lfsr
    repeat (32) @(posedge i_clk);
    i_rst_n = 1; i_state = IDLE; scramble_en=1;
    repeat (1) @(posedge i_clk);
     i_rst_n = 1; i_state = CLEAR_LFSR; scramble_en=1; //clear lfsr
    repeat (1) @(posedge i_clk);
    i_rst_n = 1; i_state = IDLE; scramble_en=0; //idle
    @(posedge i_clk);
    i_rst_n = 1; i_state = PER_LANE_IDE; scramble_en=0; //per lane ide
    repeat (64) @(posedge i_clk);



    // Clear LFSR once
    repeat (2) @(posedge i_clk);

    // Run PATTERN_LFSR for lanes 0..7 (pattern only if scramble_en=0
   

    // Run PER_LANE_IDE for lanes 0
    $stop;
  end

endmodule