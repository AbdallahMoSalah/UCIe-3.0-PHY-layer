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
    output logic timeout_error,

    // =========================================================================
    // RX / TX mainband message bus (Muxed Output)
    // =========================================================================
    output logic        mb_tx_valid,
    output msg_no_e     mb_tx_msg_id,
    output logic [15:0] mb_tx_MsgInfo,
    output logic [63:0] mb_tx_data_Field,

    // =========================================================================
    // PHY control bus (Muxed Output)
    // =========================================================================
    output logic mb_tx_valid_status,
    output logic mb_tx_track_status,
    output logic mb_tx_clk_status,
    output logic mb_tx_data_status,

    output logic mb_rx_valid_status,
    output logic mb_rx_track_status,
    output logic mb_rx_clk_status,
    output logic mb_rx_data_status,

    // =========================================================================
    // SUBMODULE INTERFACES
    // =========================================================================
    
    // PARAM
    output logic param_enable,
    input  logic param_done,
    input  logic param_error,
    input  logic param_timeout,
    input  logic        param_tx_valid,
    input  msg_no_e     param_tx_msg_id,
    input  logic [15:0] param_tx_MsgInfo,
    input  logic [63:0] param_tx_data_Field,
    input  logic param_tx_valid_s, param_tx_track_s, param_tx_clk_s, param_tx_data_s,
    input  logic param_rx_valid_s, param_rx_track_s, param_rx_clk_s, param_rx_data_s,

    // CAL
    output logic cal_enable,
    input  logic cal_done,
    input  logic cal_error,
    input  logic cal_timeout,
    input  logic        cal_tx_valid,
    input  msg_no_e     cal_tx_msg_id,
    input  logic [15:0] cal_tx_MsgInfo,
    input  logic [63:0] cal_tx_data_Field,

    // REPAIRCLK
    output logic repairclk_enable,
    input  logic repairclk_done,
    input  logic repairclk_error,
    input  logic repairclk_timeout,
    input  logic        repairclk_tx_valid,
    input  msg_no_e     repairclk_tx_msg_id,
    input  logic [15:0] repairclk_tx_MsgInfo,
    input  logic [63:0] repairclk_tx_data_Field,

    // REPAIRVAL
    output logic repairval_enable,
    input  logic repairval_done,
    input  logic repairval_error,
    input  logic repairval_timeout,
    input  logic        repairval_tx_valid,
    input  msg_no_e     repairval_tx_msg_id,
    input  logic [15:0] repairval_tx_MsgInfo,
    input  logic [63:0] repairval_tx_data_Field,

    // REVERSALMB
    output logic reversalmb_enable,
    input  logic reversalmb_done,
    input  logic reversalmb_error,
    input  logic reversalmb_timeout,
    input  logic        reversalmb_tx_valid,
    input  msg_no_e     reversalmb_tx_msg_id,
    input  logic [15:0] reversalmb_tx_MsgInfo,
    input  logic [63:0] reversalmb_tx_data_Field,
    input  logic rev_tx_valid_s, rev_tx_track_s, rev_tx_clk_s, rev_tx_data_s,
    input  logic rev_rx_valid_s, rev_rx_track_s, rev_rx_clk_s, rev_rx_data_s,

    // REPAIRMB
    output logic repairmb_enable,
    input  logic repairmb_done,
    input  logic repairmb_error,
    input  logic repairmb_timeout,
    input  logic        repairmb_tx_valid,
    input  msg_no_e     repairmb_tx_msg_id,
    input  logic [15:0] repairmb_tx_MsgInfo,
    input  logic [63:0] repairmb_tx_data_Field,
    input  logic rmb_tx_valid_s, rmb_tx_track_s, rmb_tx_clk_s, rmb_tx_data_s,
    input  logic rmb_rx_valid_s, rmb_rx_track_s, rmb_rx_clk_s, rmb_rx_data_s
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

    case (current_state)

        CTRL_IDLE:
            if (mbinit_enable && !mbinit_done && !mbinit_error)
                next_state = CTRL_PARAM;

        CTRL_PARAM:
            if (param_error || param_timeout)
                next_state = CTRL_ERROR;
            else if (param_done)
                next_state = CTRL_CAL;

        CTRL_CAL:
            if (cal_error || cal_timeout)
                next_state = CTRL_ERROR;
            else if (cal_done)
                next_state = CTRL_REPAIRCLK;

        CTRL_REPAIRCLK:
            if (repairclk_error || repairclk_timeout)
                next_state = CTRL_ERROR;
            else if (repairclk_done)
                next_state = CTRL_REPAIRVAL;

        CTRL_REPAIRVAL:
            if (repairval_error || repairval_timeout)
                next_state = CTRL_ERROR;
            else if (repairval_done)
                next_state = CTRL_REVERSALMB;

        CTRL_REVERSALMB:
            if (reversalmb_error || reversalmb_timeout)
                next_state = CTRL_ERROR;
            else if (reversalmb_done)
                next_state = CTRL_REPAIRMB;

        CTRL_REPAIRMB:
            if (repairmb_error || repairmb_timeout)
                next_state = CTRL_ERROR;
            else if (repairmb_done)
                next_state = CTRL_DONE;

        CTRL_DONE:
            if (!mbinit_enable)
                next_state = CTRL_IDLE;

        CTRL_ERROR:
            if (!mbinit_enable)
                next_state = CTRL_IDLE;

        default: next_state = CTRL_IDLE;
    endcase
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
    mb_tx_valid      = 0;
    mb_tx_msg_id     = msg_no_e'(0);
    mb_tx_MsgInfo    = 16'h0;
    mb_tx_data_Field = 64'h0;

    case (current_state)
        CTRL_PARAM: begin
            mb_tx_valid      = param_tx_valid;
            mb_tx_msg_id     = param_tx_msg_id;
            mb_tx_MsgInfo    = param_tx_MsgInfo;
            mb_tx_data_Field = param_tx_data_Field;
        end
        CTRL_REPAIRCLK: begin
            mb_tx_valid      = repairclk_tx_valid;
            mb_tx_msg_id     = repairclk_tx_msg_id;
            mb_tx_MsgInfo    = repairclk_tx_MsgInfo;
            mb_tx_data_Field = repairclk_tx_data_Field;
        end
        CTRL_REVERSALMB: begin
            mb_tx_valid      = reversalmb_tx_valid;
            mb_tx_msg_id     = reversalmb_tx_msg_id;
            mb_tx_MsgInfo    = reversalmb_tx_MsgInfo;
            mb_tx_data_Field = reversalmb_tx_data_Field;
        end
        CTRL_REPAIRMB: begin
            mb_tx_valid      = repairmb_tx_valid;
            mb_tx_msg_id     = repairmb_tx_msg_id;
            mb_tx_MsgInfo    = repairmb_tx_MsgInfo;
            mb_tx_data_Field = repairmb_tx_data_Field;
        end
        CTRL_REPAIRVAL: begin
            mb_tx_valid      = repairval_tx_valid;
            mb_tx_msg_id     = repairval_tx_msg_id;
            mb_tx_MsgInfo    = repairval_tx_MsgInfo;
            mb_tx_data_Field = repairval_tx_data_Field;
        end
        CTRL_CAL: begin
            mb_tx_valid      = cal_tx_valid;
            mb_tx_msg_id     = cal_tx_msg_id;
            mb_tx_MsgInfo    = cal_tx_MsgInfo;
            mb_tx_data_Field = cal_tx_data_Field;
        end
        default: ;
    endcase
