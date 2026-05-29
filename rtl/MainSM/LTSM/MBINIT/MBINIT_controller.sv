import UCIe_pkg::*;

// =============================================================================
// MBINIT_CONTROLLER
// =============================================================================
// Pure FSM and MUX logic to sequence the submodules in the updated order:
//   S1: MBINIT_PARAM      – capability negotiation
//   S2: MBINIT_CAL        – calibration / done handshake
//   S3: MBINIT_REPAIRCLK  – clock lane repair
//   S4: MBINIT_REPAIRVAL  – repair validation
//   S5: MBINIT_REVERSALMB – lane reversal detection
//   S6: MBINIT_REPAIRMB   – mainband data lane repair
// =============================================================================

module MBINIT_CONTROLLER
(
    input  logic clk,
    input  logic rst_n,

    // =========================================================================
    // From / To LTSM
    // =========================================================================
    input  logic mbinit_enable,
    output logic mbinit_done,
    output logic mbinit_error,

    output logic timer_enable,
    output logic timer_rst_n,
    input  logic timer_timeout_expired,

    // =========================================================================
    // RX / TX sideband message bus (Muxed Output)
    // =========================================================================
    output logic        sb_tx_valid,
    output msg_no_e     sb_tx_msg_id,
    output logic [15:0] sb_tx_MsgInfo,
    output logic [63:0] sb_tx_data_Field,

    // =========================================================================
    // Unified Mainband Outputs (Muxed / Latched)
    // =========================================================================
    output logic       mb_tx_pattern_en,
    output logic [2:0] mb_tx_pattern_setup,
    output logic [1:0] mb_tx_data_pattern_sel,
    output logic       mb_tx_val_pattern_sel,
    output logic       mb_rx_compare_en,
    output logic [1:0] mb_rx_compare_setup,
    output logic       clear_error_req,
    output logic [2:0] mbinit_rx_data_lane_mask,
    output logic [2:0] mbinit_tx_data_lane_mask,
    output logic       mb_lane_reversal_req,

    // =========================================================================
    // SUBMODULE INTERFACES
    // =========================================================================
    
    // PARAM
    output logic param_enable,
    input  logic param_done,
    input  logic param_error,
    input  logic        param_tx_valid,
    input  msg_no_e     param_tx_msg_id,
    input  logic [15:0] param_tx_MsgInfo,
    input  logic [63:0] param_tx_data_Field,

    // CAL
    output logic cal_enable,
    input  logic cal_done,
    input  logic cal_error,
    input  logic        cal_tx_valid,
    input  msg_no_e     cal_tx_msg_id,
    input  logic [15:0] cal_tx_MsgInfo,
    input  logic [63:0] cal_tx_data_Field,

    // REPAIRCLK
    output logic repairclk_enable,
    input  logic repairclk_done,
    input  logic repairclk_error,
    input  logic        repairclk_tx_valid,
    input  msg_no_e     repairclk_tx_msg_id,
    input  logic [15:0] repairclk_tx_MsgInfo,
    input  logic [63:0] repairclk_tx_data_Field,
    input  logic       repairclk_tx_pattern_en,
    input  logic [2:0] repairclk_tx_pattern_setup,
    input  logic       repairclk_rx_compare_en,
    input  logic [1:0] repairclk_rx_compare_setup,

    // REPAIRVAL
    output logic repairval_enable,
    input  logic repairval_done,
    input  logic repairval_error,
    input  logic        repairval_tx_valid,
    input  msg_no_e     repairval_tx_msg_id,
    input  logic [15:0] repairval_tx_MsgInfo,
    input  logic [63:0] repairval_tx_data_Field,
    input  logic       repairval_tx_pattern_en,
    input  logic [2:0] repairval_tx_pattern_setup,
    input  logic       repairval_tx_val_pattern_sel,
    input  logic       repairval_rx_compare_en,
    input  logic [1:0] repairval_rx_compare_setup,

    // REVERSALMB
    output logic reversalmb_enable,
    input  logic reversalmb_done,
    input  logic reversalmb_error,
    input  logic        reversalmb_tx_valid,
    input  msg_no_e     reversalmb_tx_msg_id,
    input  logic [15:0] reversalmb_tx_MsgInfo,
    input  logic [63:0] reversalmb_tx_data_Field,
    input  logic       reversalmb_tx_pattern_en,
    input  logic [2:0] reversalmb_tx_pattern_setup,
    input  logic [1:0] reversalmb_tx_data_pattern_sel,
    input  logic       reversalmb_rx_compare_en,
    input  logic [1:0] reversalmb_rx_compare_setup,
    input  logic       reversalmb_clear_error_req,
    input  logic       reversalmb_lane_reversal_req,

    // REPAIRMB
    output logic repairmb_enable,
    input  logic repairmb_done,
    input  logic repairmb_error,
    input  logic        repairmb_tx_valid,
    input  msg_no_e     repairmb_tx_msg_id,
    input  logic [15:0] repairmb_tx_MsgInfo,
    input  logic [63:0] repairmb_tx_data_Field,
    input  logic       repairmb_clear_error_req,
    input  logic [2:0] repairmb_rx_data_lane_mask,
    input  logic [2:0] repairmb_tx_data_lane_mask
);

