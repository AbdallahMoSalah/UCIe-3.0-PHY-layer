module LFSR_RX_tb;

    localparam WIDTH      = 32;
    localparam CLK_PERIOD = 10;

    // FSM state codes – match DUT (3-bit)
    localparam logic [2:0] IDLE          = 3'b000;
    localparam logic [2:0] CLEAR_LFSR    = 3'b001;
    localparam logic [2:0] PATTERN_LFSR  = 3'b010;
    localparam logic [2:0] PER_LANE_IDE  = 3'b011;
    localparam logic [2:0] DATA_TRANSFER = 3'b100;

    // Degrade modes – match DUT
    localparam NONE_DEGRADE           = 3'b000;
    localparam DEGRADE_LANES_0_TO_7   = 3'b001;
    localparam DEGRADE_LANES_8_TO_15  = 3'b010;
    localparam DEGRADE_LANES_0_TO_15  = 3'b011;
    localparam DEGRADE_LANES_0_TO_3   = 3'b100;
    localparam DEGRADE_LANES_4_TO_7   = 3'b101;

    // ---------- DUT inputs ----------
    logic              i_clk;
    logic              i_rst_n;
    logic [2:0]        i_state;
    logic [2:0]        i_width_deg_lfsr;
    logic              i_active_state_entered;   // added – missing from old TB
    logic              i_descramble_en;            // corrected spelling to match DUT
    logic              i_enable_buffer;
    logic [WIDTH-1:0]  i_data_in [0:15];          // packed array – matches DUT port

    // ---------- DUT outputs ----------
    logic [WIDTH-1:0]  o_Data_by    [0:15];       // packed array – matches DUT port
    logic [WIDTH-1:0]  o_final_gene [0:15];       // packed array – matches DUT port
    logic              pattern_comp_en;            // corrected name & direction (output)

    // ---------- Clock generation ----------
    initial i_clk = 0;
    always #(CLK_PERIOD/2) i_clk = ~i_clk;

    // ---------- DUT instantiation ----------
    unit_lfsr_rx #(.WIDTH(WIDTH)) dut (
        .i_clk                  (i_clk),
        .i_rst_n                (i_rst_n),
        .i_state                (i_state),
        .i_width_deg_lfsr       (i_width_deg_lfsr),
        .i_active_state_entered (i_active_state_entered),
        .i_descramble_en         (i_descramble_en),
        .i_enable_buffer        (i_enable_buffer),
        .i_data_in              (i_data_in),
        .o_Data_by              (o_Data_by),
        .o_final_gene           (o_final_gene),
        .pattern_comp_en        (pattern_comp_en)
    );

    // ---------- Helper task: increment all lanes ----------
    task automatic inc_lanes(input int cycles);
        for (int j = 0; j < cycles; j++) begin
            @(posedge i_clk);
            foreach (i_data_in[k]) i_data_in[k] = i_data_in[k] + 1;
        end
    endtask

    // ---------- Stimulus ----------
    initial begin
        // Initialise
        i_rst_n                = 0;
        i_state                = IDLE;
        i_width_deg_lfsr       = DEGRADE_LANES_0_TO_15;
        i_active_state_entered = 0;
        i_descramble_en         = 0;
        i_enable_buffer        = 1;

        i_data_in[0]  = 32'h0000_0000; i_data_in[1]  = 32'h1111_1111;
        i_data_in[2]  = 32'h2222_2222; i_data_in[3]  = 32'h3333_3333;
        i_data_in[4]  = 32'h4444_4444; i_data_in[5]  = 32'h5555_5555;
        i_data_in[6]  = 32'h6666_6666; i_data_in[7]  = 32'h7777_7777;
        i_data_in[8]  = 32'h8888_8888; i_data_in[9]  = 32'h9999_9999;
        i_data_in[10] = 32'hAAAA_AAAA; i_data_in[11] = 32'hBBBB_BBBB;
        i_data_in[12] = 32'hCCCC_CCCC; i_data_in[13] = 32'hDDDD_DDDD;
        i_data_in[14] = 32'hEEEE_EEEE; i_data_in[15] = 32'hFFFF_FFFF;

        repeat(3) @(posedge i_clk);
        i_rst_n = 1;

        // --- IDLE (20 cycles) ---
        i_state = IDLE; 
        inc_lanes(20);

        // --- CLEAR_LFSR (2 cycles) ---
        repeat(4) @(posedge i_clk);
        i_state = CLEAR_LFSR;
        inc_lanes(2);

        i_state = IDLE;
        inc_lanes(2);

        // --- PATTERN_LFSR (100 cycles) ---
        repeat(6) @(posedge i_clk);
        i_state = PATTERN_LFSR; 
        inc_lanes(100);

        // --- Back to IDLE (2 cycles) ---
        repeat(4) @(posedge i_clk);
        i_state = IDLE;
        inc_lanes(2);

        // --- CLEAR_LFSR (2 cycles) ---
        repeat(6) @(posedge i_clk);
        i_state = CLEAR_LFSR;
        inc_lanes(2);

        i_state = IDLE; 
        inc_lanes(2);

        // --- PER_LANE_IDE (40 cycles) ---
        repeat(6) @(posedge i_clk);
        i_state = PER_LANE_IDE;
        inc_lanes(40);

        // --- Back to IDLE (2 cycles) ---
        i_state = IDLE;
        inc_lanes(2);

        // --- CLEAR_LFSR (2 cycles) ---
        repeat(4) @(posedge i_clk);
        i_state = CLEAR_LFSR;
        inc_lanes(2);

        i_state = IDLE;
        inc_lanes(2);

        // --- PATTERN_LFSR with descramble enabled (40 cycles) ---
        repeat(6) @(posedge i_clk);
        i_state = DATA_TRANSFER; i_descramble_en = 1; i_active_state_entered = 1;
        inc_lanes(40);

        // --- DATA_TRANSFER with active_state_entered pulse ---
        /*repeat(4) @(posedge i_clk);
        i_state                = DATA_TRANSFER;
        i_descramble_en         = 1;
        i_active_state_entered = 1;
        @(posedge i_clk);
        i_active_state_entered = 0;
        inc_lanes(20);*/

        repeat(8) @(posedge i_clk);
        $stop;
    end

endmodule