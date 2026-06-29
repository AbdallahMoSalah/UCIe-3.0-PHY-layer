module mainband_ltsm_interface #(
    parameter int NUM_LANES = 16
) (   
    output  logic                    i_mapper_en,
    output  logic [2:0]              i_width_deg_tx,
    output  logic [2:0]              i_width_deg_rx,
    output  logic [2:0]              i_lfsr_state,
    output  logic                    i_reversal_en,
    output  logic                    i_valid_pattern_en,
    output  logic                    i_clk_pattern_en,
    output  logic                    i_clk_embedded_en,

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
    output  logic [NUM_LANES-1:0]    i_rx_data_deser_en,
    output  logic                    i_rx_valid_deser_en,

    input logic                    o_lfsr_tx_done,
    input logic                    o_valid_done,
    input logic                    o_clk_done,

    input logic                    o_pcmp_done,
    input logic [NUM_LANES-1:0]    o_pcmp_per_lane_pass,
    input logic                    o_vcmp_done,
    input logic                    o_vcmp_pass,
    input logic                    o_valid_frame_error,
    input logic                    o_clk_p_pass,
    input logic                    o_clk_n_pass,
    input logic                    o_track_pass,
    input logic                    i_aggr_err,






    input logic [NUM_LANES-1:0] reg_lane_mask,
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
    input logic [2:0]  mb_rx_pattern_setup,
    input logic [1:0]  mb_rx_data_pattern_sel,
    input logic        clear_error_req,
    input logic [2:0]  mb_rx_data_lane_map,
    input logic [2:0]  mb_tx_data_lane_map,

    input logic        mb_clk_embedded_en,

    // =========================================================================
    // Unified Mainband Inputs
    // =========================================================================
    output  logic [NUM_LANES-1:0] mb_rx_perlane_pass,
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
    output logic        mb_aggr_err,
    output logic        mb_rx_compare_done
);

    logic [NUM_LANES-1:0] internal_lane_mask;

    always_comb begin
    //mapper and demapper
        i_mapper_en = active;
        demapper_en = active;
    //width_deg
        i_width_deg_tx = mb_tx_data_lane_map;
        i_width_deg_rx = mb_rx_data_lane_map;
        i_reversal_en = mb_lane_reversal_req;
        // The pattern/valid comparators are RECEIVE-side resources: clear them
        // only on receive-side events (a new test's clear_error_req, or the RX
        // LFSR reset). Do NOT mix in mb_tx_lfsr_rst — in a bidirectional D2C
        // point test (e.g. MBINIT.REPAIRMB) a die holds its TX LFSR reset for the
        // whole SB clear-error handshake while simultaneously comparing the
        // partner's pattern; folding tx_lfsr_rst into the clear would zero the
        // comparator's iteration counter every cycle and o_pcmp_done never fires.
        i_pcmp_clear = clear_error_req || mb_rx_lfsr_rst;
        i_vcmp_clear = i_pcmp_clear;
        i_vcmp_mode = mb_rx_vcomp_mode;
        mb_rx_perlane_pass = o_pcmp_per_lane_pass;
        mb_tx_pattern_count_done = o_lfsr_tx_done || o_valid_done || o_clk_done;
        repairclk_rtrk_pass = o_track_pass;
        repairclk_rckn_pass = o_clk_n_pass;
        repairclk_rckp_pass = o_clk_p_pass;
        repairval_RVLD_L_pass = o_vcmp_pass;
        mb_rx_compare_done = o_pcmp_done || o_vcmp_done || o_clk_done;

        i_clk_embedded_en = mb_clk_embedded_en;
        mb_aggr_err = i_aggr_err;
    end 

    always_comb begin : lfsr_state_generator
        if (active)
            i_lfsr_state = 3'b100; //Data Transfer
        else begin
            if (mb_tx_lfsr_rst) begin 
                i_lfsr_state = 3'b001; //Reset
            end else if (mb_tx_pattern_en && mb_tx_pattern_setup[0]) begin
                if (!mb_tx_data_pattern_sel[0])
                    i_lfsr_state = 3'b010; //PRBS Pattern
                else
                    i_lfsr_state = 3'b011; //Per lane ID pattern
            end else begin
                i_lfsr_state = 3'b000; //Idle
            end 
        end 
    end

    always_comb begin : i_state_generator
        if (active)
            i_state = 3'b100; //Data Transfer
        else begin
            // RX LFSR reset is driven as IDLE (3'b000), NOT the dedicated
            // CLEAR_LFSR code (3'b001). In unit_lfsr_rx the IDLE state reloads the
            // per-lane LFSRs with SEED every cycle — exactly what CLEAR_LFSR does —
            // so the reseed still happens. The reason we must NOT emit CLEAR_LFSR
            // here is the lfsr_rx edge-detect FSM: a D2C point test (e.g.
            // MBINIT.REPAIRMB) pulses mb_rx_lfsr_rst in the cycle immediately
            // before mb_rx_compare_en rises, so i_state would step 0->1->3 in
            // back-to-back cycles. The FSM consumes the CLEAR edge (IDLE->CLEAR)
            // and, while returning CLEAR->IDLE, latches i_state_reg=PER_LANE,
            // so it never sees the edge into PER_LANE/PATTERN and pattern_comp_en
            // never fires (comparator stalls, o_pcmp_done never asserts). Driving
            // IDLE keeps lfsr_rx in IDLE through the reset so the 0->pattern edge
            // is detected cleanly. The pattern comparator is still cleared via
            // i_pcmp_clear (which includes mb_rx_lfsr_rst), independent of i_state.
            if (mb_rx_lfsr_rst)
                i_state = 3'b000; //Reset (via IDLE — reseeds lfsr_rx, see note above)
            else if (mb_rx_compare_en && mb_rx_pattern_setup[0]) begin
                if (!mb_rx_data_pattern_sel[0])
                    i_state = 3'b010; //PRBS Pattern
                else
                    i_state = 3'b011; //Per lane ID pattern
            end else begin
                i_state = 3'b000; //Idle
            end 
        end 
    end
    
    always_comb begin : valid_pattern_en_generator
        // unit_valid_tx has two modes selected by valid_pattern_en:
        //   0 -> VALID_FRAME : the valid lane serializes 0x0F0F0F0F in LOCKSTEP
        //        with the data serializer (ser_en follows ser_en_lfsr_i), i.e.
        //        continuous per-word framing aligned to every data word. This is
        //        the mode a DATA point test needs so the RX data deserializer
        //        captures one aligned word per frame for the full burst, and
        //        O_done (o_valid_done) stays low so the burst is not cut short.
        //   1 -> VALID_PATTERN : a standalone 32-frame burst (O_done after 32),
        //        used ONLY for the valid-lane point test (setup[1]).
        // So drive valid_pattern_en HIGH only for the valid point test; for data
        // tests leave it low to get lockstep framing.
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
        if (!mb_rx_data_pattern_sel[0]) begin
            i_pcmp_iter_count = 16'd128; //PRBS Pattern
            i_pcmp_pattern_mode = 1'b0; // LFSR pattern
        end else begin
            i_pcmp_iter_count = 16'd64; //Per lane ID pattern
            i_pcmp_pattern_mode = 1'b1; // Per-lane ID pattern
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
        // In ACTIVE (functional data transfer) the LTSM stops asserting the
        // training-phase RX lane selects (mb_rx_data_en / mb_rx_valid_en), but the
        // RX deserializers must stay enabled to recover mission-mode flits. Force
        // them on in ACTIVE, sized to the negotiated width held in mb_rx_data_lane_map.
        if (mb_rx_data_en) begin
            case (mb_rx_data_lane_map)
                3'b011: i_rx_data_deser_en = 16'hffff;
                3'b001: i_rx_data_deser_en = 16'h00ff;
                3'b010: i_rx_data_deser_en = 16'hff00;
                3'b100: i_rx_data_deser_en = 16'h000f;
                3'b101: i_rx_data_deser_en = 16'h00f0;
                default: i_rx_data_deser_en = 16'h0000;
            endcase
        end else begin
            i_rx_data_deser_en = 16'h0000;
        end
        i_rx_valid_deser_en = mb_rx_valid_en;
    end

    always_comb begin : lane_mask_generator
        case (mb_rx_data_lane_map)
            3'b001:  internal_lane_mask = ~16'h00FF;
            3'b010:  internal_lane_mask = ~16'hFF00;
            3'b011:  internal_lane_mask = ~16'hFFFF;
            3'b100:  internal_lane_mask = ~16'h000F;
            3'b101:  internal_lane_mask = ~16'h00F0;
            default: internal_lane_mask = 16'hFFFF;
        endcase
        i_pcmp_lane_mask = reg_lane_mask | internal_lane_mask;
    end
endmodule