// =============================================================================
// CONTROLLER STATE MACHINE
// =============================================================================
typedef enum logic [3:0] {
    CTRL_IDLE,
    CTRL_PARAM,
    CTRL_CAL,
    CTRL_REPAIRCLK,
    CTRL_REPAIRVAL,
    CTRL_REVERSALMB,
    CTRL_REPAIRMB,
    CTRL_DONE,
    CTRL_ERROR
} ctrl_state_e;

ctrl_state_e current_state, next_state;

// =============================================================================
// STATE REGISTER
// =============================================================================
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        current_state <= CTRL_IDLE;
    else
        current_state <= next_state;
end

// =============================================================================
// NEXT STATE LOGIC
// =============================================================================
always_comb begin
    next_state = current_state;

    if(!mbinit_enable)begin
        next_state = CTRL_IDLE;
    end
    else if (timer_timeout_expired && !mbinit_done) begin
        next_state = CTRL_ERROR;
    end else begin
        case (current_state)

            CTRL_IDLE: begin
                if (mbinit_enable)
                    next_state = CTRL_PARAM;
            end

            CTRL_PARAM: begin
                if (param_error)
                    next_state = CTRL_ERROR;
                else if (param_done)
                    next_state = CTRL_CAL;
            end

            CTRL_CAL: begin
                if (cal_error)
                    next_state = CTRL_ERROR;
                else if (cal_done)
                    next_state = CTRL_REPAIRCLK;
            end

            CTRL_REPAIRCLK: begin
                if (repairclk_error)
                    next_state = CTRL_ERROR;
                else if (repairclk_done)
                    next_state = CTRL_REPAIRVAL;
            end

            CTRL_REPAIRVAL: begin
                if (repairval_error)
                    next_state = CTRL_ERROR;
                else if (repairval_done)
                    next_state = CTRL_REVERSALMB;
            end

            CTRL_REVERSALMB: begin
                if (reversalmb_error)
                    next_state = CTRL_ERROR;
                else if (reversalmb_done)
                    next_state = CTRL_REPAIRMB;
            end

            CTRL_REPAIRMB: begin
                if (repairmb_error)
                    next_state = CTRL_ERROR;
                else if (repairmb_done)
                    next_state = CTRL_DONE;
            end

            CTRL_DONE: begin 
                // stay in this state until mbinit_enable deasserts
            end
 
            CTRL_ERROR: begin 
                // stay in this state until mbinit_enable deasserts
            end

            default: next_state = CTRL_IDLE;
        endcase
    end
end

// =============================================================================
// SUBMODULE ENABLE MUX
// =============================================================================
always_comb begin
    param_enable      = 0;
    repairclk_enable  = 0;
    reversalmb_enable = 0;
    repairmb_enable   = 0;
    repairval_enable  = 0;
    cal_enable        = 0;

    case (current_state)
        CTRL_PARAM:      param_enable      = 1;
        CTRL_REPAIRCLK:  repairclk_enable  = 1;
        CTRL_REVERSALMB: reversalmb_enable = 1;
        CTRL_REPAIRMB:   repairmb_enable   = 1;
        CTRL_REPAIRVAL:  repairval_enable  = 1;
        CTRL_CAL:        cal_enable        = 1;
        default: ;
    endcase
end

