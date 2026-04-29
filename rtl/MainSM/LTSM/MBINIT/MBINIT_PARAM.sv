/*
{MBINIT.PARAM configuration req}
---------------------------------
[63:16]: Reserved
[15]: Tx Adjustment during Runtime Recalibration (TARR) is supported (1) or not supported (0)
[14]: Sideband feature extensions is supported (1) or not supported (0)
[13]: UCIe-A x32 if Advanced Package; UCIe-S x8 if Standard Package.
[12:11]: Module ID: 0h: 0, 1h: 1, 2h: 2, 3h:3
[10]: Clock Phase: 0b: Differential clock, 1b: Quadrature phase
[9]: Clock Mode - 0b: Strobe mode; 1b: Continuous mode
[8:4]: Voltage Swing - The encodings are the same as the “Supported Tx Vswing encodings” field of the PHY Capability register
[3:0]: Max IO Link Speed - The encodings are the same as “Max Link Speeds” field of the UCIe Link Capability register
=====================================================================

{MBINIT.PARAM configuration resp}
---------------------------------
[63:16]: Reserved
[15]: Tx Adjustment during Runtime Recalibration (TARR) is negotiated (1) or not supported (0)
[14]: Sideband feature extensions is negotiated (1) or not supported (0)
[13:11]: Reserved
[10]: Clock Phase: 0b: Differential clock, 1b: Quadrature phase
[9]: Clock Mode - 0b: Strobe mode; 1b: Continuous mode
[8:4]: Reserved
[3:0]: Max IO Link Speed - The encodings are the same as “Max Link Speeds” field of the UCIe Link Capability register
=====================================================================

{MBINIT.PARAM SBFE req}
-----------------------
[63:5]: Reserved
[4]: L2SPD is supported (1) or not supported (0)
[3]: PSPT is supported (1) or not supported (0)
[2]: Sideband-only (SO) port (1), full UCIe port (0)
[1]: Sideband Performant Mode Operation (PMO) is supported (1) or not supported (0)
[0]: Management Transport protocol is supported (1) or not supported (0)

=====================================================================

{MBINIT.PARAM SBFE resp}
------------------------
[63:5]: Reserved
[4]: L2SPD is negotiated (1) or not negotiated (0)
[3]: PSPT is negotiated (1) or not negotiated (0)
[2]: Sideband-only (SO) port (1), full UCIe port (0)
[1]: Sideband Performant Mode Operation (PMO) is negotiated (1) or not supported (0)
[0]: Management Transport protocol is supported (1) or not supported (0)

*/


import UCIe_pkg::*;
module MBINIT_PARAM
#( parameter int CLK_FRQ_HZ = 800000000)
(
    input  logic clk, rst_n,

    // from LTSM
    input  logic mb_param_enable,

    // ===== Interface =====
    ucie_mb_cap_if.mbinit cap_if,

    // to LTSM
    output logic mb_param_done,
    output logic mb_param_error,

    // ===== PHY CONTROL =====
    output logic mb_tx_valid_status,
    output logic mb_tx_track_status,
    output logic mb_tx_clk_status,
    output logic mb_tx_data_status,

    output logic mb_rx_valid_status,
    output logic mb_rx_track_status,
    output logic mb_rx_clk_status,
    output logic mb_rx_data_status,

    // RX from partner
    input  logic mb_param_rx_valid,
    input  msg_no_e mb_param_rx_msg_id,
    input  logic [15:0] mb_param_rx_MsgInfo,
    input  logic [63:0] mb_param_rx_data_Field,

    // TX to partner
    output logic mb_param_tx_valid,
    output msg_no_e mb_param_tx_msg_id,
    output logic [15:0] mb_param_tx_MsgInfo,
    output logic [63:0] mb_param_tx_data_Field,

    output logic timeout_error
);

////////////////////////////////////////////////////////
////////////////////// STATES //////////////////////////
////////////////////////////////////////////////////////

