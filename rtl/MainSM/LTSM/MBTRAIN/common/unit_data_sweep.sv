// =============================================================================
// unit_data_sweep.sv
//
// Vref Sweep Datapath for the Data-Lane Receiver Voltage Reference calibration.
// Extracted from unit_DATAVREF so that the FSM shell remains small and the sweep
// logic can be reused in DATAVREF, DATATRAINVREF, DATATRAINCENTER1, DATATRAINCENTER2.
// =============================================================================
module unit_data_sweep #(
        parameter MAX_DATA_VREF_CODE = 7'D127,
        parameter MIN_DATA_VREF_CODE = 7'D10
    ) (
        // ======================== //
        // Clock & Reset            //
        // ======================== //
        input  wire        lclk,
        input  wire        rst_n,
        input  wire        is_ltsm_out_of_reset,

        // ======================== //
        // Control Flags            //
        // ======================== //
        input  wire        start_req_state,  // High during START_REQ state
        input  wire        log_result_state, // High during LOG_RESULT state
        input  wire        calc_apply_state, // High during CALC_APPLY state

        // ======================== //
        // Configuration            //
        // ======================== //
        input  wire [2:0]  mb_rx_data_lane_mask, // 000: None, 001: 0-7, 010: 8-15, 011: 0-15, 100: 0-3, 101: 4-7

        // ======================== //
        // D2C Test Result          //
        // ======================== //
        input  wire [15:0] d2c_perlane_pass,  // 1 = lane passed at current Vref code.

        // ======================== //
        // Outputs                  //
        // ======================== //
        output reg  [$clog2(MAX_DATA_VREF_CODE + 1)-1:0] swept_code_r,
        output reg  [$clog2(MAX_DATA_VREF_CODE + 1)-1:0] best_vref_code [15:0]
    );

    localparam DATA_VREF_CODE_WIDTH = $clog2(MAX_DATA_VREF_CODE + 1);

    // MB Lane Control
    logic [15:0] negotiated_data_lanes;
    always @(*) begin
        case(mb_rx_data_lane_mask)
            3'b000:  negotiated_data_lanes = 16'h0000;
            3'b001:  negotiated_data_lanes = 16'h00FF;
            3'b010:  negotiated_data_lanes = 16'hFF00;
            3'b011:  negotiated_data_lanes = 16'hFFFF;
            3'b100:  negotiated_data_lanes = 16'h000F;
            3'b101:  negotiated_data_lanes = 16'h00F0;
            default: negotiated_data_lanes = 16'h0000;
        endcase
    end

    // Internal arrays
    wire [DATA_VREF_CODE_WIDTH-1:0] best_range     [15:0];
    wire [DATA_VREF_CODE_WIDTH-1:0] zone_range     [15:0];
    reg  [DATA_VREF_CODE_WIDTH-1:0] zone_min_r     [15:0];
    reg  [DATA_VREF_CODE_WIDTH-1:0] best_lo        [15:0];
    reg  [DATA_VREF_CODE_WIDTH-1:0] best_hi        [15:0];
    reg  [15:0] found_pass;
    reg  [15:0] zone_valid;

    genvar lane;
    generate
        for(lane=0; lane<16; lane=lane+1) begin : VREF_RANGE_GEN
            assign best_range[lane] = (found_pass[lane] == 1'b1) ?
                (best_hi[lane] - best_lo[lane]) : '0;
            assign zone_range[lane] = (swept_code_r - zone_min_r[lane]);
        end
    endgenerate

    // swept_code_r counter and per-lane best_vref_code apply
    always @(posedge lclk or negedge rst_n) begin : DATAVREF_CODE_AND_CALC_PROC
        integer j;
        if(!rst_n) begin
            swept_code_r <= MIN_DATA_VREF_CODE;
            for(j=0; j<16; j=j+1) begin
                best_vref_code[j] <= MIN_DATA_VREF_CODE;
            end
        end
        else if (!is_ltsm_out_of_reset) begin
            swept_code_r <= MIN_DATA_VREF_CODE;
            for(j=0; j<16; j=j+1) begin
                best_vref_code[j] <= MIN_DATA_VREF_CODE;
            end
        end
        else if(start_req_state) begin
            swept_code_r <= MIN_DATA_VREF_CODE;
            for(j=0; j<16; j=j+1) begin
                best_vref_code[j] <= MIN_DATA_VREF_CODE;
            end
        end
        else if(log_result_state) begin
            if(swept_code_r != MAX_DATA_VREF_CODE) begin
                swept_code_r <= swept_code_r + 1;
            end
        end
        else if(calc_apply_state) begin
            for(j=0; j<16; j=j+1) begin
                if(found_pass[j] == 1'b1) begin
                    best_vref_code[j] <= ({1'b0, best_lo[j]} + {1'b0, best_hi[j]}) >> 1;
                end
                else begin
                    best_vref_code[j] <= '0; // No passing code: safe default
                end
            end
        end
    end

    // per-lane two-zone eye-map tracking (LOG_RESULT)
    always @(posedge lclk or negedge rst_n) begin : DATAVREF_LOG_RESULT_PROC
        integer i;
        if(!rst_n) begin
            for(i=0; i<16; i=i+1) begin
                best_lo   [i] <= '0;
                best_hi   [i] <= '0;
                found_pass[i] <= 1'b0;
                zone_valid[i] <= 1'b0;
                zone_min_r[i] <= '0;
            end
        end
        else if (!is_ltsm_out_of_reset) begin
            for(i=0; i<16; i=i+1) begin
                best_lo   [i] <= '0;
                best_hi   [i] <= '0;
                found_pass[i] <= 1'b0;
                zone_valid[i] <= 1'b0;
                zone_min_r[i] <= '0;
            end
        end
        else if(start_req_state) begin
            for(i=0; i<16; i=i+1) begin
                best_lo   [i] <= '0;
                best_hi   [i] <= '0;
                found_pass[i] <= 1'b0;
                zone_valid[i] <= 1'b0;
                zone_min_r[i] <= '0;
            end
        end
        else if(log_result_state) begin
            for(i=0; i<16; i=i+1) begin
                if (d2c_perlane_pass[i]) begin
                    // PASS at swept_code_r for lane i
                    if (!zone_valid[i] || swept_code_r == MIN_DATA_VREF_CODE) begin
                        zone_valid[i] <= 1'b1;
                        zone_min_r[i] <= swept_code_r;
                        if (!found_pass[i] && negotiated_data_lanes[i]) begin
                            found_pass[i] <= 1'b1;
                            best_lo[i]    <= swept_code_r;
                            best_hi[i]    <= swept_code_r;
                        end
                    end
                    else begin
                        if (zone_range[i] > best_range[i]) begin
                            best_lo[i] <= zone_min_r[i];
                            best_hi[i] <= swept_code_r;
                        end
                    end
                end
                else begin
                    zone_valid[i] <= 1'b0;
                end
            end
        end
    end

endmodule
