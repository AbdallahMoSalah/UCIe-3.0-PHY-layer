
    //////////////////////////////////////////////////
    // output   logic d2c_test_enable        = d2c_test_if.tx_pt_en
    // input    logic d2c_test_done          = d2c_test_if.test_d2c_done

    // output   logic d2c_pattern_setup      = d2c_test_if.d2c_pattern_setup
    // output   logic d2c_data_pattern_sel   = d2c_test_if.d2c_data_pattern_sel

    // output   logic d2c_iter_count         = d2c_test_if.d2c_iter_count
    // output   logic d2c_idle_count         = d2c_test_if.d2c_idle_count
    // output   logic d2c_burst_count        = d2c_test_if.d2c_burst_count

    // output   logic d2c_pattern_mode       = d2c_test_if.d2c_pattern_mode

    // input    logic  d2c_perlane_err       = d2c_test_if.d2c_perlane_err
    // output   logic  d2c_compare_setup     = d2c_test_if.d2c_compare_setup

    //////////////////////////////////////////////////

import UCIe_pkg::*;
module MBINIT_REPAIRMB
#( parameter int CLK_FRQ_HZ = 800000000 )
(
    input  logic clk, rst_n,

    ucie_mb_cap_if.consumer cap_if,
    internal_ltsm_if.substate2d2c_mp d2c_test_if,

    input  logic mb_repairmb_enable,

    output logic mb_repairmb_done,
    output logic mb_repairmb_error,

    // RX
    input  logic            mb_repairmb_rx_valid,
    input  msg_no_e         mb_repairmb_rx_msg_id,
    input  logic    [15:0]  mb_repairmb_rx_MsgInfo,
    input  logic    [63:0]  mb_repairmb_rx_data_Field,

    // TX
    output logic            mb_repairmb_tx_valid,
    output msg_no_e         mb_repairmb_tx_msg_id,
    output logic    [15:0]  mb_repairmb_tx_MsgInfo,
    output logic    [63:0]  mb_repairmb_tx_data_Field,

    //time out signal
    output logic timeout_error,
 
    //phy control
    output logic mb_tx_valid_status,
    output logic mb_tx_track_status,
    output logic mb_tx_clk_status,
    output logic mb_tx_data_status,

    output logic mb_rx_valid_status,
    output logic mb_rx_track_status,
    output logic mb_rx_clk_status,
    output logic mb_rx_data_status

);

////////////////////////////////////////////////////////
// STATES
////////////////////////////////////////////////////////
typedef enum logic [3:0] {
    MB_S0_IDLE,

    MB_S1_READINESS_HANDSHAKE_REQ,
    MB_S1_READINESS_HANDSHAKE_RSP,

    MB_S2_D2C_POINT_TEST,

    MB_S3_DEGRADE_RESOLUTION_REQ,
    MB_S3_DEGRADE_RESOLUTION_RSP,

    MB_S4_DEGRADE_VERIFICATION,

    MB_S5_FINALIZE_HANDSHAKE_REQ,
    MB_S5_FINALIZE_HANDSHAKE_RSP
} state_e;
state_e current_state, next_state;



logic [2:0] local_lane_map;
logic [2:0] final_lane_map_r;


////////////////////////////////////////////////////////
// DEFAULTS
////////////////////////////////////////////////////////
localparam logic [15:0] MB_default_MSG_Info = 16'h0000;
localparam logic [63:0] MB_default_data_Field = 64'h0;


////////////////////////////////////////////////////////
// RESULT for S3
////////////////////////////////////////////////////////
//local per-lane error
logic [15:0] mb_rx_perlane_result;
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        mb_rx_perlane_result <= 16'h0;

    else if(current_state == MB_S2_D2C_POINT_TEST && d2c_test_if.test_d2c_done)
        mb_rx_perlane_result <= d2c_test_if.d2c_perlane_err;
end

