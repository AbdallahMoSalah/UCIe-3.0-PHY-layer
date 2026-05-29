import UCIe_pkg::*;

module MBINIT_CAL 
#(parameter int CLK_FRQ_HZ = 800000000)
(
    input  logic clk, rst_n,

    // from LTSM
    input  logic mb_cal_enable,

    // to LTSM
    output logic mb_cal_done,
    output logic mb_cal_error,

    // RX from partner
    input  logic sb_cal_rx_valid,
    input  msg_no_e sb_cal_rx_msg_id,
    input  logic [15:0] sb_cal_rx_MsgInfo,
    input  logic [63:0] sb_cal_rx_data_Field,

    // TX to partner
    output logic sb_cal_tx_valid,
    output msg_no_e sb_cal_tx_msg_id,
    output logic [15:0] sb_cal_tx_MsgInfo,
    output logic [63:0] sb_cal_tx_data_Field,

    // FIFO ready
    input  logic sb_ltsm_rdy,

    // Timer / Global Error signals
    input  logic global_error
);

////////////////////////////////////////////////////////
////////////////////// STATES //////////////////////////
////////////////////////////////////////////////////////
typedef enum logic [2:0] { 
    MB_S0_IDLE,

    MB_S1_CAL_REQ_SEND,     // drive CAL_Done_req until ltsm_rdy=1
    MB_S1_CAL_REQ_WAIT,     // wait for partner's CAL_Done_req

    MB_S1_CAL_RSP_SEND,     // drive CAL_Done_resp until ltsm_rdy=1
    MB_S1_CAL_RSP_WAIT,     // wait for partner's CAL_Done_resp

    MB_S2_DONE,
    MB_S3_ERROR

 } mb_cal_state_e;
mb_cal_state_e current_state , next_state ;

////////////////////////////////////////////////////////
///////////////////// PARAMETERS ///////////////////////
////////////////////////////////////////////////////////
localparam logic [15:0] MB_default_MSG_Info = 16'h0000;
localparam logic [63:0] MB_default_data_Field = 64'h0000000000000000;

//

////////////////////////////////////////////////////////
//////////////// HANDSHAKE FLAGS /////////////////////
////////////////////////////////////////////////////////
logic cal_req_rcvd;
logic cal_rsp_rcvd;

//-----------------------------------------------------
// CAL REQ received (clears outside MB_S1_CAL_REQ_WAIT)
//-----------------------------------------------------
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        cal_req_rcvd <= 0;
    else if(sb_cal_rx_valid && sb_cal_rx_msg_id == MBINIT_CAL_Done_req)
        cal_req_rcvd <= 1;
    else if(current_state != MB_S1_CAL_REQ_WAIT)
        cal_req_rcvd <= 0;
end

//-----------------------------------------------------
// CAL RSP received (clears outside MB_S1_CAL_RSP_WAIT)
//-----------------------------------------------------
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        cal_rsp_rcvd <= 0;
    else if(sb_cal_rx_valid && sb_cal_rx_msg_id == MBINIT_CAL_Done_resp && current_state > MB_S1_CAL_REQ_SEND)
        cal_rsp_rcvd <= 1;
    else if(current_state != MB_S1_CAL_RSP_WAIT)
        cal_rsp_rcvd <= 0;
end

////////////////////////////////////////////////////////
//////////////// STATE REGISTER //////////////////////
////////////////////////////////////////////////////////
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        current_state <= MB_S0_IDLE;
    else
        current_state <= next_state;
end

////////////////////////////////////////////////////////
////////////////// NEXT STATE LOGIC ////////////////////
////////////////////////////////////////////////////////
always_comb begin 
    next_state = current_state;

    if (!mb_cal_enable) begin
        next_state = MB_S0_IDLE;
    end else if (global_error && !mb_cal_done) begin
        next_state = MB_S3_ERROR;
    end else begin
        
        case(current_state)
            MB_S0_IDLE: begin
                if(mb_cal_enable)
                    next_state = MB_S1_CAL_REQ_SEND;
            end

            // -- S1 CAL Request --
            MB_S1_CAL_REQ_SEND: begin
                if(sb_ltsm_rdy)           next_state = MB_S1_CAL_REQ_WAIT;
            end

            MB_S1_CAL_REQ_WAIT: begin
                if(cal_req_rcvd)       next_state = MB_S1_CAL_RSP_SEND;
            end

            // -- S1 CAL Response --
            MB_S1_CAL_RSP_SEND: begin
                if(sb_ltsm_rdy)           next_state = MB_S1_CAL_RSP_WAIT;
            end

            MB_S1_CAL_RSP_WAIT: begin
                if(cal_rsp_rcvd)       next_state = MB_S2_DONE;
            end

            MB_S2_DONE: begin
                // Stays here until mb_cal_enable deasserts
            end

            MB_S3_ERROR: begin
                // Stays here until mb_cal_enable deasserts
            end

            default: next_state = MB_S0_IDLE;
        endcase        
    end
end

