/*
{MBINIT.PARAM configuration req}
---------------------------------
[63:16]: Reserved
[15]   : Tx Adjustment during Runtime Recalibration (TARR) is supported (1) or not supported (0)    not supported (0)
[14]   : Sideband feature extensions is supported (1) or not supported (0)  (internal)
[13]   : UCIe-S x8 if Standard Package. (internal)
[12:11]: Module ID: 0h: 0, 1h: 1, 2h: 2, 3h: 3
[10]   : Clock Phase: 0b: Differential clock, 1b: Quadrature phase
[9]    : Clock Mode - 0b: Strobe mode; 1b: Continuous mode
[8:4]  : Voltage Swing - The encodings are the same as the “Supported Tx Vswing encodings” field of the PHY Capability register
[3:0]  : Max IO Link Speed - The encodings are the same as “Max Link Speeds” field of the UCIe Link Capability register
=====================================================================

{MBINIT.PARAM configuration resp}
---------------------------------
[63:16]: Reserved
[15]   : Tx Adjustment during Runtime Recalibration (TARR) is negotiated (1) or not supported (0)
[14]   : Sideband feature extensions is negotiated (1) or not supported (0)
[13:11]: Reserved
[10]   : Clock Phase: 0b: Differential clock, 1b: Quadrature phase
[9]    : Clock Mode - 0b: Strobe mode; 1b: Continuous mode
[8:4]  : Reserved
[3:0]  : Max IO Link Speed - The encodings are the same as “Max Link Speeds” field of the UCIe Link Capability register
=====================================================================

{MBINIT.PARAM SBFE req}
-----------------------
[63:5] : Reserved
[4]    : L2SPD is supported (1) or not supported (0)
[3]    : PSPT is supported (1) or not supported (0)
[2]    : Sideband-only (SO) port (1), full UCIe port (0)    (Hard code 0)
[1]    : Sideband Performant Mode Operation (PMO) is supported (1) or not supported (0)
[0]    : Management Transport protocol is supported (1) or not supported (0)  (Hard code 0)

=====================================================================

{MBINIT.PARAM SBFE resp}
------------------------
[63:5] : Reserved
[4]    : L2SPD is negotiated (1) or not negotiated (0) (bit - 25 in cap phy register)
[3]    : PSPT is negotiated (1) or not negotiated (0) (bit - 24 in cap phy register)
[2]    : Sideband-only (SO) port (1), full UCIe port (0)
[1]    : Sideband Performant Mode Operation (PMO) is negotiated (1) or not supported (0) (bit - 23 in cap phy register)
[0]    : Management Transport protocol is supported (1) or not supported (0) (bit - 19 in cap phy register)

*/

module MBINIT_PARAM

import UCIe_pkg::*;

#( parameter int CLK_FRQ_HZ = 800000000)
(
    input  logic clk,
    input  logic rst_n,

    // from LTSM
    input  logic mb_param_enable,

    // to LTSM
    output logic mb_param_done,
    output logic mb_param_error,

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

    //--------------------------------
    //-------- Hard code signal ------
    //--------------------------------
    input logic [4:0] Supported_TX_Vswing,  // hard code to 0
    input  logic so ,                       // hard code to 0
    input  logic mtp ,                      // hard code to 0
    input logic [1:0] Module_ID,            // hard code to 0
    
    // -------------------------------
    // ------- CAPABILITY REG --------
    // -------------------------------
    // From PHY
    input logic TARR_support_local_cap,
    input logic [1:0] Clock_Phase_cap,
    input logic [1:0] Clock_mode_cap,
    // From Link
    input logic L2SPD_support_local_cap,
    input logic PSPT_support_local_cap,
    input logic PMO_support_local_cap,
    input logic [2:0] Max_Link_Width_cap,
    input logic [3:0] Max_Link_Speed_cap,
    
    // -------------------------------
    // --------- CTRL REG ------------
    // -------------------------------
    // From Phy
    input logic TARR_support_local_ctrl,
    input logic phy_x8_mode_ctrl,
    input logic Clock_Phase_ctrl,
    input logic Clock_mode_ctrl,
    input logic [3:0] Max_Link_Speed_cap,
  
    // From Link
    input logic L2SPD_support_local_ctrl,
    input logic PSPT_support_local_ctrl,
    input logic PMO_support_local_ctrl,
    input logic [3:0] Target_Link_Width_ctrl,
    input logic [3:0] Target_Link_Speed_ctrl,

    // -------------------------------
    // --------- STATUS REG ----------
    // -------------------------------
    // From Phy 
    output logic Clock_Phase_enable_status;
    output logic Clock_mode_enable_status;
    output logic TARR_enable_status;
    // From Link
    output logic [3:0] Link_Width_enable_status;
    output logic [3:0] Link_Speed_enable_status;
    output logic PMO_enable_status;
    output logic L2SPD_enable_status;
    output logic PSPT_enable_status;
    
    // Timer signals
    output logic mb_param_timer_enable;
    input  logic mb_param_timeout_expired;

);

