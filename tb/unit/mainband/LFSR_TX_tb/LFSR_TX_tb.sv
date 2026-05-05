module LFSR_TX_tb;

  localparam int WIDTH = 32;

  // States (Updated to match DUT 3-bit encoding [cite: 352-354])
  localparam logic [2:0] IDLE           = 3'b000;
  localparam logic [2:0] CLEAR_LFSR     = 3'b001;
  localparam logic [2:0] PATTERN_LFSR   = 3'b010;
  localparam logic [2:0] PER_LANE_IDE   = 3'b011;
  localparam logic [2:0] DATA_TRANSFER  = 3'b100;

  // Degrade modes (match DUT [cite: 354-356])
  localparam logic [2:0] NONE_DEGRADE           = 3'b000;
  localparam logic [2:0] DEGRADE_LANES_0_TO_7   = 3'b001;
  localparam logic [2:0] DEGRADE_LANES_8_TO_15  = 3'b010;
  localparam logic [2:0] DEGRADE_LANES_0_TO_15  = 3'b011;
  localparam logic [2:0] DEGRADE_LANES_0_TO_3   = 3'b100;
  localparam logic [2:0] DEGRADE_LANES_4_TO_7   = 3'b101;

  // Signals
  logic              i_clk;
  logic              i_rst_n;
  logic [2:0]        i_state;
  logic              i_scramble_en;
  logic [2:0]        i_width_deg_lfsr;
  logic              i_reversal_en;
  logic              i_active_state_entered;

  // Array interfaces to match DUT 
  logic [WIDTH-1:0]  i_lane [0:15];
  logic [WIDTH-1:0]  o_lane [0:15];

  logic               o_Lfsr_tx_done;
  logic               o_valid_frame_en;

  // DUT Instance
  LFSR_TX #(.WIDTH(WIDTH)) dut (
    .i_clk                  (i_clk),
    .i_rst_n                (i_rst_n),
    .i_state                (i_state),
    .i_scramble_en          (i_scramble_en),
    .i_width_deg_lfsr       (i_width_deg_lfsr),
    .i_reversal_en          (i_reversal_en),
    .i_active_state_entered (i_active_state_entered),
    .i_lane                 (i_lane),
    .o_lane                 (o_lane),
    .o_Lfsr_tx_done         (o_Lfsr_tx_done),
    .o_valid_frame_en       (o_valid_frame_en)
  );

  // Clock generation: 10 ns period [cite: 564]
  initial i_clk = 0;
  always #5 i_clk = ~i_clk;


  // Stimulus
  initial begin
    // Defaults
    i_state = IDLE;
    i_scramble_en = 0;
    i_width_deg_lfsr = DEGRADE_LANES_0_TO_15;
    i_reversal_en = 0;
    i_active_state_entered = 0;

    // Simple lane inputs
    for (int j = 0; j < 16; j++) begin
        i_lane[j] = {4{j[3:0]}}; // e.g., Lane 1 = 32'h0000_1111
    end

    // Reset
    i_rst_n = 0;
    repeat (3) @(posedge i_clk);         //idle
      i_rst_n = 1; i_state = IDLE; 
    repeat (1) @(posedge i_clk);
     i_rst_n = 1; i_state = CLEAR_LFSR; //clear lfsr
    repeat (1) @(posedge i_clk);
    i_rst_n = 1; i_state = IDLE; //idle
    @(posedge i_clk);
    i_rst_n = 1; i_state = PATTERN_LFSR; // pattern_lfsr scr
    repeat (129) @(posedge i_clk);
    i_rst_n = 1; i_state = IDLE;  // idle
    @(posedge i_clk);
     i_rst_n = 1; i_state = CLEAR_LFSR;  //clear lfsr
    repeat (1) @(posedge i_clk);
    i_rst_n = 1; i_state = IDLE; // idle
    @(posedge i_clk);
    i_rst_n = 1; i_state = DATA_TRANSFER; i_scramble_en=1; i_active_state_entered = 1 ;//Data Transfer
    repeat (32) @(posedge i_clk);
    i_rst_n = 1; i_state = IDLE;i_active_state_entered = 0 ;
    repeat (1) @(posedge i_clk);
     i_rst_n = 1; i_state = CLEAR_LFSR; //clear lfsr
    repeat (1) @(posedge i_clk);
    i_rst_n = 1; i_state = IDLE; //idle
    @(posedge i_clk);
    i_rst_n = 1; i_state = PER_LANE_IDE; i_scramble_en=0; //per lane ide
    repeat (65) @(posedge i_clk);
 
    i_rst_n = 0;i_reversal_en = 1; 
    repeat (3) @(posedge i_clk);         //idle
      i_rst_n = 1; i_state = IDLE; 
    repeat (1) @(posedge i_clk);
     i_rst_n = 1; i_state = CLEAR_LFSR; //clear lfsr
    repeat (1) @(posedge i_clk);
    i_rst_n = 1; i_state = IDLE; //idle
    @(posedge i_clk);
    i_rst_n = 1; i_state = PATTERN_LFSR; // pattern_lfsr scr
    repeat (129) @(posedge i_clk);
    i_rst_n = 1; i_state = IDLE;  // idle
    @(posedge i_clk);
     i_rst_n = 1; i_state = CLEAR_LFSR;  //clear lfsr
    repeat (1) @(posedge i_clk);
    i_rst_n = 1; i_state = IDLE; // idle
    @(posedge i_clk);
    i_rst_n = 1; i_state = DATA_TRANSFER; i_scramble_en=1; i_active_state_entered = 1 ;//Data Transfer
    repeat (32) @(posedge i_clk);
    i_rst_n = 1; i_state = IDLE;i_active_state_entered = 0 ;
    repeat (1) @(posedge i_clk);
     i_rst_n = 1; i_state = CLEAR_LFSR; //clear lfsr
    repeat (1) @(posedge i_clk);
    i_rst_n = 1; i_state = IDLE; //idle
    @(posedge i_clk);
    i_rst_n = 1; i_state = PER_LANE_IDE; i_scramble_en=0; //per lane ide
    repeat (65) @(posedge i_clk);



    // Clear LFSR once
    repeat (2) @(posedge i_clk);

    $stop;
  end

endmodule