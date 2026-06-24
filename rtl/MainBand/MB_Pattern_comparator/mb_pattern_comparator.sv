
// Module: MB_pattern_comparator
// Status: done 
// Description: Pattern comparator for MainBand lanes (Per-Lane & Aggregate modes)
// Author: Mohamed Anwar
module PATTERN_COMPARATOR #(
    parameter WIDTH = 32
)(
    input  wire        i_clk,
    input  wire        i_rst_n,
    input  wire        i_active,                              // Active mode flag
    input  wire [2:0]  i_width_deg_comp,                     // Lane degradation mode for comparison
    input  wire [1:0]  i_type_of_com,
    input  wire        i_enable_pattern_com,
    input  wire [15:0] i_max_error_threshold_per_lane_ID, // Threshold for per-lane error disabling
    input  wire [15:0] i_max_error_threshold_aggergate,   // Aggregate error threshold

    // Reference PRBS / Generator
    input  wire [WIDTH-1:0] i_local_gen_0, i_local_gen_1, i_local_gen_2, i_local_gen_3,
    input  wire [WIDTH-1:0] i_local_gen_4, i_local_gen_5, i_local_gen_6, i_local_gen_7,
    input  wire [WIDTH-1:0] i_local_gen_8, i_local_gen_9, i_local_gen_10, i_local_gen_11,
    input  wire [WIDTH-1:0] i_local_gen_12, i_local_gen_13, i_local_gen_14, i_local_gen_15,

    // Received Data
    input  wire [WIDTH-1:0] i_data_0,  i_data_1,  i_data_2,  i_data_3,
    input  wire [WIDTH-1:0] i_data_4,  i_data_5,  i_data_6,  i_data_7,
    input  wire [WIDTH-1:0] i_data_8,  i_data_9,  i_data_10, i_data_11,
    input  wire [WIDTH-1:0] i_data_12, i_data_13, i_data_14, i_data_15,

    output reg  [15:0]      o_per_lane_error,
    output reg  [31:0]      o_error_counter,
    output reg              o_error_done,

    // Bypassed Data
    output wire [WIDTH-1:0] o_data_0,  o_data_1,  o_data_2,  o_data_3,
    output wire [WIDTH-1:0] o_data_4,  o_data_5,  o_data_6,  o_data_7,
    output wire [WIDTH-1:0] o_data_8,  o_data_9,  o_data_10, o_data_11,
    output wire [WIDTH-1:0] o_data_12, o_data_13, o_data_14, o_data_15
);

    // =========================================================================
    // Lane Degradation Modes
    // =========================================================================
    localparam NONE_DEGRADE           = 3'b000;
    localparam DEGRADE_LANES_0_TO_7   = 3'b001;
    localparam DEGRADE_LANES_8_TO_15  = 3'b010;
    localparam DEGRADE_LANES_0_TO_15  = 3'b011;
    localparam DEGRADE_LANES_0_TO_3   = 3'b100;
    localparam DEGRADE_LANES_4_TO_7   = 3'b101;

    // =========================================================================
    // Lane-Active Mask based on i_width_deg_comp
    // =========================================================================
    reg [15:0] lane_active;
    always @(*) begin
        case (i_width_deg_comp)
            DEGRADE_LANES_0_TO_7:   lane_active = 16'h00FF; // Lanes 0-7
            DEGRADE_LANES_8_TO_15:  lane_active = 16'hFF00; // Lanes 8-15
            DEGRADE_LANES_0_TO_15:  lane_active = 16'hFFFF; // All 16 lanes
            DEGRADE_LANES_0_TO_3:   lane_active = 16'h000F; // Lanes 0-3
            DEGRADE_LANES_4_TO_7:   lane_active = 16'h00F0; // Lanes 4-7
            default:                lane_active = 16'h0000; // No lanes (NONE_DEGRADE)
        endcase
    end

    // =========================================================================
    // Arrays for easier indexing
    // =========================================================================
    wire [WIDTH-1:0] w_local_gen [0:15];
    wire [WIDTH-1:0] w_data [0:15];

    assign w_local_gen[0] = i_local_gen_0;  assign w_data[0] = i_data_0;
    assign w_local_gen[1] = i_local_gen_1;  assign w_data[1] = i_data_1;
    assign w_local_gen[2] = i_local_gen_2;  assign w_data[2] = i_data_2;
    assign w_local_gen[3] = i_local_gen_3;  assign w_data[3] = i_data_3;
    assign w_local_gen[4] = i_local_gen_4;  assign w_data[4] = i_data_4;
    assign w_local_gen[5] = i_local_gen_5;  assign w_data[5] = i_data_5;
    assign w_local_gen[6] = i_local_gen_6;  assign w_data[6] = i_data_6;
    assign w_local_gen[7] = i_local_gen_7;  assign w_data[7] = i_data_7;
    assign w_local_gen[8] = i_local_gen_8;  assign w_data[8] = i_data_8;
    assign w_local_gen[9] = i_local_gen_9;  assign w_data[9] = i_data_9;
    assign w_local_gen[10]= i_local_gen_10; assign w_data[10]= i_data_10;
    assign w_local_gen[11]= i_local_gen_11; assign w_data[11]= i_data_11;
    assign w_local_gen[12]= i_local_gen_12; assign w_data[12]= i_data_12;
    assign w_local_gen[13]= i_local_gen_13; assign w_data[13]= i_data_13;
    assign w_local_gen[14]= i_local_gen_14; assign w_data[14]= i_data_14;
    assign w_local_gen[15]= i_local_gen_15; assign w_data[15]= i_data_15;

    // =========================================================================
    // Bypass Logic (Active state)
    // =========================================================================
    // When i_active is high, bypass the descrambled data directly to output.
    // Otherwise, output zeros.
    assign o_data_0  = i_active ? i_data_0  : {WIDTH{1'b0}};
    assign o_data_1  = i_active ? i_data_1  : {WIDTH{1'b0}};
    assign o_data_2  = i_active ? i_data_2  : {WIDTH{1'b0}};
    assign o_data_3  = i_active ? i_data_3  : {WIDTH{1'b0}};
    assign o_data_4  = i_active ? i_data_4  : {WIDTH{1'b0}};
    assign o_data_5  = i_active ? i_data_5  : {WIDTH{1'b0}};
    assign o_data_6  = i_active ? i_data_6  : {WIDTH{1'b0}};
    assign o_data_7  = i_active ? i_data_7  : {WIDTH{1'b0}};
    assign o_data_8  = i_active ? i_data_8  : {WIDTH{1'b0}};
    assign o_data_9  = i_active ? i_data_9  : {WIDTH{1'b0}};
    assign o_data_10 = i_active ? i_data_10 : {WIDTH{1'b0}};
    assign o_data_11 = i_active ? i_data_11 : {WIDTH{1'b0}};
    assign o_data_12 = i_active ? i_data_12 : {WIDTH{1'b0}};
    assign o_data_13 = i_active ? i_data_13 : {WIDTH{1'b0}};
    assign o_data_14 = i_active ? i_data_14 : {WIDTH{1'b0}};
    assign o_data_15 = i_active ? i_data_15 : {WIDTH{1'b0}};

    // =========================================================================
    // Functions for Bit Mismatch Counting (Popcount)
    // =========================================================================
    function automatic [4:0] count_ones_16(input [15:0] val);
        integer i;
        begin
            count_ones_16 = 0;
            for (i = 0; i < 16; i = i + 1) begin
                count_ones_16 = count_ones_16 + val[i];
            end
        end
    endfunction

    // =========================================================================
    // Combinational Mismatch Checking (2-stage as per spec: Lower & Upper 16)
    // =========================================================================
    wire [15:0] mismatch_lower [0:15];
    wire [15:0] mismatch_upper [0:15];
    wire [4:0]  lane_mismatch_part_1 [0:15];
    wire [4:0]  lane_mismatch_part_2 [0:15];
    wire [5:0]  lane_total_mismatch  [0:15];

    genvar g;
    generate
        for (g = 0; g < 16; g = g + 1) begin : gen_cmp
            // Bitwise XOR per lane
            assign mismatch_lower[g] = w_local_gen[g][15:0]  ^ w_data[g][15:0];
            assign mismatch_upper[g] = w_local_gen[g][31:16] ^ w_data[g][31:16];
            
            // Popcount 16-bit parts
            assign lane_mismatch_part_1[g] = count_ones_16(mismatch_lower[g]);
            assign lane_mismatch_part_2[g] = count_ones_16(mismatch_upper[g]);
            
            // Total mismatch per lane in a cycle
            assign lane_total_mismatch[g]  = lane_mismatch_part_1[g] + lane_mismatch_part_2[g];
        end
    endgenerate

    // =========================================================================
    // Iteration Count & Accumulation logic
    // =========================================================================
    reg [7:0]   iteration_ctr;
    reg         in_progress;
    
    // Per-lane accumulated errors
    reg [15:0]  lane_err_accum [0:15];

    integer k;

    // FSM & Evaluation Logic
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            iteration_ctr    <= 8'd0;
            in_progress      <= 1'b0;
            o_error_done     <= 1'b0;
            o_error_counter  <= 32'd0;
            o_per_lane_error <= 16'd0;
            
            for (k = 0; k < 16; k = k + 1) begin
                lane_err_accum[k] <= 16'd0;
            end
        end else begin
            // Proceed with comparison ONLY IF i_active is 0 and enabled
            if (i_enable_pattern_com && !i_active) begin
                if (!in_progress) begin
                    // Initial setup/edge of compare triggering
                    in_progress      <= 1'b1;
                    iteration_ctr    <= 8'd0;
                    o_error_done     <= 1'b0;
                    o_error_counter  <= 32'd0;
                    o_per_lane_error <= 16'd0;
                    
                    for (k = 0; k < 16; k = k + 1) begin
                        lane_err_accum[k] <= 16'd0; // start fresh
                    end
                end else if (iteration_ctr < 128) begin
                    if (iteration_ctr < 5) begin
                        $display("%m at %t: lane_active=%h, lane0_gen=%h, lane0_data=%h, mismatch=%h",
                                 $time, lane_active, w_local_gen[0], w_data[0], mismatch_lower[0]);
                    end
                    // ACCUMULATE — only count errors on active lanes
                    for (k = 0; k < 16; k = k + 1) begin
                        if (lane_active[k]) begin
                            lane_err_accum[k] <= lane_err_accum[k] + lane_total_mismatch[k];
                        end
                    end
                    // Accumulate aggregate errors — only from active lanes
                    o_error_counter <= o_error_counter + 
                                       (lane_active[0]  ? lane_total_mismatch[0]  : 6'd0) +
                                       (lane_active[1]  ? lane_total_mismatch[1]  : 6'd0) +
                                       (lane_active[2]  ? lane_total_mismatch[2]  : 6'd0) +
                                       (lane_active[3]  ? lane_total_mismatch[3]  : 6'd0) +
                                       (lane_active[4]  ? lane_total_mismatch[4]  : 6'd0) +
                                       (lane_active[5]  ? lane_total_mismatch[5]  : 6'd0) +
                                       (lane_active[6]  ? lane_total_mismatch[6]  : 6'd0) +
                                       (lane_active[7]  ? lane_total_mismatch[7]  : 6'd0) +
                                       (lane_active[8]  ? lane_total_mismatch[8]  : 6'd0) +
                                       (lane_active[9]  ? lane_total_mismatch[9]  : 6'd0) +
                                       (lane_active[10] ? lane_total_mismatch[10] : 6'd0) +
                                       (lane_active[11] ? lane_total_mismatch[11] : 6'd0) +
                                       (lane_active[12] ? lane_total_mismatch[12] : 6'd0) +
                                       (lane_active[13] ? lane_total_mismatch[13] : 6'd0) +
                                       (lane_active[14] ? lane_total_mismatch[14] : 6'd0) +
                                       (lane_active[15] ? lane_total_mismatch[15] : 6'd0);

                    iteration_ctr <= iteration_ctr + 1'b1;
                end else begin
                    // FINISH
                    in_progress <= 1'b0;
                    o_error_done <= 1'b1;
                    
                    // Evaluate threshold limits — only for active lanes
                    for (k = 0; k < 16; k = k + 1) begin
                        if (lane_active[k] && lane_err_accum[k] > i_max_error_threshold_per_lane_ID) begin
                            o_per_lane_error[k] <= 1'b1;
                        end else begin
                            o_per_lane_error[k] <= 1'b0;
                        end
                    end
                end
            end else begin
                // Reset/Idle when enable is low OR Active mode is high
                in_progress      <= 1'b0;
                o_error_done     <= 1'b0;   // FIX: clear done flag so next phase doesn't read stale result
                o_per_lane_error <= 16'd0;  // FIX: clear per-lane errors so stale bits don't carry over
                o_error_counter  <= 32'd0;
                iteration_ctr    <= 8'd0;
                for (k = 0; k < 16; k = k + 1)
                    lane_err_accum[k] <= 16'd0;
            end
        end
    end

endmodule