typedef enum logic [2:0] { 
    MB_S0_IDLE,

    MB_S1_PARAM_EXCHANGE_REQ,
    MB_S1_PARAM_EXCHANGE_RSP,

    MB_S2_FEATURE_EXCHANGE_REQ,
    MB_S2_FEATURE_EXCHANGE_RSP,

    MB_S3_STALL
 } mb_param_state_e;
mb_param_state_e current_state , next_state ;

////////////////////////////////////////////////////////
///////////////////// PARAMETERS ///////////////////////
//Handshakes message IDs.///////////////////////////////
localparam logic [15:0] MB_default_MSG_Info = 16'h0000;
localparam logic [63:0] MB_default_data_Field = 64'h0000000000000000;

////////////////////////////////////////////////////////
////////////////////////////////////////////////////////
///////////////// LOCAL CAPABILITIES ///////////////////
////////////////////////////////////////////////////////
////////////////////////////////////////////////////////

/*
configuration_req
64'h0000_0000_0000_6A53
[15] TARR = 0
[14] SBFE = 1
[13] x32 = 1
[12:11] ModuleID = 01
[10] ClockPhase = 0
[9] ClockMode = 1
[8:4] Vswing = 00101
[3:0] MaxSpeed = 0011
*/
logic [63:0] local_capabilities_DataField_S1;
always_comb begin
    local_capabilities_DataField_S1 = 64'b0;

    local_capabilities_DataField_S1[15] = cap_if.local_tarr;
    local_capabilities_DataField_S1[14] = cap_if.local_sbfe;
    local_capabilities_DataField_S1[13] = cap_if.local_is_x8;   //  width
    local_capabilities_DataField_S1[3:0]= cap_if.local_max_speed;
end
//*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*

/*
SBFE_req
64'h0000_0000_0000_0013
[4] L2SPD = 1
[3] PSPT = 0
[2] SO = 0
[1] PMO = 1
[0] MTP = 1
*/
logic [63:0] local_capabilities_S2;

always_comb begin
    local_capabilities_S2 = 64'b0;

    local_capabilities_S2[4] = cap_if.local_l2spd;
    local_capabilities_S2[3] = cap_if.local_pspt;
    local_capabilities_S2[2] = cap_if.local_so;
    local_capabilities_S2[1] = cap_if.local_pmo;
    local_capabilities_S2[0] = cap_if.local_mtp;
end
////////////////////////////////////////////////////////
////////////////////////////////////////////////////////
///////////////// PARTNER CAPABILITIES /////////////////
////////////////////////////////////////////////////////
////////////////////////////////////////////////////////
logic [63:0] partner_capabilities_DataField_S1;

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        partner_capabilities_DataField_S1 <= 64'h0;
    else if(mb_param_rx_valid && mb_param_rx_msg_id == MBINIT_PARAM_configuration_req)
        partner_capabilities_DataField_S1 <= mb_param_rx_data_Field;
end
// decode
assign cap_if.partner_tarr       = partner_capabilities_DataField_S1[15];
assign cap_if.partner_sbfe       = partner_capabilities_DataField_S1[14];
assign cap_if.partner_is_x8      = partner_capabilities_DataField_S1[13];
assign cap_if.partner_max_speed  = partner_capabilities_DataField_S1[3:0];

/////////////////////////////////////////////////////////
logic [63:0] partner_capabilities_DataField_S2;

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        partner_capabilities_DataField_S2 <= 64'h0;
    else if(mb_param_rx_valid && mb_param_rx_msg_id == MBINIT_PARAM_SBFE_req)
        partner_capabilities_DataField_S2 <= mb_param_rx_data_Field;
end
// Decode
assign cap_if.partner_l2spd = partner_capabilities_DataField_S2[4];
assign cap_if.partner_pspt  = partner_capabilities_DataField_S2[3];
assign cap_if.partner_so    = partner_capabilities_DataField_S2[2];
assign cap_if.partner_pmo   = partner_capabilities_DataField_S2[1];
assign cap_if.partner_mtp   = partner_capabilities_DataField_S2[0];

