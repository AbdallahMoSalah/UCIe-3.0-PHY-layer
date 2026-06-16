module mainband_ltsm_interface
(   
    output  logic                    i_mapper_en,
    output  logic [2:0]              i_width_deg_tx,
    output  logic [2:0]              i_width_deg_rx,
    output  logic [2:0]              i_lfsr_state,
    output  logic                    i_reversal_en,
    output  logic                    i_valid_pattern_en,
    output  logic                    i_pll_en,//
    output  logic [1:0]              i_pll_speed_sel,//
    output  logic                    lclk_g,//
    output  logic                    i_clk_pattern_en,
    output  logic                    i_clk_embedded_en,//

    output  logic [2:0]              i_state,
    output  logic                    demapper_en,
    output  logic                    i_pcmp_enable,
    output  logic                    i_pcmp_mode,
    output  logic [NUM_LANES-1:0]    i_pcmp_lane_mask,//
    output  logic [15:0]             i_pcmp_iter_count,
    output  logic                    i_pcmp_pattern_mode,
    output  logic                    i_pcmp_clear,
    output  logic                    i_vcmp_enable,
    output  logic                    i_vcmp_mode,
    output  logic                    i_vcmp_clear,
    output  logic                    i_clk_detector_en,
    output  logic [15:0]             i_rx_data_deser_en,
    output  logic                    i_rx_valid_deser_en,

    input logic                    o_lfsr_tx_done,
    input logic                    o_valid_done,
    input logic                    o_clk_done,

    input logic                    o_pcmp_done,
    input logic [NUM_LANES-1:0]    o_pcmp_per_lane_pass,
    input logic [15:0]             o_pcmp_agg_err_cnt,
    input logic                    o_pcmp_agg_error,
    input logic                    o_vcmp_done,
    input logic                    o_vcmp_pass,
    input logic                    o_valid_frame_error,
    input logic                    o_clk_p_pass,
    input logic                    o_clk_n_pass,
    input logic                    o_track_pass,
//=========================================================================

//=========================================================================

//=========================================================================

//=========================================================================

//=========================================================================
    input logic        mb_tx_pattern_en,
    input logic [2:0]  mb_tx_pattern_setup,
    input logic [1:0]  mb_tx_data_pattern_sel,
    input logic        mb_tx_val_pattern_sel,
    input logic        mb_rx_compare_en,
    input logic [1:0]  mb_rx_compare_setup,
    input logic        clear_error_req,
    input logic [2:0]  mb_rx_data_lane_map,
    input logic [2:0]  mb_tx_data_lane_map,

    // =========================================================================
    // Unified Mainband Inputs
    // =========================================================================
    output  logic [15:0] mb_rx_perlane_pass,
    output  logic        mb_tx_pattern_count_done,

    // =========================================================================
    // Substate Discrete Outputs/Inputs
    // =========================================================================
    input  logic        mb_lane_reversal_req,
    input  logic        active,
    input  logic        mb_tx_lfsr_rst,
    input  logic        mb_rx_lfsr_rst,
    input  logic        mb_rx_vcomp_mode,
    input  logic        mb_rx_data_en,
    input  logic        mb_rx_valid_en,
    output logic        repairclk_rtrk_pass,
    output logic        repairclk_rckn_pass,
    output logic        repairclk_rckp_pass,
    output logic        repairval_RVLD_L_pass,
    output logic        mb_rx_compare_done,
);
    always_comb begin :
    //mapper and demapper
        i_mapper_en = active;
        demapper_en = active;
    //width_deg
        i_width_deg_tx = mb_tx_data_lane_map;
        i_width_deg_rx = mb_rx_data_lane_map;
        i_reversal_en = mb_lane_reversal_req;
        i_pcmp_clear = clear_error_req || mb_tx_lfsr_rst || mb_rx_lfsr_rst;
        i_vcmp_clear = i_pcmp_clear;
        i_vcmp_mode = mb_rx_vcomp_mode;
        mb_rx_perlane_pass = o_pcmp_per_lane_pass;
        mb_tx_pattern_count_done = o_lfsr_tx_done || o_valid_done || o_clk_done;
        repairclk_rtrk_pass = o_track_pass;
        repairclk_rckn_pass = o_clk_n_pass;
        repairclk_rckp_pass = o_clk_p_pass;
        repairval_RVLD_L_pass = o_vcmp_pass;
        mb_rx_compare_done = o_pcmp_done || o_vcmp_done || o_clk_done;
    end 

    always_comb begin : lfsr_state_generator
        if (active)
            i_lfsr_state = 3'b100; //Data Transfer
        else begin
            if (mb_tx_lfsr_rst)
                i_lfsr_state = 3'b001; //Reset
            else if (mb_tx_pattern_en && mb_tx_pattern_setup[0]) begin
                if (mb_tx_data_pattern_sel[0])
                    i_lfsr_state = 3'b010; //PRBS Pattern
                else
                    i_lfsr_state = 3'b011; //Per lane ID pattern
            end else begin
                i_lfsr_state = 3'b000; //Idle
            end 
        end 
        i_state = i_lfsr_state;
    end

    always_comb begin : valid_pattern_en_generator
        if (mb_tx_pattern_en && mb_tx_pattern_setup[1])
            i_valid_pattern_en = 1'b1;
        else
            i_valid_pattern_en = 1'b0;
    end

    always_comb begin : i_clk_pattern_en_generator
        if (mb_tx_pattern_en && mb_tx_pattern_setup[2])
            i_clk_pattern_en= 1'b1;
        else
            i_clk_pattern_en = 1'b0;
    end

    always_comb begin : i_pcmp_enable_generator
        if (mb_rx_compare_en && (mb_rx_compare_setup == 2'b00 || mb_rx_compare_setup == 2'b01)) begin
            i_pcmp_enable = 1'b1;
        end else begin
            i_pcmp_enable = 1'b0;
        end
        i_pcmp_mode = !mb_rx_compare_setup[0];
    end
    
    always_comb begin : i_pcmp_iter_count_generator
        if (mb_tx_data_pattern_sel[0]) begin
            i_pcmp_iter_count = 16'd128; //PRBS Pattern
            i_pcmp_pattern_mode = 1'b1;
        end else begin
            i_pcmp_iter_count = 16'd64; //Per lane ID pattern
            i_pcmp_pattern_mode = 1'b0; 
        end
    end

    always_comb begin : valid_compare_en_generator
        if (mb_rx_compare_en && mb_rx_compare_setup == 2'b10)
            i_vcmp_enable = 1'b1;
        else
            i_vcmp_enable = 1'b0;
    end
    
    always_comb begin : clk_compare_en_generator
        if (mb_rx_compare_en && mb_rx_compare_setup == 2'b11)
            i_clk_detector_en = 1'b1;
        else
            i_clk_detector_en = 1'b0;
    end

    always_comb begin : deserializer_en_generator
        case (mb_rx_data_lane_map)
            3'b011: i_rx_data_deser_en = 16'hffff;
            3'b001: i_rx_data_deser_en = 16'h00ff;
            3'b010: i_rx_data_deser_en = 16'hff00;
            3'b100: i_rx_data_deser_en = 16'h000f;
            3'b101: i_rx_data_deser_en = 16'h00f0;
            default: i_rx_data_deser_en = 16'h0000;
        endcase 
        i_rx_valid_deser_en = mb_rx_valid_en;
    end
endmodule