logic TARR_sel;
assign TARR_sel = TARR_support_local_ctrl &&  TARR_support_local_cap;

logic L2SPD_sel;
logic PSPT_sel;
logic PMO_sel;
assign L2SPD_sel = L2SPD_support_local_ctrl && L2SPD_support_local_cap;
assign PSPT_sel  = PSPT_support_local_ctrl  && PSPT_support_local_cap;
assign PMO_sel   = PMO_support_local_ctrl   && PMO_support_local_cap;

logic SFES_sel;
assign SFES_sel = L2SPD_sel || PSPT_sel || PMO_sel;

// عايزين نشوف حوار ال SPMW
logic UCIE_x8;
always_comb begin
    if(phy_x8_mode_ctrl || Target_Link_Width_ctrl == 4'b0001 ) begin
        if(Max_Link_Width_cap >= 3'b000 || Max_Link_Width_cap == 3'b111)begin 
            UCIE_x8 = 1'b1;
        end
        else begin
            UCIE_x8 = 1'b0;
        end
    end
    else begin
        UCIE_x8 = 1'b0;
    end
end



//speed selection
logic [3:0] link_speed_sel;
always_comb begin
    if(Target_Link_Speed_ctrl <= Max_Link_Speed_cap ) begin
        link_speed_sel = Target_Link_Speed_ctrl;
    end
    else begin
        link_speed_sel = Max_Link_Speed_cap;
    end
end



logic clk_mode_sel;
always_comb begin
    if(link_speed_sel <= 4'b0101)begin
        if(Clock_mode_cap == 2'b00) begin
            clk_mode_sel = Clock_mode_ctrl;
        end
        else begin
            clk_mode_sel = 1'b1;
        end
    end
    else begin 
        clk_mode_sel = 1'b1;
    end
end






logic clk_phase_sel;
always_comb begin
    if(link_speed_sel <= 4'b0101) begin
        if(Clock_phase_cap == 2'b01 || Clock_phase_cap == 2'b10)begin
            if(link_speed_sel== 4'b0100 || link_speed_sel== 4'b0101 ) begin
                clk_phase_sel = Clock_Phase_ctrl;
            end
            else begin
                clk_phase_sel = 1'b0;
            end
        end
        else begin
            clk_phase_sel = 1'b0;
        end
    end
    else begin
        clk_phase_sel = 1'b0;
    end
end

////////////////////////////////////////////////////////
////////////////////// STATES //////////////////////////
////////////////////////////////////////////////////////

typedef enum logic [2:0] { 
    MB_S0_IDLE,

    MB_S1_PARAM_EXCHANGE_REQ,
    MB_S1_PARAM_EXCHANGE_RSP,

    MB_S2_ERROR_CHECK,

    MB_S3_FEATURE_EXCHANGE_REQ,
    MB_S3_FEATURE_EXCHANGE_RSP,

    MB_S4_ERROR_CHECK,

    MB_S5_ERROR

    MB_S6_DONE
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

[15]    TARR         
[14]    SBFE         
[13]    x32          
[12:11] ModuleID     
[10]    ClockPhase   
[9]     ClockMode   
[8:4]   Vswing      
[3:0]   MaxSpeed     
*/
logic [63:0] local_capabilities_DataField_S1;
always_comb begin
    local_capabilities_DataField_S1 = 64'b0;

    local_capabilities_DataField_S1[15]     = TARR_sel;
    local_capabilities_DataField_S1[14]     = SFES_sel;
    local_capabilities_DataField_S1[13]     = UCIE_x8;   //  width
    local_capabilities_DataField_S1[12:11]  = Module_ID;
    local_capabilities_DataField_S1[10]     = clk_phase_sel; 
    local_capabilities_DataField_S1[9]      = clk_mode_sel;
    local_capabilities_DataField_S1[8:4]    = Supported_TX_Vswing;
    local_capabilities_DataField_S1[3:0]    = link_speed_sel;
end

//*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*

/*
SBFE_req

[4] L2SPD   
[3] PSPT    
[2] SO      
[1] PMO     
[0] MTP     
*/
logic [63:0] local_capabilities_DataField_S2;

always_comb begin
    local_capabilities_DataField_S2 = 64'b0;

    local_capabilities_DataField_S2[4] = L2SPD_sel;
    local_capabilities_DataField_S2[3] = PSPT_sel;
    local_capabilities_DataField_S2[2] = so;
    local_capabilities_DataField_S2[1] = PMO_sel;
    local_capabilities_DataField_S2[0] = mtp;
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

logic partner_TARR_sel;
logic partner_SFES_sel;
logic partner_UCIE_x8_sel;
logic [1:0]partner_Module_ID_sel;
logic partner_clk_phase_sel;
logic partner_clk_mode_sel;
logic [4:0]partner_Supported_TX_Vswing_sel;
logic [3:0]partner_link_speed_sel;



always_comb begin

    partner_TARR_sel                = partner_capabilities_DataField_S1[15];
    partner_SFES_sel                = partner_capabilities_DataField_S1[14];
    partner_UCIE_x8_sel             = partner_capabilities_DataField_S1[13];
    partner_Module_ID_sel           = partner_capabilities_DataField_S1[12:11];
    partner_clk_phase_sel           = partner_capabilities_DataField_S1[10];
    partner_clk_mode_sel            = partner_capabilities_DataField_S1[9];
    partner_Supported_TX_Vswing_sel = partner_capabilities_DataField_S1[8:4];
    partner_link_speed_sel          = partner_capabilities_DataField_S1[3:0];
end

/////////////////////////////////////////////////////////

logic [63:0] partner_capabilities_DataField_S2;
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        partner_capabilities_DataField_S2 <= 64'h0;
    else if(mb_param_rx_valid && mb_param_rx_msg_id == MBINIT_PARAM_SBFE_req)
        partner_capabilities_DataField_S2 <= mb_param_rx_data_Field;
end

logic partner_l2spd;
logic partner_pspt;
logic partner_so;
logic partner_pmo;
logic partner_mtp;

// Decode

assign partner_l2spd = partner_capabilities_DataField_S2[4];
assign partner_pspt  = partner_capabilities_DataField_S2[3];
assign partner_so    = partner_capabilities_DataField_S2[2];
assign partner_pmo   = partner_capabilities_DataField_S2[1];
assign partner_mtp   = partner_capabilities_DataField_S2[0];

////////////////////////////////////////////////////////
////////////////////////////////////////////////////////
/////////////// NEGOTIATED CAP /////////////////////////
////////////////////////////////////////////////////////
////////////////////////////////////////////////////////
// ======================================================
// NEGOTIATION BLOCK
// ======================================================

logic local_TARR_negotiated_status;
logic local_clk_phase_negotiated_status;
logic local_clk_mode_negotiated_status;
logic [3:0] local_Link_speed_enabled_negotiate_status;
logic local_pmo_negotiated_status;
logic local_l2spd_negotiated_status;
logic local_pspt_negotiated_status;

logic local_SFES_negotiated;
logic local_so_negotiated;
logic local_mtp_negotiated;

logic [3:0] local_Link_width_enabled_status;

// regester file outputs
//S1_req
assign Link_Width_enable_status   = local_Link_width_enabled_status;
assign Link_Speed_enable_status   = local_Link_speed_enabled_negotiate_status;
assign Clock_Phase_enable_status  = local_clk_phase_negotiated_status;
assign Clock_mode_enable_status   = local_clk_mode_negotiated_status;
assign TARR_enable_status         = local_TARR_negotiated_status;
//S2_req
assign PMO_enable_status          = local_pmo_negotiated_status;
assign L2SPD_enable_status        = local_l2spd_negotiated_status;
assign PSPT_enable_status         = local_pspt_negotiated_status;

always_ff @(posedge clk or negedge rst_n) begin
    ////////////////////////////////////////////////////////
    // DEFAULT = LOCAL (safe before partner arrives)
    ////////////////////////////////////////////////////////
    if(!rst_n) begin
        local_TARR_negotiated_status               <= TARR_sel;
        local_SFES_negotiated                      <= SFES_sel;
        local_clk_phase_negotiated_status          <= clk_phase_sel;
        local_clk_mode_negotiated_status           <= clk_mode_sel;
        local_Link_speed_enabled_negotiate_status  <= link_speed_sel;
        
        local_pmo_negotiated_status                <= pmo_sel;
        local_l2spd_negotiated_status              <= l2spd_sel;
        local_pspt_negotiated_status               <= pspt_sel;
        local_so_negotiated                        <= so;
        local_mtp_negotiated                       <= mtp;
    end

    ////////////////////////////////////////////////////////
    // S1 NEGOTIATION (when partner S1 valid)
    ////////////////////////////////////////////////////////
    else if (param_req_rcvd) begin
        local_Link_width_enabled_status           <= UCIE_x8        | partner_UCIE_x8_sel;
        local_TARR_negotiated_status              <= TARR_sel       & partner_TARR_sel;
        local_SFES_negotiated                     <= SFES_sel       & partner_SFES_sel;
        local_clk_phase_negotiated_status         <= clk_phase_sel  & partner_clk_phase_sel;
        local_clk_mode_negotiated_status          <= clk_mode_sel   & partner_clk_mode_sel;
        local_Link_speed_enabled_negotiate_status <= (link_speed_sel <= partner_link_speed_sel) ? link_speed_sel : partner_link_speed_sel;
    end

    ////////////////////////////////////////////////////////
    // S2 NEGOTIATION (SBFE features)
    ////////////////////////////////////////////////////////
    else if (sbfe_req_rcvd) begin
        local_l2spd_negotiated_status <= l2spd_sel     & partner_l2spd;
        local_pspt_negotiated_status  <= pspt_sel      & partner_pspt;
        local_so_negotiated           <= so            & partner_so;
        local_pmo_negotiated_status   <= pmo_sel       & partner_pmo;
        local_mtp_negotiated          <= mtp           & partner_mtp;
    end
end
//////////////////////////////////////////////////////////////

logic [63:0] negotiated_capabilities_S1;
always_comb begin
    negotiated_capabilities_S1 = 64'b0;

    negotiated_capabilities_S1[15] = local_TARR_negotiated_status;
    negotiated_capabilities_S1[14] = local_SFES_negotiated;
    negotiated_capabilities_S1[10] = local_clk_phase_negotiated_status;
    negotiated_capabilities_S1[9]  = local_clk_mode_negotiated_status;
    negotiated_capabilities_S1[3:0]= local_Link_speed_enabled_negotiate_status;
end

logic [63:0] negotiated_capabilities_S2;
always_comb begin
    negotiated_capabilities_S2 = 64'b0;

    negotiated_capabilities_S2[4] = local_l2spd_negotiated_status;
    negotiated_capabilities_S2[3] = local_pspt_negotiated_status;
    negotiated_capabilities_S2[2] = local_so_negotiated;
    negotiated_capabilities_S2[1] = local_pmo_negotiated_status;
    negotiated_capabilities_S2[0] = local_mtp_negotiated;
end

////////////////////////////////////////////////////////
/////////// partner RESP Negotiation log  //////////////
////////////////////////////////////////////////////////
logic partner_TARR_negotiated_status;
logic partner_SFES_negotiated                    
logic partner_clk_phase_negotiated_status        
logic partner_clk_mode_negotiated_status         
logic [3:0] partner_Link_speed_enabled_negotiate_status 


logic partner_l2spd_negotiated_status;
logic partner_pspt_negotiated_status;
logic partner_so_negotiated;
logic partner_pmo_negotiated_status;
logic partner_mtp_negotiated;


always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n || !mb_param_enable)
        partner_S2_RESP <= 64'b0;
    else if(mb_param_rx_valid && mb_param_rx_msg_id == MBINIT_PARAM_configuration_resp)
        partner_S2_RESP <= mb_param_rx_data_Field;
end

logic [63:0] partner_S2_RESP;
always_comb begin
    partner_TARR_negotiated_status              = partner_S2_RESP[15];
    partner_SFES_negotiated                     = partner_S2_RESP[14];
    partner_clk_phase_negotiated_status         = partner_S2_RESP[10];
    partner_clk_mode_negotiated_status          = partner_S2_RESP[9];
    partner_Link_speed_enabled_negotiate_status = partner_S2_RESP[3:0];
end

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n || !mb_param_enable)
        partner_S4_RESP <= 64'b0;
    else if(mb_param_rx_valid && mb_param_rx_msg_id == MBINIT_PARAM_configuration_resp)
        partner_S4_RESP <= mb_param_rx_data_Field;
end

logic [63:0] partner_S4_RESP;
always_comb begin
    partner_l2spd_negotiated_status              = partner_S4_RESP[4];
    partner_pspt_negotiated_status               = partner_S4_RESP[3];
    partner_so_negotiated                        = partner_S4_RESP[2];
    partner_pmo_negotiated_status                = partner_S4_RESP[1];
    partner_mtp_negotiated                       = partner_S4_RESP[0];
end


always_comb begin
    if(current_state == MB_S2_ERROR_CHECK) begin
        is_error != (local_TARR_negotiated_status == partner_TARR_negotiated_status) &&
                    (local_SFES_negotiated == partner_SFES_negotiated) &&
                    (local_clk_phase_negotiated_status == partner_clk_phase_negotiated_status) &&
                    (local_clk_mode_negotiated_status == partner_clk_mode_negotiated_status) &&
                    (local_Link_speed_enabled_negotiate_status == partner_Link_speed_enabled_negotiate_status);

        is_SFES = ((local_SFES_negotiated == 1'b1) && (partner_SFES_negotiated == 1'b1));
    end
    else if(current_state == MB_S4_ERROR_CHECK) begin
        is_error != (local_l2spd_negotiated_status == partner_l2spd_negotiated_status) &&
                    (local_pspt_negotiated_status == partner_pspt_negotiated_status) &&
                    (local_so_negotiated == partner_so_negotiated) &&
                    (local_pmo_negotiated_status == partner_pmo_negotiated_status) &&
                    (local_mtp_negotiated == partner_mtp_negotiated);
    end
    else begin
        is_error = 1'b0;
        is_SFES = 1'b0;
    end
end


////////////////////////////////////////////////////////
//////////////// Entry Detection logic /////////////////
////////////////////////////////////////////////////////
logic s1_req_entry;
logic s1_resp_entry;
logic s3_req_entry;
logic s3_resp_entry;
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        s1_req_entry  <= 0;
        s1_resp_entry <= 0;
        s3_req_entry  <= 0;
        s3_resp_entry <= 0;
    end

    else begin
        s1_req_entry  <= (current_state != MB_S1_PARAM_EXCHANGE_REQ)   && (next_state == MB_S1_PARAM_EXCHANGE_REQ);
        s1_resp_entry <= (current_state != MB_S1_PARAM_EXCHANGE_RSP)   && (next_state == MB_S1_PARAM_EXCHANGE_RSP);
        s3_req_entry  <= (current_state != MB_S3_FEATURE_EXCHANGE_REQ) && (next_state == MB_S3_FEATURE_EXCHANGE_REQ);
        s3_resp_entry <= (current_state != MB_S3_FEATURE_EXCHANGE_RSP) && (next_state == MB_S3_FEATURE_EXCHANGE_RSP);
    end
end
////////////////////////////////////////////////////////
/////////////////// TIMEOUT TIMER //////////////////////
////////////////////////////////////////////////////////
logic mb_param_timeout_error;
assign mb_param_timeout_error = mb_param_timeout_expired && !mb_param_done;

assign mb_param_timer_enable = mb_param_enable && !mb_param_done && !mb_param_error;

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
else if(current_state == MB_S3_FEATURE_EXCHANGE_REQ && mb_param_rx_valid && mb_param_rx_msg_id == MBINIT_PARAM_SBFE_req)
    sbfe_req_rcvd <= 1;
else if(current_state != MB_S3_FEATURE_EXCHANGE_REQ)
    sbfe_req_rcvd <= 0;
end
//-----------------------------------------------------
// SBFE RSP received
//-----------------------------------------------------
always_ff @(posedge clk or negedge rst_n) begin
if(!rst_n)
    sbfe_rsp_rcvd <= 0;
else if(current_state == MB_S3_FEATURE_EXCHANGE_RSP && mb_param_rx_valid && mb_param_rx_msg_id == MBINIT_PARAM_SBFE_resp)
    sbfe_rsp_rcvd <= 1;
else if(current_state != MB_S3_FEATURE_EXCHANGE_RSP)
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

    case(current_state)
        MB_S0_IDLE: begin
            if(mb_param_enable) begin
                next_state = MB_S1_PARAM_EXCHANGE_REQ;
            end
            else if(mb_param_timeout_error)begin
                next_state = MB_S5_ERROR;
            end
        end
        ////////////////////////////////////////////////
        MB_S1_PARAM_EXCHANGE_REQ: begin
            if(!mb_param_enable)begin
                next_state = MB_S0_IDLE;
            end 
            else if(mb_param_timeout_error)begin
                next_state = MB_S5_ERROR;
            end
            else if(param_req_rcvd) begin
                next_state = MB_S1_PARAM_EXCHANGE_RSP;
            end
            else begin
                next_state = MB_S1_PARAM_EXCHANGE_REQ;
            end
        end
        ////////////////////////////////////////////////
        MB_S1_PARAM_EXCHANGE_RSP: begin
            if(!mb_param_enable)begin
                next_state = MB_S0_IDLE; // Return to idle.
            end
            else if(mb_param_timeout_error)begin
                next_state = MB_S5_ERROR;
            end
            else if(param_rsp_rcvd) begin
                next_state = MB_S2_ERROR_CHECK ;
            end
            else begin
                next_state = MB_S1_PARAM_EXCHANGE_RSP;
            end
        end
        ////////////////////////////////////////////////
        MB_S2_ERROR_CHECK: begin
            if(!is_error && !mb_param_timeout_error) begin
                if(is_SFES)begin
                    next_state = MB_S3_FEATURE_EXCHANGE_REQ;
                end
                else begin
                    next_state = MB_S6_DONE;
                end
            end
            else begin
                next_state = MB_S5_ERROR;
            end
        end
        ////////////////////////////////////////////////
        MB_S3_FEATURE_EXCHANGE_REQ: begin
            if(!mb_param_enable)begin
                next_state = MB_S0_IDLE;
            end
            else if(mb_param_timeout_error)begin
                next_state = MB_S5_ERROR;
            end
            else if(sbfe_req_rcvd)begin
                next_state = MB_S3_FEATURE_EXCHANGE_RSP;
            end
            else begin
                next_state = MB_S3_FEATURE_EXCHANGE_REQ;                
            end
        end
        ///////////////////////////////////////////////
        MB_S3_FEATURE_EXCHANGE_RSP: begin
            if(!mb_param_enable)begin
                next_state = MB_S0_IDLE;
            end
            else if(mb_param_timeout_error)begin
                next_state = MB_S5_ERROR;
            end
            else if(sbfe_rsp_rcvd) begin
                next_state = MB_S4_ERROR_CHECK;
            end
            else begin
                next_state = MB_S3_FEATURE_EXCHANGE_RSP;
            end            
        end
        ///////////////////////////////////////////////
        MB_S4_ERROR_CHECK: begin
            if(is_error)begin
                next_state = MB_S5_ERROR;
            end
            else begin
                next_state = MB_S6_DONE;
            end
        end
        ///////////////////////////////////////////////
        MB_S6_DONE: begin
            if(!mb_param_enable) begin
                next_state = MB_S0_IDLE;
            end 
            else begin
                next_state = MB_S6_DONE;
            end   
        end
        ///////////////////////////////////////////////
        MB_S5_ERROR: begin
            if(!mb_param_enable) begin
                next_state = MB_S0_IDLE;
            end 
            else begin
                next_state = MB_S5_ERROR;
            end   
        end
        default: begin
            next_state = MB_S0_IDLE;
        end
    endcase
end
////////////////////////////////////////////////////////
/////////////// OUTPUT LOGIC ///////////////////////////
////////////////////////////////////////////////////////
always_comb begin
    // Default outputs.
    mb_param_tx_valid       = 1'b0;
    mb_param_tx_msg_id      = msg_no_e'(NOTHING);
    mb_param_tx_MsgInfo     = MB_default_MSG_Info;
    mb_param_tx_data_Field  = MB_default_data_Field;

    case(current_state)

        MB_S1_PARAM_EXCHANGE_REQ: begin
            if(s1_req_entry) begin
                mb_param_tx_valid       = 1'b1;
                mb_param_tx_msg_id      = MBINIT_PARAM_configuration_req;
                mb_param_tx_MsgInfo     = MB_default_MSG_Info;
                mb_param_tx_data_Field  = local_capabilities_DataField_S1;    
            end
            else begin
                mb_param_tx_valid       = 1'b0;
                mb_param_tx_msg_id      = msg_no_e'(NOTHING);
                mb_param_tx_MsgInfo     = MB_default_MSG_Info;
                mb_param_tx_data_Field  = MB_default_data_Field;
            end
        end

        MB_S1_PARAM_EXCHANGE_RSP: begin
            if(s1_resp_entry) begin
                mb_param_tx_valid       = 1'b1;
                mb_param_tx_msg_id      = MBINIT_PARAM_configuration_resp;
                mb_param_tx_MsgInfo     = MB_default_MSG_Info;
                mb_param_tx_data_Field  = negotiated_capabilities_S1;    
            end
            else begin
                mb_param_tx_valid       = 1'b0;
                mb_param_tx_msg_id      = msg_no_e'(NOTHING);
                mb_param_tx_MsgInfo     = MB_default_MSG_Info;
                mb_param_tx_data_Field  = MB_default_data_Field;                
            end
        end

        MB_S3_FEATURE_EXCHANGE_REQ: begin
            if(s3_req_entry) begin
                mb_param_tx_valid       = 1'b1;
                mb_param_tx_msg_id      = MBINIT_PARAM_SBFE_req;
                mb_param_tx_MsgInfo     = MB_default_MSG_Info;
                mb_param_tx_data_Field  = local_capabilities_DataField_S2;    
            end
            else begin
                mb_param_tx_valid       = 1'b0;
                mb_param_tx_msg_id      = msg_no_e'(NOTHING);
                mb_param_tx_MsgInfo     = MB_default_MSG_Info;
                mb_param_tx_data_Field  = MB_default_data_Field;
            end
        end

        MB_S3_FEATURE_EXCHANGE_RSP: begin
            if(s3_resp_entry) begin
                mb_param_tx_valid       = 1'b1;
                mb_param_tx_msg_id      = MBINIT_PARAM_SBFE_resp;
                mb_param_tx_MsgInfo     = MB_default_MSG_Info;
                mb_param_tx_data_Field  = negotiated_capabilities_S2;    
            end
            else begin
                mb_param_tx_valid       = 1'b0;
                mb_param_tx_msg_id      = msg_no_e'(NOTHING);
                mb_param_tx_MsgInfo     = MB_default_MSG_Info;
                mb_param_tx_data_Field  = MB_default_data_Field;                
            end
        end

        default: begin
            mb_param_tx_valid       = 1'b0;
            mb_param_tx_msg_id      = msg_no_e'(NOTHING);
            mb_param_tx_MsgInfo     = MB_default_MSG_Info;
            mb_param_tx_data_Field  = MB_default_data_Field;                
        end
    endcase
end

////////////////////////////////////////////////////////
/////////////// DONE LOGIC //////////////////////////////
////////////////////////////////////////////////////////
always_comb begin
    mb_param_done = (current_state == MB_S6_DONE);
end

////////////////////////////////////////////////////////
/////////////// ERROR LOGIC ////////////////////////////
////////////////////////////////////////////////////////
always_comb begin
    mb_param_error = (current_state == MB_S5_ERROR);
end

endmodule