logic [15:0] MB_local_degradation_req_msg_info;
assign MB_local_degradation_req_msg_info = {13'h0, local_lane_map};

logic [15:0] MB_local_degradation_rsp_msg_info;
assign MB_local_degradation_rsp_msg_info = {13'h0, final_lane_map_r};

////////////////////////////////////////////////////////
//partner per-lane error
logic [2:0] partner_lane_map;
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        partner_lane_map <= 3'b000;

    else if(/*current_state == MB_S3_DEGRADE_RESOLUTION_REQ &&*/
            mb_repairmb_rx_valid &&
            mb_repairmb_rx_msg_id == MBINIT_REPAIRMB_apply_degrade_req)
        partner_lane_map <= mb_repairmb_rx_MsgInfo[2:0];
end
////////////////////////////////////////////////////////
logic allow_x4_mode;
assign allow_x4_mode = /*cap_if.spmw_en || */cap_if.use_x8_mode;

////////////////////////////////////////////////////////
// Lane Maps
////////////////////////////////////////////////////////

//////////////////
// LOCAL DECISION
//////////////////
always_comb begin

    // default - all good 
    local_lane_map = 3'b000;    // not possible

    //////////////
    // Degrade NOT possible
    //////////////
    if(mb_rx_perlane_result == 16'hFFFF)
        local_lane_map = 3'b000; // not possible
    
    else if (mb_rx_perlane_result == 16'h0000) 
        local_lane_map = 3'b011; // x16
    
    //////////////////
    // X8 MODES
    //////////////////
    else if (mb_rx_perlane_result == 16'hFF00) 
        local_lane_map = 3'b001; // lower x8
    
    else if (mb_rx_perlane_result == 16'h00FF) 
        local_lane_map = 3'b010; // upper x8

    /////////////////////
    // X4 MODES (ADVANCED)
    /////////////////////
    else if (allow_x4_mode) begin

        // lanes 0-3
        if (mb_rx_perlane_result == 16'hFFF0)
            local_lane_map = 3'b100;

        // lanes 4-7
        else if (mb_rx_perlane_result == 16'hFF0F)
            local_lane_map = 3'b101;

    end
end

////////////////////////////////////////////
// Final Decision
////////////////////////////////////////////
logic [2:0] final_lane_map;
logic degrade_not_possible;

always_comb begin
    degrade_not_possible = 0;
    final_lane_map = 3'b000;

    ////////////////////////////////////////////
    // 1. Full x16
    ////////////////////////////////////////////
    if(local_lane_map == 3'b000) begin
        final_lane_map = 3'b000;
        degrade_not_possible = 1;
    end
    else if(local_lane_map == 3'b011 && partner_lane_map == 3'b011) begin
        final_lane_map = 3'b011;
        degrade_not_possible = 0;
    end

    ////////////////////////////////////////////
    // 2. x8 Common
    ////////////////////////////////////////////
    else if(
        (local_lane_map inside {3'b011,3'b001}) &&
        (partner_lane_map inside {3'b011,3'b001})
    ) begin
        final_lane_map = 3'b001; // lower x8
        degrade_not_possible = 0;
    end

    else if(
        (local_lane_map inside {3'b011,3'b010}) &&
        (partner_lane_map inside {3'b011,3'b010})
    ) begin
        final_lane_map = 3'b010; // upper x8
        degrade_not_possible = 0;
    end

    ////////////////////////////////////////////
    // 3. x4 (advanced mode only)
    ////////////////////////////////////////////
    else if(allow_x4_mode) begin

        // lanes 0-3
        if(
            (local_lane_map inside {3'b011,3'b001,3'b100}) &&
            (partner_lane_map inside {3'b011,3'b001,3'b100})
        )begin
            final_lane_map = 3'b100;
            degrade_not_possible = 0;
        end
        // lanes 4-7
        else if(
            (local_lane_map inside {3'b011,3'b001,3'b101}) &&
            (partner_lane_map inside {3'b011,3'b001,3'b101})
        )begin
            final_lane_map = 3'b101;
            degrade_not_possible = 0;
        end
        else begin
            final_lane_map = 3'b000;
            degrade_not_possible = 1;
        end
    end

    ////////////////////////////////////////////
    // 4. no solution
    ////////////////////////////////////////////
    else begin
        final_lane_map = 3'b000;
        degrade_not_possible = 1;
    end
end

/////////////////////////////////////////////////////////
//Width Change Detection:
/////////////////////////////////////////////////////////
logic [2:0] prev_lane_map;

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        prev_lane_map <= 3'b011; // start x16
    else if(current_state == MB_S4_DEGRADE_VERIFICATION)
        prev_lane_map <= final_lane_map_r;
end

//logic width_changed;

//assign width_changed = (final_lane_map != prev_lane_map);

////////////////////////////////////////////////////////
// Signals Registered
////////////////////////////////////////////////////////
// Register final lane map and degrade not possible flags
logic degrade_not_possible_r;

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        final_lane_map_r <= 3'b011;
        degrade_not_possible_r <= 0;
    end
    else if(current_state == MB_S3_DEGRADE_RESOLUTION_RSP) begin
        final_lane_map_r <= final_lane_map;
        degrade_not_possible_r <= degrade_not_possible;
    end
end

// Register width change flag
logic width_changed_r;

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        width_changed_r <= 0;
    else if(current_state == MB_S3_DEGRADE_RESOLUTION_RSP)
        width_changed_r <= (final_lane_map != prev_lane_map);
end
////////////////////////////////////////////////////////
// TIMEOUT
////////////////////////////////////////////////////////
logic timer_enable;
logic timeout_expired;

assign timer_enable = mb_repairmb_enable && !mb_repairmb_done && !mb_repairmb_error;
timeout_counter #(
    .CLK_FRQ_HZ(CLK_FRQ_HZ),
    .TIME_OUT(8)
) u_timeout (
    .clk(clk),
    .timeout_rst_n(rst_n),
    .enable_timeout(timer_enable),
    .timeout_expired(timeout_expired)
);

assign timeout_error = timeout_expired && !mb_repairmb_done;

////////////////////////////////////////////////////////
// Retry logic
////////////////////////////////////////////////////////
logic retry_start;
assign retry_start = (current_state == MB_S4_DEGRADE_VERIFICATION) && width_changed_r && !degrade_not_possible_r;

logic retry_done;

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        retry_done <= 0;
    else if(retry_start)
        retry_done <= 1;
    else if(current_state == MB_S0_IDLE)
        retry_done <= 0;
end

////////////////////////////////////////////////////////
// HANDSHAKE FLAGS
////////////////////////////////////////////////////////
logic s1_req_sent, s1_req_rcvd;
logic s1_rsp_sent, s1_rsp_rcvd;

logic s3_req_sent, s3_req_rcvd;
logic s3_rsp_sent, s3_rsp_rcvd;

logic s5_req_sent, s5_req_rcvd;
logic s5_rsp_sent, s5_rsp_rcvd;

/////////////////////////////////////////////////////////
// TX flags
/////////////////////////////////////////////////////////
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n || retry_start) begin
        s1_req_sent <= 0; s1_rsp_sent <= 0;
        s3_req_sent <= 0; s3_rsp_sent <= 0;
        s5_req_sent <= 0; s5_rsp_sent <= 0;
    end
end

////////////////////////////////////////////////////////
// RX FLAGS
////////////////////////////////////////////////////////
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n || retry_start) begin
        s1_req_rcvd <= 0; s1_rsp_rcvd <= 0;
        s3_req_rcvd <= 0; s3_rsp_rcvd <= 0;
        s5_req_rcvd <= 0; s5_rsp_rcvd <= 0;
    end
    else if(mb_repairmb_rx_valid) begin

        case(current_state)

        //////////////////////////////////////////////////
        // S1
        //////////////////////////////////////////////////
        MB_S1_READINESS_HANDSHAKE_REQ,
        MB_S1_READINESS_HANDSHAKE_RSP: begin
            if(mb_repairmb_rx_msg_id == MBINIT_REPAIRMB_start_req)
                s1_req_rcvd <= 1;
            if(mb_repairmb_rx_msg_id == MBINIT_REPAIRMB_start_resp)
                s1_rsp_rcvd <= 1;
        end

        //////////////////////////////////////////////////
        // S3
        //////////////////////////////////////////////////
        MB_S3_DEGRADE_RESOLUTION_REQ,
        MB_S3_DEGRADE_RESOLUTION_RSP: begin
            if(mb_repairmb_rx_msg_id == MBINIT_REPAIRMB_apply_degrade_req)
                s3_req_rcvd <= 1;
            if(mb_repairmb_rx_msg_id == MBINIT_REPAIRMB_apply_degrade_resp)
                s3_rsp_rcvd <= 1;
        end

        //////////////////////////////////////////////////
        // S5    
        //////////////////////////////////////////////////
        MB_S5_FINALIZE_HANDSHAKE_REQ,
        MB_S5_FINALIZE_HANDSHAKE_RSP: begin
            if(mb_repairmb_rx_msg_id == MBINIT_REPAIRMB_end_req)
                s5_req_rcvd <= 1;
            if(mb_repairmb_rx_msg_id == MBINIT_REPAIRMB_end_resp)
                s5_rsp_rcvd <= 1;
        end
        default: ;
        endcase
    end
end

////////////////////////////////////////////////////////
// STATE REGISTER
////////////////////////////////////////////////////////
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        current_state <= MB_S0_IDLE;
    else
        current_state <= next_state;
end

////////////////////////////////////////////////////////
// NEXT STATE
////////////////////////////////////////////////////////
always_comb begin
    next_state = current_state;


    if(mb_repairmb_error || timeout_error)
        next_state = MB_S0_IDLE;
    else
        case(current_state)

    MB_S0_IDLE:
        if (mb_repairmb_enable && !mb_repairmb_done && !mb_repairmb_error)
            next_state = MB_S1_READINESS_HANDSHAKE_REQ;

    //--------------------------------------------------
    // S1
    //--------------------------------------------------
    MB_S1_READINESS_HANDSHAKE_REQ:
        if (/*s1_req_sent &&*/ s1_req_rcvd)
            next_state = MB_S1_READINESS_HANDSHAKE_RSP;

    MB_S1_READINESS_HANDSHAKE_RSP:
        if (/*s1_rsp_sent &&*/ s1_rsp_rcvd)
            next_state = MB_S2_D2C_POINT_TEST;

    //--------------------------------------------------
    // S2 (D2C TEST)
    //--------------------------------------------------
    MB_S2_D2C_POINT_TEST:
        if (d2c_test_if.test_d2c_done)
            next_state = MB_S3_DEGRADE_RESOLUTION_REQ;

    //--------------------------------------------------
    // S3
    //--------------------------------------------------
    MB_S3_DEGRADE_RESOLUTION_REQ:
        if (/*s3_req_sent && */s3_req_rcvd)
            next_state = MB_S3_DEGRADE_RESOLUTION_RSP;

    MB_S3_DEGRADE_RESOLUTION_RSP:
        if (s3_rsp_sent && s3_rsp_rcvd)
            next_state = MB_S4_DEGRADE_VERIFICATION;

    //--------------------------------------------------
    // S4
    //--------------------------------------------------
    MB_S4_DEGRADE_VERIFICATION:
        if(degrade_not_possible_r)
            next_state = MB_S0_IDLE;
        else if( retry_start && !retry_done)
            next_state = MB_S2_D2C_POINT_TEST; // repeat S2
        else
            next_state = MB_S5_FINALIZE_HANDSHAKE_REQ;

    //--------------------------------------------------
    // S5
    //--------------------------------------------------
    MB_S5_FINALIZE_HANDSHAKE_REQ:
        if (/*s5_req_sent &&*/ s5_req_rcvd)
            next_state = MB_S5_FINALIZE_HANDSHAKE_RSP;

    MB_S5_FINALIZE_HANDSHAKE_RSP:
        if (/*s5_rsp_sent &&*/ s5_rsp_rcvd)
            next_state = MB_S0_IDLE;

    endcase
end

////////////////////////////////////////////////////////
// PHY CONTROL
////////////////////////////////////////////////////////
always_comb begin
    // default (safe)
    mb_tx_valid_status = 0;
    mb_tx_track_status = 0;
    mb_tx_clk_status   = 0;
    mb_tx_data_status  = 0;

    mb_rx_valid_status = 0;
    mb_rx_track_status = 0;
    mb_rx_clk_status   = 0;
    mb_rx_data_status  = 0;

    //////////////////////////////////////////////////////
    // REPAIR / TRAINING STATE
    //////////////////////////////////////////////////////
    if (current_state == MB_S2_D2C_POINT_TEST) begin

        // TX
        mb_tx_clk_status   = 1;  // clock ON
        mb_tx_valid_status = 0;  // held low
        mb_tx_data_status  = 0;  // held low
        mb_tx_track_status = 0;  // held low

        // RX
        mb_rx_clk_status   = 1;  // enabled
        mb_rx_valid_status = 1;
        mb_rx_data_status  = 1;
        mb_rx_track_status = 0;  // optional disable
    end
end

////////////////////////////////////////////////////////
// TX LOGIC
////////////////////////////////////////////////////////
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        mb_repairmb_tx_valid <= 0;
        mb_repairmb_tx_msg_id <= msg_no_e'(0);
        mb_repairmb_tx_MsgInfo <= 16'h0;
        mb_repairmb_tx_data_Field <= 64'h0;
    end
    else begin
        mb_repairmb_tx_valid <= 0;
        mb_repairmb_tx_msg_id <= msg_no_e'(0);
        mb_repairmb_tx_MsgInfo <= 16'h0;
        mb_repairmb_tx_data_Field <= 64'h0;

        case(current_state)

        //////////////////////////////////////////////////
        // S1
        //////////////////////////////////////////////////
        MB_S1_READINESS_HANDSHAKE_REQ:
            if(!s1_req_sent) begin
                mb_repairmb_tx_valid <= 1;
                mb_repairmb_tx_msg_id <= MBINIT_REPAIRMB_start_req;
                mb_repairmb_tx_MsgInfo <= MB_default_MSG_Info;
                mb_repairmb_tx_data_Field <= MB_default_data_Field;
                s1_req_sent <= 1;
            end

        MB_S1_READINESS_HANDSHAKE_RSP:
            if(!s1_rsp_sent && s1_req_rcvd)begin
                mb_repairmb_tx_valid <= 1;
                mb_repairmb_tx_msg_id <= MBINIT_REPAIRMB_start_resp;
                mb_repairmb_tx_MsgInfo <= MB_default_MSG_Info;
                mb_repairmb_tx_data_Field <= MB_default_data_Field;
                s1_rsp_sent <= 1;
            end

        //////////////////////////////////////////////////
        // S3
        //////////////////////////////////////////////////
        MB_S3_DEGRADE_RESOLUTION_REQ:
            if(!s3_req_sent)begin
                mb_repairmb_tx_valid <= 1;
                mb_repairmb_tx_msg_id <= MBINIT_REPAIRMB_apply_degrade_req;
                mb_repairmb_tx_MsgInfo <= MB_local_degradation_req_msg_info;    // local_lane_map ( 3'b011,3'b001,3'b010,3'b100,3'b101,3'b000)
                mb_repairmb_tx_data_Field <= MB_default_data_Field;
                s3_req_sent <= 1;
            end


        MB_S3_DEGRADE_RESOLUTION_RSP:
            if(!s3_rsp_sent && s3_req_rcvd)begin
                mb_repairmb_tx_valid <= 1;
                mb_repairmb_tx_msg_id <= MBINIT_REPAIRMB_apply_degrade_resp;
                mb_repairmb_tx_MsgInfo <= MB_local_degradation_rsp_msg_info;    // final_lane_map ( 3'b011,3'b001,3'b010,3'b100,3'b101,3'b000)
                mb_repairmb_tx_data_Field <= MB_default_data_Field;
                s3_rsp_sent <= 1;
            end

        //////////////////////////////////////////////////
        // S4
        //////////////////////////////////////////////////
        MB_S4_DEGRADE_VERIFICATION: begin
            // verification only
        end

        //////////////////////////////////////////////////
        // S5
        //////////////////////////////////////////////////
        MB_S5_FINALIZE_HANDSHAKE_REQ:
            if(!s5_req_sent) begin
                mb_repairmb_tx_valid <= 1;
                mb_repairmb_tx_msg_id <= MBINIT_REPAIRMB_end_req;
                mb_repairmb_tx_MsgInfo <= MB_default_MSG_Info;
                mb_repairmb_tx_data_Field <= MB_default_data_Field;
                s5_req_sent <= 1;
            end

        MB_S5_FINALIZE_HANDSHAKE_RSP:
            if(!s5_rsp_sent && s5_req_rcvd)begin
                mb_repairmb_tx_valid <= 1;
                mb_repairmb_tx_msg_id <= MBINIT_REPAIRMB_end_resp;
                mb_repairmb_tx_MsgInfo <= MB_default_MSG_Info;
                mb_repairmb_tx_data_Field <= MB_default_data_Field;
                s5_rsp_sent <= 1;
            end
        endcase
    end
end

////////////////////////////////////////////////////////
// PATTERN CONTROL
////////////////////////////////////////////////////////
always_comb begin
    // default
    d2c_test_if.tx_pt_en          = 0;
    d2c_test_if.d2c_pattern_setup = 3'b001; // Per Lane ID
    d2c_test_if.d2c_data_pattern_sel = 2'b01;
    d2c_test_if.d2c_pattern_mode  = 0; // continuous
    d2c_test_if.d2c_compare_setup = 2'b00; // per-lane

    d2c_test_if.d2c_iter_count  = 16'd128;
    d2c_test_if.d2c_idle_count  = 0;
    d2c_test_if.d2c_burst_count = 0;

    //--------------------------------------------------
    if (current_state == MB_S2_D2C_POINT_TEST) begin
        d2c_test_if.tx_pt_en = 1;
    end
end

////////////////////////////////////////////////////////
// DONE
////////////////////////////////////////////////////////
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        mb_repairmb_done <= 0;
    else if(current_state == MB_S5_FINALIZE_HANDSHAKE_RSP && s5_rsp_sent && s5_rsp_rcvd)
        mb_repairmb_done <= 1;
    else if(current_state == MB_S0_IDLE)
        mb_repairmb_done <= 0;
end

////////////////////////////////////////////////////////
// ERROR
////////////////////////////////////////////////////////
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        mb_repairmb_error <= 0;

    else if(timeout_error)
        mb_repairmb_error <= 1;

    else if(degrade_not_possible_r)
        mb_repairmb_error <= 1;

    else if(retry_start && retry_done)
        mb_repairmb_error <= 1;

    else if((partner_lane_map inside {3'b100,3'b101} && !allow_x4_mode) || !(partner_lane_map inside {3'b000,3'b001,3'b010,3'b011,3'b100,3'b101}))
        mb_repairmb_error <= 1;

/*else if(mb_repairmb_rx_valid) begin

    case(current_state)

    MB_S1_READINESS_HANDSHAKE_REQ,
    MB_S1_READINESS_HANDSHAKE_RSP: begin
        if(!(mb_repairmb_rx_msg_id inside {
            MBINIT_REPAIRMB_start_req,
            MBINIT_REPAIRMB_start_resp
        }))
            mb_repairmb_error <= 1;
    end

    MB_S3_DEGRADE_RESOLUTION_REQ,
    MB_S3_DEGRADE_RESOLUTION_RSP: begin
        if(!(mb_repairmb_rx_msg_id inside {
            MBINIT_REPAIRMB_apply_degrade_req,
            MBINIT_REPAIRMB_apply_degrade_resp
        }))
            mb_repairmb_error <= 1;
    end

    MB_S5_FINALIZE_HANDSHAKE_REQ,
    MB_S5_FINALIZE_HANDSHAKE_RSP: begin
        if(!(mb_repairmb_rx_msg_id inside {
            MBINIT_REPAIRMB_end_req,
            MBINIT_REPAIRMB_end_resp
        }))
            mb_repairmb_error <= 1;
    end

    MB_S2_D2C_POINT_TEST,
    MB_S4_DEGRADE_VERIFICATION:begin
        
    end
       

    default: ;

    endcase
end*/
end
endmodule