// =============================================================================
// TX MUX  (only the active submodule drives the bus)
// =============================================================================
always_comb begin
    sb_tx_valid      = 0;
    sb_tx_msg_id     = msg_no_e'(0);
    sb_tx_MsgInfo    = 16'h0;
    sb_tx_data_Field = 64'h0;

    case (current_state)
        CTRL_PARAM: begin
            sb_tx_valid      = param_tx_valid;
            sb_tx_msg_id     = param_tx_msg_id;
            sb_tx_MsgInfo    = param_tx_MsgInfo;
            sb_tx_data_Field = param_tx_data_Field;
        end
        CTRL_REPAIRCLK: begin
            sb_tx_valid      = repairclk_tx_valid;
            sb_tx_msg_id     = repairclk_tx_msg_id;
            sb_tx_MsgInfo    = repairclk_tx_MsgInfo;
            sb_tx_data_Field = repairclk_tx_data_Field;
        end
        CTRL_REVERSALMB: begin
            sb_tx_valid      = reversalmb_tx_valid;
            sb_tx_msg_id     = reversalmb_tx_msg_id;
            sb_tx_MsgInfo    = reversalmb_tx_MsgInfo;
            sb_tx_data_Field = reversalmb_tx_data_Field;
        end
        CTRL_REPAIRMB: begin
            sb_tx_valid      = repairmb_tx_valid;
            sb_tx_msg_id     = repairmb_tx_msg_id;
            sb_tx_MsgInfo    = repairmb_tx_MsgInfo;
            sb_tx_data_Field = repairmb_tx_data_Field;
        end
        CTRL_REPAIRVAL: begin
            sb_tx_valid      = repairval_tx_valid;
            sb_tx_msg_id     = repairval_tx_msg_id;
            sb_tx_MsgInfo    = repairval_tx_MsgInfo;
            sb_tx_data_Field = repairval_tx_data_Field;
        end
        CTRL_CAL: begin
            sb_tx_valid      = cal_tx_valid;
            sb_tx_msg_id     = cal_tx_msg_id;
            sb_tx_MsgInfo    = cal_tx_MsgInfo;
            sb_tx_data_Field = cal_tx_data_Field;
        end
        default: ;
    endcase
end

// =============================================================================
// MAINBAND TRAINING & COMPARISON MUX
// =============================================================================
always_comb begin
    mb_tx_pattern_en         = 1'b0;
    mb_tx_pattern_setup      = 3'b000;
    mb_tx_data_pattern_sel   = 2'b00;
    mb_tx_val_pattern_sel    = 1'b0;
    mb_rx_compare_en         = 1'b0;
    mb_rx_compare_setup      = 2'b00;
    clear_error_req          = 1'b0;

    case (current_state)
        CTRL_REPAIRCLK: begin
            mb_tx_pattern_en         = repairclk_tx_pattern_en;
            mb_tx_pattern_setup      = repairclk_tx_pattern_setup;
            mb_rx_compare_en         = repairclk_rx_compare_en;
            mb_rx_compare_setup      = repairclk_rx_compare_setup;
        end

        CTRL_REPAIRVAL: begin
            mb_tx_pattern_en         = repairval_tx_pattern_en;
            mb_tx_pattern_setup      = repairval_tx_pattern_setup;
            mb_tx_val_pattern_sel    = repairval_tx_val_pattern_sel;
            mb_rx_compare_en         = repairval_rx_compare_en;
            mb_rx_compare_setup      = repairval_rx_compare_setup;
        end

        CTRL_REVERSALMB: begin
            mb_tx_pattern_en         = reversalmb_tx_pattern_en;
            mb_tx_pattern_setup      = reversalmb_tx_pattern_setup;
            mb_tx_data_pattern_sel   = reversalmb_tx_data_pattern_sel;
            mb_rx_compare_en         = reversalmb_rx_compare_en;
            mb_rx_compare_setup      = reversalmb_rx_compare_setup;
            clear_error_req          = reversalmb_clear_error_req;
        end

        CTRL_REPAIRMB: begin
            clear_error_req          = repairmb_clear_error_req;
        end

        default: ;
    endcase
end