////////////////////////////////////////////////////////
////////////////////////////////////////////////////////
/////////////// NEGOTIATED CAP /////////////////////////
////////////////////////////////////////////////////////
////////////////////////////////////////////////////////
// ======================================================
// NEGOTIATION BLOCK
// ======================================================

logic partner_s1_valid;
logic partner_s2_valid;

always_comb begin
    ////////////////////////////////////////////////////////
    // DEFAULT = LOCAL (safe before partner arrives)
    ////////////////////////////////////////////////////////

    cap_if.use_x8_mode     = cap_if.local_is_x8;
    cap_if.negotiated_speed= cap_if.local_max_speed;

    cap_if.negotiated_sbfe = cap_if.local_sbfe;
    cap_if.negotiated_tarr = cap_if.local_tarr;

    cap_if.negotiated_l2spd= cap_if.local_l2spd;
    cap_if.negotiated_pspt = cap_if.local_pspt;
    cap_if.negotiated_so   = cap_if.local_so;
    cap_if.negotiated_pmo  = cap_if.local_pmo;
    cap_if.negotiated_mtp  = cap_if.local_mtp;

    ////////////////////////////////////////////////////////
    // S1 NEGOTIATION (when partner S1 valid)
    ////////////////////////////////////////////////////////


    if (partner_s1_valid) begin

        // WIDTH → MIN (X8 dominates)
        cap_if.use_x8_mode =
            cap_if.local_is_x8 | cap_if.partner_is_x8;

        // SPEED → MIN
        cap_if.negotiated_speed =
            (cap_if.local_max_speed < cap_if.partner_max_speed) ?
            cap_if.local_max_speed : cap_if.partner_max_speed;

        // FLAGS → AND
        cap_if.negotiated_sbfe =
            cap_if.local_sbfe & cap_if.partner_sbfe;

        cap_if.negotiated_tarr =
            cap_if.local_tarr & cap_if.partner_tarr;
    end

    ////////////////////////////////////////////////////////
    // S2 NEGOTIATION (SBFE features)
    ////////////////////////////////////////////////////////
    if (partner_s2_valid) begin

        cap_if.negotiated_l2spd =
            cap_if.local_l2spd & cap_if.partner_l2spd;

        cap_if.negotiated_pspt =
            cap_if.local_pspt & cap_if.partner_pspt;

        cap_if.negotiated_so =
            cap_if.local_so & cap_if.partner_so;

        cap_if.negotiated_pmo =
            cap_if.local_pmo & cap_if.partner_pmo;

        cap_if.negotiated_mtp =
            cap_if.local_mtp & cap_if.partner_mtp;
    end
end
//////////////////////////////////////////////////////////////

logic [63:0] negotiated_capabilities_S1;
always_comb begin
    negotiated_capabilities_S1 = 64'b0;

    negotiated_capabilities_S1[15] = cap_if.negotiated_tarr;
    negotiated_capabilities_S1[14] = cap_if.negotiated_sbfe;
    negotiated_capabilities_S1[13] = cap_if.use_x8_mode;
    negotiated_capabilities_S1[3:0]= cap_if.negotiated_speed;
end

logic [63:0] negotiated_capabilities_S2;
always_comb begin
    negotiated_capabilities_S2 = 64'b0;

    negotiated_capabilities_S2[4] = cap_if.negotiated_l2spd;
    negotiated_capabilities_S2[3] = cap_if.negotiated_pspt;
    negotiated_capabilities_S2[2] = cap_if.negotiated_so;
    negotiated_capabilities_S2[1] = cap_if.negotiated_pmo;
    negotiated_capabilities_S2[0] = cap_if.negotiated_mtp;
end

////////////////////////////////////////////////////////
//////////////// Partner Entry Detection /////////////////
////////////////////////////////////////////////////////

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n || !mb_param_enable)
        partner_s1_valid <= 0;
    else if(mb_param_rx_valid && mb_param_rx_msg_id == MBINIT_PARAM_configuration_req)
        partner_s1_valid <= 1;
end

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n || !mb_param_enable)
        partner_s2_valid <= 0;
    else if(mb_param_rx_valid && mb_param_rx_msg_id == MBINIT_PARAM_SBFE_req)
        partner_s2_valid <= 1;