end

// =============================================================================
// PHY STATUS MUX
// =============================================================================
always_comb begin
    mb_tx_valid_status = 0;
    mb_tx_track_status = 0;
    mb_tx_clk_status   = 0;
    mb_tx_data_status  = 0;
    mb_rx_valid_status = 0;
    mb_rx_track_status = 0;
    mb_rx_clk_status   = 0;
    mb_rx_data_status  = 0;

    case (current_state)
        CTRL_PARAM: begin
            mb_tx_valid_status = param_tx_valid_s;
            mb_tx_track_status = param_tx_track_s;
            mb_tx_clk_status   = param_tx_clk_s;
            mb_tx_data_status  = param_tx_data_s;
            mb_rx_valid_status = param_rx_valid_s;
            mb_rx_track_status = param_rx_track_s;
            mb_rx_clk_status   = param_rx_clk_s;
            mb_rx_data_status  = param_rx_data_s;
        end
        // REPAIRCLK and REPAIRVAL don't have PHY status ports
        CTRL_REVERSALMB: begin
            mb_tx_valid_status = rev_tx_valid_s;
            mb_tx_track_status = rev_tx_track_s;
            mb_tx_clk_status   = rev_tx_clk_s;
            mb_tx_data_status  = rev_tx_data_s;
            mb_rx_valid_status = rev_rx_valid_s;
            mb_rx_track_status = rev_rx_track_s;
            mb_rx_clk_status   = rev_rx_clk_s;
            mb_rx_data_status  = rev_rx_data_s;
        end
        CTRL_REPAIRMB: begin
            mb_tx_valid_status = rmb_tx_valid_s;
            mb_tx_track_status = rmb_tx_track_s;
            mb_tx_clk_status   = rmb_tx_clk_s;
            mb_tx_data_status  = rmb_tx_data_s;
            mb_rx_valid_status = rmb_rx_valid_s;
            mb_rx_track_status = rmb_rx_track_s;
            mb_rx_clk_status   = rmb_rx_clk_s;
            mb_rx_data_status  = rmb_rx_data_s;
        end
        default: ;
    endcase
end

// =============================================================================
// DONE / ERROR / TIMEOUT
// =============================================================================
assign mbinit_done   = (current_state == CTRL_DONE);
assign mbinit_error  = (current_state == CTRL_ERROR);
assign timeout_error = param_timeout | repairclk_timeout | reversalmb_timeout |
                       repairmb_timeout | repairval_timeout | cal_timeout;

endmodule