// =============================================================================
// SEQUENTIAL LATCHING FOR NEGOTIATED LANE MASKS
// =============================================================================
logic [2:0] mbinit_rx_data_lane_mask_reg;
logic [2:0] mbinit_tx_data_lane_mask_reg;

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mbinit_rx_data_lane_mask_reg <= 3'b011;
        mbinit_tx_data_lane_mask_reg <= 3'b011;
    end else if (current_state == CTRL_IDLE) begin
        mbinit_rx_data_lane_mask_reg <= 3'b011;
        mbinit_tx_data_lane_mask_reg <= 3'b011;
    end else if (current_state == CTRL_REPAIRMB) begin
        // Active tracking: Submodule plays with the bus
        // Latch: Freeze the final negotiated map values
        mbinit_rx_data_lane_mask_reg <= repairmb_rx_data_lane_mask;
        mbinit_tx_data_lane_mask_reg <= repairmb_tx_data_lane_mask;
    end
end

always_comb begin
    mbinit_rx_data_lane_mask = mbinit_rx_data_lane_mask_reg;
    mbinit_tx_data_lane_mask = mbinit_tx_data_lane_mask_reg;
    if (current_state == CTRL_IDLE) begin
        mbinit_rx_data_lane_mask = 3'b011;
        mbinit_tx_data_lane_mask = 3'b011;
    end else if (current_state == CTRL_REPAIRMB) begin
        mbinit_rx_data_lane_mask = repairmb_rx_data_lane_mask;
        mbinit_tx_data_lane_mask = repairmb_tx_data_lane_mask;
    end
end

// =============================================================================
// SEQUENTIAL LATCHING FOR REVERSAL REQUEST
// =============================================================================
logic mb_lane_reversal_req_reg;

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mb_lane_reversal_req_reg <= 1'b0;
    end else if (current_state == CTRL_IDLE) begin
        mb_lane_reversal_req_reg <= 1'b0;
    end else if (current_state == CTRL_REVERSALMB) begin
        mb_lane_reversal_req_reg <= reversalmb_lane_reversal_req;
    end
end

always_comb begin
    mb_lane_reversal_req = mb_lane_reversal_req_reg;
    if (current_state == CTRL_IDLE) begin
        mb_lane_reversal_req = 1'b0;
    end else if (current_state == CTRL_REVERSALMB) begin
        mb_lane_reversal_req = reversalmb_lane_reversal_req;
    end
end

// =============================================================================
// SHARED TIMER CONTROL SIGNALS
// =============================================================================
assign timer_enable = (current_state != CTRL_IDLE) && (current_state != CTRL_DONE) && (current_state != CTRL_ERROR);

logic timer_rst_n_reg;
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        timer_rst_n_reg <= 1'b0;
    else if (next_state != current_state)
        timer_rst_n_reg <= 1'b0; // reset the timer on state transition
    else
        timer_rst_n_reg <= 1'b1;
end
assign timer_rst_n = timer_rst_n_reg;

// =============================================================================
// DONE / ERROR
// =============================================================================
assign mbinit_done   = (current_state == CTRL_DONE);
assign mbinit_error  = (current_state == CTRL_ERROR);

