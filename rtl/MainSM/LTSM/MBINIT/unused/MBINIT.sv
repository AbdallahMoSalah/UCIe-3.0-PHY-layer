import UCIe_pkg::*;

module MBINIT
#(
    parameter int CLK_FRQ_HZ = 800000000
)
(
    input  logic clk,
    input  logic rst_n,

    // from LTSM
    input  logic mb_enable,

    // to LTSM
    output logic mb_done,
    output logic mb_error,

    // RX from partner
    input  logic mb_rx_valid,
    input  msg_no_e mb_rx_msg_id,
    input  logic [15:0] mb_rx_MsgInfo,
    input  logic [63:0] mb_rx_data_Field,

    // TX to partner
    output logic mb_tx_valid,
    output msg_no_e mb_tx_msg_id,
    output logic [15:0] mb_tx_MsgInfo,
    output logic [63:0] mb_tx_data_Field,

    output logic timeout_error
);

logic param_timeout;
logic cal_timeout;

assign timeout_error = param_timeout | cal_timeout;

////////////////////////////////////////////////////////
//////////////////// STATES ////////////////////////////
////////////////////////////////////////////////////////

typedef enum logic [2:0] {

    MBINIT_IDLE_S0,
    MBINIT_PARAM_S1,
    MBINIT_CAL_S2,
    MBINIT_DONE_S3

} mb_state_e;

mb_state_e current_state, next_state;

////////////////////////////////////////////////////////
//////////////// SUBMODULE SIGNALS /////////////////////
////////////////////////////////////////////////////////

logic mb_param_enable;
logic mb_param_done;
logic mb_param_error;

logic mb_cal_enable;
logic mb_cal_done;
logic mb_cal_error;

////////////////////////////////////////////////////////
//////////////// STATE REGISTER ////////////////////////
////////////////////////////////////////////////////////

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        current_state <= MBINIT_IDLE_S0;
    else
        current_state <= next_state;
end

////////////////////////////////////////////////////////
//////////////// NEXT STATE LOGIC //////////////////////
////////////////////////////////////////////////////////

always_comb begin

    next_state = current_state;

    case(current_state)

        MBINIT_IDLE_S0:
        begin
            if(mb_enable && !mb_done)
                next_state = MBINIT_PARAM_S1;
        end


        MBINIT_PARAM_S1:
        begin
            if(!mb_enable || mb_param_error)
                next_state = MBINIT_IDLE_S0;
            else if(mb_param_done)
                next_state = MBINIT_CAL_S2;
        end


        MBINIT_CAL_S2:
        begin
            if(!mb_enable || mb_cal_error)
                next_state = MBINIT_IDLE_S0;
            else if(mb_cal_done)
                next_state = MBINIT_DONE_S3;
        end


        MBINIT_DONE_S3:
        begin
            if(!mb_enable)
            next_state = MBINIT_IDLE_S0;
        end

    endcase

end

////////////////////////////////////////////////////////
//////////////// ENABLE CONTROL ////////////////////////
////////////////////////////////////////////////////////

always_comb begin

    mb_param_enable = 0;
    mb_cal_enable   = 0;

    case(current_state)

        MBINIT_PARAM_S1:
            mb_param_enable = 1;

        MBINIT_CAL_S2:
            mb_cal_enable = 1;

    endcase

end

////////////////////////////////////////////////////////
////////////////// ERROR LOGIC /////////////////////////
////////////////////////////////////////////////////////

assign mb_error = mb_param_error | mb_cal_error;

////////////////////////////////////////////////////////
//////////////// DONE LOGIC ////////////////////////////
////////////////////////////////////////////////////////

assign mb_done = (current_state == MBINIT_DONE_S3);

////////////////////////////////////////////////////////
//////////////// Internal Signals //////////////////////
////////////////////////////////////////////////////////

logic        param_tx_valid;
msg_no_e     param_tx_msg_id;
logic [15:0] param_tx_msginfo;
logic [63:0] param_tx_data;

logic        cal_tx_valid;
msg_no_e     cal_tx_msg_id;
logic [15:0] cal_tx_msginfo;
logic [63:0] cal_tx_data;

always_comb begin

    mb_tx_valid      = 0;
    mb_tx_msg_id     = msg_no_e'(0);
    mb_tx_MsgInfo    = 0;
    mb_tx_data_Field = 0;

    case(current_state)

        MBINIT_PARAM_S1: begin
            mb_tx_valid      = param_tx_valid;
            mb_tx_msg_id     = param_tx_msg_id;
            mb_tx_MsgInfo    = param_tx_msginfo;
            mb_tx_data_Field = param_tx_data;
        end

        MBINIT_CAL_S2: begin
            mb_tx_valid      = cal_tx_valid;
            mb_tx_msg_id     = cal_tx_msg_id;
            mb_tx_MsgInfo    = cal_tx_msginfo;
            mb_tx_data_Field = cal_tx_data;
        end

    endcase

end

////////////////////////////////////////////////////////
//////////////// MBINIT.PARAM //////////////////////////
////////////////////////////////////////////////////////

MBINIT_PARAM
#(
    .CLK_FRQ_HZ(CLK_FRQ_HZ)
)
u_mbinit_param
(
    .clk(clk),
    .rst_n(rst_n),

    .mb_param_enable(mb_param_enable),

    .mb_param_done(mb_param_done),
    .mb_param_error(mb_param_error),

    .mb_param_rx_valid(mb_rx_valid),
    .mb_param_rx_msg_id(mb_rx_msg_id),
    .mb_param_rx_MsgInfo(mb_rx_MsgInfo),
    .mb_param_rx_data_Field(mb_rx_data_Field),

    .mb_param_tx_valid(param_tx_valid),
    .mb_param_tx_msg_id(param_tx_msg_id),
    .mb_param_tx_MsgInfo(param_tx_msginfo),
    .mb_param_tx_data_Field(param_tx_data),

    .timeout_error(param_timeout)
);

////////////////////////////////////////////////////////
////////////////////// MBINIT.CAL //////////////////////
////////////////////////////////////////////////////////

MBINIT_CAL 
#(
    .CLK_FRQ_HZ(CLK_FRQ_HZ)
)
u_mbinit_cal
(
    .clk(clk),
    .rst_n(rst_n),

    .mb_cal_enable(mb_cal_enable),

    .mb_cal_done(mb_cal_done),
    .mb_cal_error(mb_cal_error),

    .mb_cal_rx_valid(mb_rx_valid),
    .mb_cal_rx_msg_id(mb_rx_msg_id),
    .mb_cal_rx_MsgInfo(mb_rx_MsgInfo),
    .mb_cal_rx_data_Field(mb_rx_data_Field),

    .mb_cal_tx_valid(cal_tx_valid),
    .mb_cal_tx_msg_id(cal_tx_msg_id),
    .mb_cal_tx_MsgInfo(cal_tx_msginfo),
    .mb_cal_tx_data_Field(cal_tx_data),

    .timeout_error(cal_timeout)
);

endmodule