end

////////////////////////////////////////////////////////
//////////////// Entry Detection logic /////////////////
////////////////////////////////////////////////////////
logic s1_entry;
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        s1_entry <= 0;
    else
        s1_entry <= (current_state != MB_S1_PARAM_EXCHANGE_REQ) && (next_state == MB_S1_PARAM_EXCHANGE_REQ);
end

logic s2_entry;
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        s2_entry <= 0;
    else
        s2_entry <= (current_state != MB_S2_FEATURE_EXCHANGE_REQ) && (next_state == MB_S2_FEATURE_EXCHANGE_REQ);
end

////////////////////////////////////////////////////////
/////////////////// TIMEOUT TIMER //////////////////////
////////////////////////////////////////////////////////
logic mb_param_timer_enable;  // to reset and enable the timeout timer.
assign mb_param_timer_enable = mb_param_enable && !mb_param_done && !mb_param_error;
logic mb_param_timeout_expired ;
timeout_counter #(
    .CLK_FRQ_HZ(CLK_FRQ_HZ),
    .TIME_OUT(8)
) mb_param_timeout_timer (
    .clk(clk),
    .timeout_rst_n(rst_n),
    .enable_timeout(mb_param_timer_enable),
    .timeout_expired(mb_param_timeout_expired)
);
assign timeout_error = mb_param_timeout_expired && !mb_param_done;

////////////////////////////////////////////////////////
////////////////// HANDSHAKE FLAGS /////////////////////
////////////////////////////////////////////////////////
logic param_req_rcvd;
logic param_rsp_rcvd;

logic sbfe_req_rcvd;
logic sbfe_rsp_rcvd;
//-----------------------------------------------------
// PARAM REQ received
//-----------------------------------------------------
always_ff @(posedge clk or negedge rst_n) begin
if(!rst_n)
    param_req_rcvd <= 0;
else if(current_state == MB_S1_PARAM_EXCHANGE_REQ && mb_param_rx_valid && mb_param_rx_msg_id == MBINIT_PARAM_configuration_req)
    param_req_rcvd <= 1;
else if(current_state != MB_S1_PARAM_EXCHANGE_REQ)
    param_req_rcvd <= 0;
end
//-----------------------------------------------------
// PARAM RSP received
//-----------------------------------------------------
always_ff @(posedge clk or negedge rst_n) begin
if(!rst_n)
    param_rsp_rcvd <= 0;
else if(current_state == MB_S1_PARAM_EXCHANGE_RSP && mb_param_rx_valid && mb_param_rx_msg_id == MBINIT_PARAM_configuration_resp)
    param_rsp_rcvd <= 1;
else if(current_state != MB_S1_PARAM_EXCHANGE_RSP)
    param_rsp_rcvd <= 0;
end
//-----------------------------------------------------
// SBFE REQ received
//-----------------------------------------------------
always_ff @(posedge clk or negedge rst_n) begin
if(!rst_n)
    sbfe_req_rcvd <= 0;
else if(current_state == MB_S2_FEATURE_EXCHANGE_REQ && mb_param_rx_valid && mb_param_rx_msg_id == MBINIT_PARAM_SBFE_req)
    sbfe_req_rcvd <= 1;
else if(current_state != MB_S2_FEATURE_EXCHANGE_REQ)
    sbfe_req_rcvd <= 0;
end
//-----------------------------------------------------
// SBFE RSP received
//-----------------------------------------------------
always_ff @(posedge clk or negedge rst_n) begin
if(!rst_n)
    sbfe_rsp_rcvd <= 0;
else if(current_state == MB_S2_FEATURE_EXCHANGE_RSP && mb_param_rx_valid && mb_param_rx_msg_id == MBINIT_PARAM_SBFE_resp)
    sbfe_rsp_rcvd <= 1;
else if(current_state != MB_S2_FEATURE_EXCHANGE_RSP)
    sbfe_rsp_rcvd <= 0;
end