// =============================================================================
// SYSTEMVERILOG ASSERTIONS & STATE COVERAGE
// =============================================================================
`ifdef SIMULATION
    // 1. Safety Check: Done and Error are mutually exclusive
    assert_never_done_and_error: assert property (
        @(posedge clk) disable iff (!rst_n) 
        !(mbinit_done && mbinit_error)
    );

    // 2. Safety Check: One-hot enable for submodules during active FSM
    assert_one_hot_enable: assert property (
        @(posedge clk) disable iff (!rst_n)
        $onehot0({param_enable, cal_enable, repairclk_enable, repairval_enable, reversalmb_enable, repairmb_enable})
    );

    // 3. State Transitions
    property p_param_done_leads_to_cal;
        @(posedge clk) disable iff (!rst_n)
        (current_state == CTRL_PARAM && param_done && !param_error) |=> (current_state == CTRL_CAL);
    endproperty
    assert_param_done_leads_to_cal: assert property(p_param_done_leads_to_cal);

    property p_param_error_leads_to_error;
        @(posedge clk) disable iff (!rst_n)
        (current_state == CTRL_PARAM && param_error) |=> (current_state == CTRL_ERROR);
    endproperty
    assert_param_error_leads_to_error: assert property(p_param_error_leads_to_error);

    property p_cal_done_leads_to_repairclk;
        @(posedge clk) disable iff (!rst_n)
        (current_state == CTRL_CAL && cal_done && !cal_error) |=> (current_state == CTRL_REPAIRCLK);
    endproperty
    assert_cal_done_leads_to_repairclk: assert property(p_cal_done_leads_to_repairclk);

    property p_cal_error_leads_to_error;
        @(posedge clk) disable iff (!rst_n)
        (current_state == CTRL_CAL && cal_error) |=> (current_state == CTRL_ERROR);
    endproperty
    assert_cal_error_leads_to_error: assert property(p_cal_error_leads_to_error);

    property p_repairclk_done_leads_to_repairval;
        @(posedge clk) disable iff (!rst_n)
        (current_state == CTRL_REPAIRCLK && repairclk_done && !repairclk_error) |=> (current_state == CTRL_REPAIRVAL);
    endproperty
    assert_repairclk_done_leads_to_repairval: assert property(p_repairclk_done_leads_to_repairval);

    property p_repairclk_error_leads_to_error;
        @(posedge clk) disable iff (!rst_n)
        (current_state == CTRL_REPAIRCLK && repairclk_error) |=> (current_state == CTRL_ERROR);
    endproperty
    assert_repairclk_error_leads_to_error: assert property(p_repairclk_error_leads_to_error);

    property p_repairval_done_leads_to_reversalmb;
        @(posedge clk) disable iff (!rst_n)
        (current_state == CTRL_REPAIRVAL && repairval_done && !repairval_error) |=> (current_state == CTRL_REVERSALMB);
    endproperty
    assert_repairval_done_leads_to_reversalmb: assert property(p_repairval_done_leads_to_reversalmb);

    property p_repairval_error_leads_to_error;
        @(posedge clk) disable iff (!rst_n)
        (current_state == CTRL_REPAIRVAL && repairval_error) |=> (current_state == CTRL_ERROR);
    endproperty
    assert_repairval_error_leads_to_error: assert property(p_repairval_error_leads_to_error);

    property p_reversalmb_done_leads_to_repairmb;
        @(posedge clk) disable iff (!rst_n)
        (current_state == CTRL_REVERSALMB && reversalmb_done && !reversalmb_error) |=> (current_state == CTRL_REPAIRMB);
    endproperty
    assert_reversalmb_done_leads_to_repairmb: assert property(p_reversalmb_done_leads_to_repairmb);

    property p_reversalmb_error_leads_to_error;
        @(posedge clk) disable iff (!rst_n)
        (current_state == CTRL_REVERSALMB && reversalmb_error) |=> (current_state == CTRL_ERROR);
    endproperty
    assert_reversalmb_error_leads_to_error: assert property(p_reversalmb_error_leads_to_error);

    property p_repairmb_done_leads_to_done;
        @(posedge clk) disable iff (!rst_n)
        (current_state == CTRL_REPAIRMB && repairmb_done && !repairmb_error) |=> (current_state == CTRL_DONE);
    endproperty
    assert_repairmb_done_leads_to_done: assert property(p_repairmb_done_leads_to_done);

    property p_repairmb_error_leads_to_error;
        @(posedge clk) disable iff (!rst_n)
        (current_state == CTRL_REPAIRMB && repairmb_error) |=> (current_state == CTRL_ERROR);
    endproperty
    assert_repairmb_error_leads_to_error: assert property(p_repairmb_error_leads_to_error);

    // 4. State Coverage
    cover_state_idle:       cover property (@(posedge clk) disable iff (!rst_n) current_state == CTRL_IDLE);
    cover_state_param:      cover property (@(posedge clk) disable iff (!rst_n) current_state == CTRL_PARAM);
    cover_state_cal:        cover property (@(posedge clk) disable iff (!rst_n) current_state == CTRL_CAL);
    cover_state_repairclk:  cover property (@(posedge clk) disable iff (!rst_n) current_state == CTRL_REPAIRCLK);
    cover_state_repairval:  cover property (@(posedge clk) disable iff (!rst_n) current_state == CTRL_REPAIRVAL);
    cover_state_reversalmb: cover property (@(posedge clk) disable iff (!rst_n) current_state == CTRL_REVERSALMB);
    cover_state_repairmb:   cover property (@(posedge clk) disable iff (!rst_n) current_state == CTRL_REPAIRMB);
    cover_state_done:       cover property (@(posedge clk) disable iff (!rst_n) current_state == CTRL_DONE);
    cover_state_error:      cover property (@(posedge clk) disable iff (!rst_n) current_state == CTRL_ERROR);
`endif

endmodule