////////////////////////////////////////////////////////
/////////////// OUTPUT LOGIC ///////////////////////////
////////////////////////////////////////////////////////
always_comb begin
    // Default outputs.
    sb_cal_tx_valid       = 1'b0;
    sb_cal_tx_msg_id      = msg_no_e'(NOTHING);
    sb_cal_tx_MsgInfo     = MB_default_MSG_Info;
    sb_cal_tx_data_Field  = MB_default_data_Field;

    case(current_state)
        MB_S1_CAL_REQ_SEND: begin
            sb_cal_tx_valid       = 1'b1;
            sb_cal_tx_msg_id      = MBINIT_CAL_Done_req;
            sb_cal_tx_MsgInfo     = MB_default_MSG_Info;
            sb_cal_tx_data_Field  = MB_default_data_Field;    
        end

        MB_S1_CAL_RSP_SEND: begin
            sb_cal_tx_valid       = 1'b1;
            sb_cal_tx_msg_id      = MBINIT_CAL_Done_resp;
            sb_cal_tx_MsgInfo     = MB_default_MSG_Info;
            sb_cal_tx_data_Field  = MB_default_data_Field;    
        end

        default: ; // Use defaults
    endcase
end

////////////////////////////////////////////////////////
/////////////// DONE LOGIC //////////////////////////////
////////////////////////////////////////////////////////
always_comb begin
    mb_cal_done = (current_state == MB_S2_DONE);
end

////////////////////////////////////////////////////////
/////////////// ERROR LOGIC ////////////////////////////
////////////////////////////////////////////////////////
always_comb begin
    mb_cal_error = (current_state == MB_S3_ERROR);
end

////////////////////////////////////////////////////////
// SYSTEMVERILOG ASSERTIONS (SVA) FOR CAL
////////////////////////////////////////////////////////
`ifdef SIMULATION
    // 1. Handshake Integrity: No Done_resp sent without Done_req received first
    property p_tx_start_resp_after_req;
        @(posedge clk) disable iff (!rst_n)
        (sb_cal_tx_valid && sb_cal_tx_msg_id == MBINIT_CAL_Done_resp) |-> cal_req_rcvd;
    endproperty
    assert_tx_start_resp_after_req: assert property(p_tx_start_resp_after_req);

    // 2. Bounded Liveness: Done_req must eventually be answered or enter S3 error
    property p_start_req_leads_to_resp_or_error;
        @(posedge clk) disable iff (!rst_n)
        (current_state == MB_S1_CAL_REQ_WAIT) |-> (##[1:2000] (cal_rsp_rcvd || current_state == MB_S3_ERROR));
    endproperty
    assert_start_req_leads_to_resp_or_error: assert property(p_start_req_leads_to_resp_or_error);

    // 3. Protocol Rule: Sideband TX stability until sb_ltsm_rdy asserts
    property p_tx_stability_until_rdy;
        @(posedge clk) disable iff (!rst_n || !mb_cal_enable)
        (sb_cal_tx_valid && !sb_ltsm_rdy) |-> 
        ##1 (sb_cal_tx_valid && 
             $stable(sb_cal_tx_msg_id) && 
             $stable(sb_cal_tx_MsgInfo) && 
             $stable(sb_cal_tx_data_Field));
    endproperty
    assert_tx_stability_until_rdy: assert property(p_tx_stability_until_rdy);

    // 4. Error Check: Error states raise error flag
    property p_error_condition_raises_error;
        @(posedge clk) disable iff (!rst_n)
        (global_error && mb_cal_enable)
        |-> ##[1:5] (current_state == MB_S3_ERROR && mb_cal_error == 1'b1);
    endproperty
    assert_error_condition_raises_error: assert property(p_error_condition_raises_error);

    // 5. Success Check: Done state asserts done flag
    property p_success_path_leads_to_done;
        @(posedge clk) disable iff (!rst_n)
        (current_state == MB_S1_CAL_RSP_WAIT && cal_rsp_rcvd && !global_error)
        |-> ##[1:5] (current_state == MB_S2_DONE && mb_cal_done == 1'b1);
    endproperty
    assert_success_path_leads_to_done: assert property(p_success_path_leads_to_done);

    // 6. Safety Check: Done and Error are mutually exclusive
    assert_never_done_and_error: assert property (
        @(posedge clk) disable iff (!rst_n) 
        !(mb_cal_done && mb_cal_error)
    );

    // 7. FSM State Coverage Checks
    cover_state_idle:         cover property (@(posedge clk) disable iff (!rst_n) current_state == MB_S0_IDLE);
    cover_state_req_send:     cover property (@(posedge clk) disable iff (!rst_n) current_state == MB_S1_CAL_REQ_SEND);
    cover_state_req_wait:     cover property (@(posedge clk) disable iff (!rst_n) current_state == MB_S1_CAL_REQ_WAIT);
    cover_state_rsp_send:     cover property (@(posedge clk) disable iff (!rst_n) current_state == MB_S1_CAL_RSP_SEND);
    cover_state_rsp_wait:     cover property (@(posedge clk) disable iff (!rst_n) current_state == MB_S1_CAL_RSP_WAIT);
    cover_state_done:         cover property (@(posedge clk) disable iff (!rst_n) current_state == MB_S2_DONE);
    cover_state_error:        cover property (@(posedge clk) disable iff (!rst_n) current_state == MB_S3_ERROR);
`endif

endmodule