////////////////////////////////////////////////////////
////////////////// STATE REGISTER //////////////////////
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

    if(timeout_error)
        next_state = MB_S0_IDLE;

    case(current_state)

        MB_S0_IDLE: begin
            if(mb_param_enable && !mb_param_done)
                next_state = MB_S1_PARAM_EXCHANGE_REQ;
        end
        ////////////////////////////////////////////////
        MB_S1_PARAM_EXCHANGE_REQ: begin
            if(!mb_param_enable || mb_param_error)
                next_state = MB_S0_IDLE; 
            else if(param_req_rcvd && !param_rsp_rcvd)
                next_state = MB_S1_PARAM_EXCHANGE_RSP;
            else if(param_rsp_rcvd) 
                next_state = MB_S2_FEATURE_EXCHANGE_REQ ;
            else 
                next_state = MB_S1_PARAM_EXCHANGE_REQ;
        end
        ////////////////////////////////////////////////
        MB_S1_PARAM_EXCHANGE_RSP: begin
            if(!mb_param_enable || mb_param_error)
                next_state = MB_S0_IDLE; // Return to idle.
            else if(param_rsp_rcvd) begin
                if(cap_if.partner_sbfe)
                    next_state = MB_S2_FEATURE_EXCHANGE_REQ ;
                else
                next_state = MB_S0_IDLE;
        end
        end
        ////////////////////////////////////////////////
        MB_S2_FEATURE_EXCHANGE_REQ: begin
            if(!mb_param_enable || mb_param_error)
                next_state = MB_S0_IDLE;
            else if(sbfe_req_rcvd && !sbfe_rsp_rcvd )
                next_state = MB_S2_FEATURE_EXCHANGE_RSP;
            else 
                next_state = MB_S2_FEATURE_EXCHANGE_REQ;                
            end
        ///////////////////////////////////////////////
        MB_S2_FEATURE_EXCHANGE_RSP: begin
            if(!mb_param_enable || mb_param_error)
                next_state = MB_S0_IDLE;
            else if(sbfe_rsp_rcvd) begin
                next_state = MB_S0_IDLE;
            end            
        end
        ///////////////////////////////////////////////
        MB_S3_STALL:
        next_state = MB_S3_STALL;
        /* begin
            if(!mb_param_enable || mb_param_error)
                next_state = MB_S0_IDLE; // Return to idle.
            else if(mb_param_rx_valid && mb_param_rx_msg_id == MBINIT_PARAM_SBFE_resp && mb_param_rx_MsgInfo == MB_default_MSG_Info)
                next_state = MB_S3_STALL;
            else if(mb_param_rx_valid && mb_param_rx_msg_id == MBINIT_PARAM_SBFE_resp && mb_param_rx_MsgInfo == MB_default_MSG_Info)
                next_state = MB_S0_IDLE;
        end*/
    endcase
end
////////////////////////////////////////////////////////
/////////////// OUTPUT LOGIC ///////////////////////////
////////////////////////////////////////////////////////
always_comb begin
    // Default outputs.
    mb_param_tx_valid       = 1'b0;
    mb_param_tx_msg_id      = msg_no_e'(8'h00);
    mb_param_tx_MsgInfo     = MB_default_MSG_Info;
    mb_param_tx_data_Field  = MB_default_data_Field;

    if(mb_param_enable) begin
    case(current_state)

        MB_S1_PARAM_EXCHANGE_REQ: begin
            if(s1_entry) begin
            mb_param_tx_valid       = 1'b1;
            mb_param_tx_msg_id      = MBINIT_PARAM_configuration_req;
            mb_param_tx_MsgInfo     = MB_default_MSG_Info;
            mb_param_tx_data_Field  = local_capabilities_DataField_S1;    
        end
            end
        MB_S1_PARAM_EXCHANGE_RSP: begin
            mb_param_tx_valid       = 1'b1;
            mb_param_tx_msg_id      = MBINIT_PARAM_configuration_resp;
            mb_param_tx_MsgInfo     = MB_default_MSG_Info;
            mb_param_tx_data_Field  = negotiated_capabilities_S1;    

        end
        MB_S2_FEATURE_EXCHANGE_REQ: begin
            if(s2_entry) begin
            mb_param_tx_valid       = 1'b1;
            mb_param_tx_msg_id      = MBINIT_PARAM_SBFE_req;
            mb_param_tx_MsgInfo     = MB_default_MSG_Info;
            mb_param_tx_data_Field  = local_capabilities_S2;    
            end
        end
        MB_S2_FEATURE_EXCHANGE_RSP: begin
            mb_param_tx_valid       = 1'b1;
            mb_param_tx_msg_id      = MBINIT_PARAM_SBFE_resp;
            mb_param_tx_MsgInfo     = MB_default_MSG_Info;
            mb_param_tx_data_Field  = negotiated_capabilities_S2;    

        end
        /*
        MB_S3_STALL: begin
            mb_param_tx_valid       = 1'b1;
            mb_param_tx_msg_id      = MBINIT_PARAM_SBFE_resp;
            mb_param_tx_MsgInfo     = MB_default_MSG_Info;
            mb_param_tx_data_Field  = MB_default_data_Field;    
        end
        */
    endcase
    end
end

////////////////////////////////////////////////////////
// PHY CONTROL
////////////////////////////////////////////////////////

always_comb begin
    // TX tri-state
    mb_tx_valid_status = 0;
    mb_tx_track_status = 0;
    mb_tx_clk_status   = 0;
    mb_tx_data_status  = 0;
    
    // RX enabled or permitted to be disabled
    mb_rx_valid_status = 0;
    mb_rx_track_status = 0;
    mb_rx_clk_status   = 0;
    mb_rx_data_status  = 0;

    if(mb_param_enable && !mb_param_done) begin

    // RX enabled or permitted to be disabled
    mb_rx_valid_status = 1;
    mb_rx_track_status = 1;
    mb_rx_clk_status   = 1;
    mb_rx_data_status  = 1;

    // TX enabled or permitted to be disabled
    mb_tx_valid_status = 1;
    mb_tx_track_status = 1;
    mb_tx_clk_status   = 1;
    mb_tx_data_status  = 1;
end
end

////////////////////////////////////////////////////////
/////////////// DONE LOGIC //////////////////////////////
////////////////////////////////////////////////////////
always_ff @( posedge clk , negedge rst_n ) begin
    if(!rst_n)
        mb_param_done <= 0;
    else if(current_state == MB_S2_FEATURE_EXCHANGE_RSP && sbfe_rsp_rcvd )        
        mb_param_done <= 1;
    else if(current_state == MB_S1_PARAM_EXCHANGE_RSP && param_rsp_rcvd && !negotiated_capabilities_S1[14])
        mb_param_done <= 1;
end

////////////////////////////////////////////////////////
/////////////// ERROR LOGIC ////////////////////////////
////////////////////////////////////////////////////////
always_ff @( posedge clk , negedge rst_n ) begin
    if(!rst_n)
    mb_param_error <= 0;

    else if(timeout_error)
    mb_param_error <= 1;
    //S1 error.
    else if(mb_param_rx_valid && current_state == MB_S1_PARAM_EXCHANGE_REQ && mb_param_rx_msg_id != MBINIT_PARAM_configuration_req )
    mb_param_error <= 1;
    else if(mb_param_rx_valid && current_state == MB_S1_PARAM_EXCHANGE_RSP && mb_param_rx_msg_id != MBINIT_PARAM_configuration_resp)
    mb_param_error <= 1;
    //S2
    else if(mb_param_rx_valid && current_state == MB_S2_FEATURE_EXCHANGE_REQ && mb_param_rx_msg_id != MBINIT_PARAM_SBFE_req )
    mb_param_error <= 1;
    else if(mb_param_rx_valid && current_state == MB_S2_FEATURE_EXCHANGE_RSP && mb_param_rx_msg_id != MBINIT_PARAM_SBFE_resp )
    mb_param_error <= 1;
    else if(current_state == MB_S0_IDLE)
    mb_param_error <= 0;
end

endmodule