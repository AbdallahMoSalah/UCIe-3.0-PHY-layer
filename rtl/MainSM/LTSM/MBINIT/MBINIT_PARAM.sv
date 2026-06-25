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
(
    input  logic clk,
    input  logic rst_n,

    // from LTSM
    input  logic mb_param_enable,

    // to LTSM
    output logic mb_param_done,
    output logic mb_param_error,

    // RX from partner
    input  logic sb_param_rx_valid,
    input  msg_no_e sb_param_rx_msg_id,
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [15:0] sb_param_rx_data_Field, // bits [12:11,8:5] are reserved per UCIe spec
    /* verilator lint_on UNUSEDSIGNAL */

    // TX to partner
    output logic sb_param_tx_valid,
    output msg_no_e sb_param_tx_msg_id,
    output logic [15:0] sb_param_tx_MsgInfo,
    output logic [63:0] sb_param_tx_data_Field,

    //--------------------------------
    //-------- Hard code signal ------
    //--------------------------------
    input logic [4:0] Supported_TX_Vswing,  
    input logic so ,                       
    input logic mtp ,                      
    input logic [1:0] Module_ID,            
    
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
    input logic [3:0] Max_Link_Speed_cap,
    
    // -------------------------------
    // --------- CTRL REG ------------
    // -------------------------------
    // From Phy
    input logic TARR_support_local_ctrl,
    input logic phy_x8_mode_ctrl,
    input logic SPMW,
    input logic Clock_Phase_ctrl,
    input logic Clock_mode_ctrl,
  
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
    output logic Clock_Phase_enable_status,
    output logic Clock_mode_enable_status,
    output logic TARR_enable_status,
    // From Link
    output logic [3:0] Link_Width_enable_status,
    output logic [3:0] Link_Speed_enable_status,
    output logic PMO_enable_status,
    output logic L2SPD_enable_status,
    output logic PSPT_enable_status,
    
    // Sideband FIFO ready (write-side handshake)
    input  logic sb_ltsm_rdy,

    // Timer / Global Error signals
    input  logic global_error
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

logic UCIE_x8;
always_comb begin
    if(phy_x8_mode_ctrl || Target_Link_Width_ctrl == 4'h1 || SPMW) begin
        UCIE_x8 = 1'b1;
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
        if(Clock_Phase_cap == 2'b01 || Clock_Phase_cap == 2'b10)begin
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

typedef enum logic [3:0] {
    MB_S0_IDLE,

    // S1 – Param Exchange (split: SEND waits for FIFO, WAIT waits for partner)
    MB_S1_PARAM_REQ_SEND,   // drive configuration_req until ltsm_rdy=1
    MB_S1_PARAM_REQ_WAIT,   // msg in FIFO; wait for partner's configuration_req

    MB_S1_PARAM_RSP_SEND,   // drive configuration_resp until ltsm_rdy=1
    MB_S1_PARAM_RSP_WAIT,   // msg in FIFO; wait for partner's configuration_resp

    MB_S2_ERROR_CHECK,

    // S3 – Feature Exchange (split)
    MB_S3_FEATURE_REQ_SEND, // drive SBFE_req until ltsm_rdy=1
    MB_S3_FEATURE_REQ_WAIT, // msg in FIFO; wait for partner's SBFE_req

    MB_S3_FEATURE_RSP_SEND, // drive SBFE_resp until ltsm_rdy=1
    MB_S3_FEATURE_RSP_WAIT, // msg in FIFO; wait for partner's SBFE_resp

    MB_S4_ERROR_CHECK,

    MB_S5_ERROR,

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
// ── RX message flags + data-capture – all in one always_ff ──────────────────
// When mb_param_rx_valid is high, a case on mb_param_rx_msg_id:
//   • sets the matching flag
//   • captures the payload into the corresponding register (where applicable)
// All flags are cleared together when the FSM is reset or returns to IDLE.
// Registers that have no associated payload keep their last captured value.
//------------------------------------------------------------------------------
logic param_req_rcvd;
logic param_rsp_rcvd;
logic sbfe_req_rcvd;
logic sbfe_rsp_rcvd;

logic [3:0]  partner_S1_REQ_speed;
logic        partner_S1_REQ_x8;
logic        partner_S1_REQ_tarr;
logic        partner_S1_REQ_sfes;
logic        partner_S1_REQ_clk_phase;
logic        partner_S1_REQ_clk_mode;
logic [4:0]  partner_S2_REQ;
logic        partner_S2_RESP_tarr;
logic        partner_S2_RESP_sfes;
logic        partner_S2_RESP_clk_phase;
logic        partner_S2_RESP_clk_mode;
logic [3:0]  partner_S2_RESP_speed;
logic [4:0]  partner_S4_RESP;

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n || !mb_param_enable) begin
        param_req_rcvd                     <= 1'b0;
        param_rsp_rcvd                     <= 1'b0;
        sbfe_req_rcvd                      <= 1'b0;
        sbfe_rsp_rcvd                      <= 1'b0;
        partner_S1_REQ_speed               <= 4'h0;
        partner_S1_REQ_x8                  <= 1'b0;
        partner_S1_REQ_tarr                <= 1'b0;
        partner_S1_REQ_sfes                <= 1'b0;
        partner_S1_REQ_clk_phase           <= 1'b0;
        partner_S1_REQ_clk_mode            <= 1'b0;
        partner_S2_REQ                     <= 5'h0;
        partner_S2_RESP_tarr               <= 1'b0;
        partner_S2_RESP_sfes               <= 1'b0;
        partner_S2_RESP_clk_phase          <= 1'b0;
        partner_S2_RESP_clk_mode           <= 1'b0;
        partner_S2_RESP_speed              <= 4'h0;
        partner_S4_RESP                    <= 5'h0;
    end else if (current_state == MB_S0_IDLE) begin
        param_req_rcvd <= 1'b0;
        param_rsp_rcvd <= 1'b0;
        sbfe_req_rcvd  <= 1'b0;
        sbfe_rsp_rcvd  <= 1'b0;
    end else if (sb_param_rx_valid) begin
        case (sb_param_rx_msg_id)
            MBINIT_PARAM_configuration_req: begin
                param_req_rcvd  <= 1'b1;
                partner_S1_REQ_speed     <= sb_param_rx_data_Field[3:0];
                partner_S1_REQ_x8        <= sb_param_rx_data_Field[13];
                partner_S1_REQ_tarr      <= sb_param_rx_data_Field[15];
                partner_S1_REQ_sfes      <= sb_param_rx_data_Field[14];
                partner_S1_REQ_clk_phase <= sb_param_rx_data_Field[10];
                partner_S1_REQ_clk_mode  <= sb_param_rx_data_Field[9];
            end
            MBINIT_PARAM_configuration_resp: begin
                if(current_state > MB_S1_PARAM_REQ_SEND) begin
                    param_rsp_rcvd            <= 1'b1;
                    partner_S2_RESP_tarr      <= sb_param_rx_data_Field[15];
                    partner_S2_RESP_sfes      <= sb_param_rx_data_Field[14];
                    partner_S2_RESP_clk_phase <= sb_param_rx_data_Field[10];
                    partner_S2_RESP_clk_mode  <= sb_param_rx_data_Field[9];
                    partner_S2_RESP_speed     <= sb_param_rx_data_Field[3:0];
                end
            end
            MBINIT_PARAM_SBFE_req: begin
                if((current_state > MB_S1_PARAM_RSP_SEND) && param_rsp_rcvd) begin
                    sbfe_req_rcvd   <= 1'b1;
                    partner_S2_REQ  <= sb_param_rx_data_Field[4:0];
                end
            end
            MBINIT_PARAM_SBFE_resp: begin
                if(current_state > MB_S3_FEATURE_REQ_SEND) begin
                    sbfe_rsp_rcvd   <= 1'b1;
                    partner_S4_RESP <= sb_param_rx_data_Field[4:0];
                end
            end
            default : ; // ignore unrelated messages
        endcase
    end
end

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
// Combinatorial lookahead logic for S1 capabilities:
logic [3:0] comb_partner_link_speed_sel;
logic comb_partner_UCIE_x8_sel;
logic comb_partner_TARR_sel;
logic comb_partner_SFES_sel;
logic comb_partner_clk_phase_sel;
logic comb_partner_clk_mode_sel;

assign comb_partner_link_speed_sel = (sb_param_rx_valid && (sb_param_rx_msg_id == MBINIT_PARAM_configuration_req)) ?
                                     sb_param_rx_data_Field[3:0]  : partner_S1_REQ_speed;
assign comb_partner_UCIE_x8_sel    = (sb_param_rx_valid && (sb_param_rx_msg_id == MBINIT_PARAM_configuration_req)) ?
                                     sb_param_rx_data_Field[13]   : partner_S1_REQ_x8;
assign comb_partner_TARR_sel       = (sb_param_rx_valid && (sb_param_rx_msg_id == MBINIT_PARAM_configuration_req)) ?
                                     sb_param_rx_data_Field[15]   : partner_S1_REQ_tarr;
assign comb_partner_SFES_sel       = (sb_param_rx_valid && (sb_param_rx_msg_id == MBINIT_PARAM_configuration_req)) ?
                                     sb_param_rx_data_Field[14]   : partner_S1_REQ_sfes;
assign comb_partner_clk_phase_sel  = (sb_param_rx_valid && (sb_param_rx_msg_id == MBINIT_PARAM_configuration_req)) ?
                                     sb_param_rx_data_Field[10]   : partner_S1_REQ_clk_phase;
assign comb_partner_clk_mode_sel   = (sb_param_rx_valid && (sb_param_rx_msg_id == MBINIT_PARAM_configuration_req)) ?
                                     sb_param_rx_data_Field[9]    : partner_S1_REQ_clk_mode;

logic [3:0] comb_negotiated_speed_val;
assign comb_negotiated_speed_val = (link_speed_sel <= comb_partner_link_speed_sel) ? link_speed_sel : comb_partner_link_speed_sel;

logic [3:0] lookahead_Link_speed;
logic [3:0] lookahead_Link_width;
logic       lookahead_TARR;
logic       lookahead_SFES;
logic       lookahead_clk_phase;
logic       lookahead_clk_mode;

assign lookahead_Link_speed = comb_negotiated_speed_val;
assign lookahead_Link_width = (UCIE_x8 | comb_partner_UCIE_x8_sel) ? 4'h1 : 4'h2;
assign lookahead_TARR       = TARR_sel & comb_partner_TARR_sel;
assign lookahead_SFES       = SFES_sel & comb_partner_SFES_sel;

assign lookahead_clk_phase = (comb_negotiated_speed_val == 4'd4 || comb_negotiated_speed_val == 4'd5) ? 
                             (clk_phase_sel & comb_partner_clk_phase_sel) : 1'b0;

assign lookahead_clk_mode  = (comb_negotiated_speed_val <= 4'd5) ? 
                             (clk_mode_sel & comb_partner_clk_mode_sel) : 1'b1;

// Combinatorial lookahead logic for S2 (SBFE) features:
logic [4:0] comb_partner_S2_REQ;
assign comb_partner_S2_REQ = (sb_param_rx_valid && (sb_param_rx_msg_id == MBINIT_PARAM_SBFE_req)) ? 
                             sb_param_rx_data_Field[4:0] : partner_S2_REQ;

logic comb_partner_l2spd;
logic comb_partner_pspt;
logic comb_partner_so;
logic comb_partner_pmo;
logic comb_partner_mtp;

assign comb_partner_l2spd = comb_partner_S2_REQ[4];
assign comb_partner_pspt  = comb_partner_S2_REQ[3];
assign comb_partner_so    = comb_partner_S2_REQ[2];
assign comb_partner_pmo   = comb_partner_S2_REQ[1];
assign comb_partner_mtp   = comb_partner_S2_REQ[0];

logic lookahead_l2spd;
logic lookahead_pspt;
logic lookahead_so;
logic lookahead_pmo;
logic lookahead_mtp;

assign lookahead_l2spd = L2SPD_sel & comb_partner_l2spd;
assign lookahead_pspt  = PSPT_sel  & comb_partner_pspt;
assign lookahead_so    = so        & comb_partner_so;
assign lookahead_pmo   = PMO_sel   & comb_partner_pmo;
assign lookahead_mtp   = mtp       & comb_partner_mtp;

always_comb begin
    Link_Width_enable_status   = local_Link_width_enabled_status;
    Link_Speed_enable_status   = local_Link_speed_enabled_negotiate_status;
    Clock_Phase_enable_status  = local_clk_phase_negotiated_status;
    Clock_mode_enable_status   = local_clk_mode_negotiated_status;
    TARR_enable_status         = local_TARR_negotiated_status;

    PMO_enable_status          = local_pmo_negotiated_status;
    L2SPD_enable_status        = local_l2spd_negotiated_status;
    PSPT_enable_status         = local_pspt_negotiated_status;

    if(current_state == MB_S0_IDLE) begin
        TARR_enable_status         = 1'b0;
        Clock_Phase_enable_status  = 1'b0;
        Clock_mode_enable_status   = 1'b0;
        Link_Speed_enable_status   = '0;
        Link_Width_enable_status   = 4'h2;
    
        PMO_enable_status          = 1'b0;
        L2SPD_enable_status        = 1'b0;
        PSPT_enable_status         = 1'b0;
    end
    else if (sb_param_rx_valid && (sb_param_rx_msg_id == MBINIT_PARAM_configuration_req)) begin
        Link_Speed_enable_status  = lookahead_Link_speed;
        Link_Width_enable_status  = lookahead_Link_width;
        TARR_enable_status        = lookahead_TARR;
        Clock_Phase_enable_status = lookahead_clk_phase;
        Clock_mode_enable_status  = lookahead_clk_mode;
    end

    if (sb_param_rx_valid && (sb_param_rx_msg_id == MBINIT_PARAM_SBFE_req)) begin
        PMO_enable_status          = lookahead_pmo;
        L2SPD_enable_status        = lookahead_l2spd;
        PSPT_enable_status         = lookahead_pspt;
    end
end

always_ff @(posedge clk or negedge rst_n) begin
    ////////////////////////////////////////////////////////
    // DEFAULT = LOCAL (safe before partner arrives)
    ////////////////////////////////////////////////////////
    if(!rst_n) begin
        local_TARR_negotiated_status               <= 1'b0;
        local_SFES_negotiated                      <= 1'b0;
        local_clk_phase_negotiated_status          <= 1'b0;
        local_clk_mode_negotiated_status           <= 1'b0;
        local_Link_speed_enabled_negotiate_status  <= '0;
        local_Link_width_enabled_status            <= 4'h2;
        
        local_pmo_negotiated_status                <= 1'b0;
        local_l2spd_negotiated_status              <= 1'b0;
        local_pspt_negotiated_status               <= 1'b0;
        local_so_negotiated                        <= 1'b0;  // constant async reset; MB_S0_IDLE reloads
        local_mtp_negotiated                       <= 1'b0;  // constant async reset; MB_S0_IDLE reloads
    end
    else if(current_state == MB_S0_IDLE) begin
        local_TARR_negotiated_status               <= 1'b0;
        local_SFES_negotiated                      <= 1'b0;
        local_clk_phase_negotiated_status          <= 1'b0;
        local_clk_mode_negotiated_status           <= 1'b0;
        local_Link_speed_enabled_negotiate_status  <= '0;
        local_Link_width_enabled_status            <= 4'h2;
        
        local_pmo_negotiated_status                <= 1'b0;
        local_l2spd_negotiated_status              <= 1'b0;
        local_pspt_negotiated_status               <= 1'b0;
        local_so_negotiated                        <= 1'b0;
        local_mtp_negotiated                       <= 1'b0;
    end
    ////////////////////////////////////////////////////////
    // S1 NEGOTIATION (when partner S1 valid)
    ////////////////////////////////////////////////////////
    else if (sb_param_rx_valid && (sb_param_rx_msg_id == MBINIT_PARAM_configuration_req)) begin
        local_Link_speed_enabled_negotiate_status  <= lookahead_Link_speed;
        local_Link_width_enabled_status            <= lookahead_Link_width;
        local_TARR_negotiated_status               <= lookahead_TARR;
        local_SFES_negotiated                      <= lookahead_SFES;
        local_clk_phase_negotiated_status          <= lookahead_clk_phase;
        local_clk_mode_negotiated_status           <= lookahead_clk_mode;
    end

    ////////////////////////////////////////////////////////
    // S2 NEGOTIATION (SBFE features)
    ////////////////////////////////////////////////////////
    else if (sb_param_rx_valid && (sb_param_rx_msg_id == MBINIT_PARAM_SBFE_req)) begin
        local_l2spd_negotiated_status <= lookahead_l2spd;
        local_pspt_negotiated_status  <= lookahead_pspt;
        local_pmo_negotiated_status   <= lookahead_pmo;
        local_so_negotiated           <= lookahead_so;
        local_mtp_negotiated          <= lookahead_mtp;
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
logic partner_SFES_negotiated;
logic partner_clk_phase_negotiated_status;
logic partner_clk_mode_negotiated_status;
logic [3:0] partner_Link_speed_enabled_negotiate_status;

logic partner_l2spd_negotiated_status;
logic partner_pspt_negotiated_status;
logic partner_so_negotiated;
logic partner_pmo_negotiated_status;
logic partner_mtp_negotiated;

logic is_error;
logic is_SFES;



always_comb begin
    partner_TARR_negotiated_status              = partner_S2_RESP_tarr;
    partner_SFES_negotiated                     = partner_S2_RESP_sfes;
    partner_clk_phase_negotiated_status         = partner_S2_RESP_clk_phase;
    partner_clk_mode_negotiated_status          = partner_S2_RESP_clk_mode;
    partner_Link_speed_enabled_negotiate_status = partner_S2_RESP_speed;
end


always_comb begin
    partner_l2spd_negotiated_status              = partner_S4_RESP[4];
    partner_pspt_negotiated_status               = partner_S4_RESP[3];
    partner_so_negotiated                        = partner_S4_RESP[2];
    partner_pmo_negotiated_status                = partner_S4_RESP[1];
    partner_mtp_negotiated                       = partner_S4_RESP[0];
end


always_comb begin
    if(current_state == MB_S2_ERROR_CHECK) begin
        is_error = !((local_TARR_negotiated_status == partner_TARR_negotiated_status) &&
                     (local_SFES_negotiated == partner_SFES_negotiated) &&
                     (local_clk_phase_negotiated_status == partner_clk_phase_negotiated_status) &&
                     (local_clk_mode_negotiated_status == partner_clk_mode_negotiated_status) &&
                     (local_Link_speed_enabled_negotiate_status == partner_Link_speed_enabled_negotiate_status));

        is_SFES = ((local_SFES_negotiated == 1'b1) && (partner_SFES_negotiated == 1'b1));
    end
    else if(current_state == MB_S4_ERROR_CHECK) begin
        is_error = !((local_l2spd_negotiated_status == partner_l2spd_negotiated_status) &&
                     (local_pspt_negotiated_status == partner_pspt_negotiated_status) &&
                     (local_so_negotiated == partner_so_negotiated) &&
                     (local_pmo_negotiated_status == partner_pmo_negotiated_status) &&
                     (local_mtp_negotiated == partner_mtp_negotiated));
        is_SFES = 1'b0;
    end
    else begin
        is_error = 1'b0;
        is_SFES = 1'b0;
    end
end


// Entry-detection flip-flops removed – _SEND states handle first-cycle TX.


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
    if(!mb_param_enable)begin
        next_state = MB_S0_IDLE;
    end
    else if(global_error && !mb_param_done)begin
        next_state = MB_S5_ERROR;
    end
    else begin
        case(current_state)
            MB_S0_IDLE: begin
                if(mb_param_enable)
                    next_state = MB_S1_PARAM_REQ_SEND;
            end
            // ── S1 Param Request ──────────────────────────────────────────────
            MB_S1_PARAM_REQ_SEND: begin
                if(sb_ltsm_rdy)             next_state = MB_S1_PARAM_REQ_WAIT;
            end
            MB_S1_PARAM_REQ_WAIT: begin
                if(param_req_rcvd)       next_state = MB_S1_PARAM_RSP_SEND;
            end
            // ── S1 Param Response ─────────────────────────────────────────────
            MB_S1_PARAM_RSP_SEND: begin
                if(sb_ltsm_rdy)             next_state = MB_S1_PARAM_RSP_WAIT;
            end
            MB_S1_PARAM_RSP_WAIT: begin
                if(param_rsp_rcvd)       next_state = MB_S2_ERROR_CHECK;
            end
            // ── S2 Error Check ────────────────────────────────────────────────
            MB_S2_ERROR_CHECK: begin
                if(!is_error) begin
                    if(is_SFES) next_state = MB_S3_FEATURE_REQ_SEND;
                    else        next_state = MB_S6_DONE;
                end
                else next_state = MB_S5_ERROR;
            end
            // ── S3 Feature Request ────────────────────────────────────────────
            MB_S3_FEATURE_REQ_SEND: begin
                if(sb_ltsm_rdy)             next_state = MB_S3_FEATURE_REQ_WAIT;
            end
            MB_S3_FEATURE_REQ_WAIT: begin
                if(sbfe_req_rcvd)        next_state = MB_S3_FEATURE_RSP_SEND;
            end
            // ── S3 Feature Response ───────────────────────────────────────────
            MB_S3_FEATURE_RSP_SEND: begin
                if(sb_ltsm_rdy)             next_state = MB_S3_FEATURE_RSP_WAIT;
            end
            MB_S3_FEATURE_RSP_WAIT: begin
                if(sbfe_rsp_rcvd)        next_state = MB_S4_ERROR_CHECK;
            end
            // ── S4 Error Check ────────────────────────────────────────────────
            MB_S4_ERROR_CHECK: begin
                if(is_error) next_state = MB_S5_ERROR;
                else         next_state = MB_S6_DONE;
            end
            MB_S6_DONE: begin
               
            end
            MB_S5_ERROR: begin
                
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
    sb_param_tx_valid       = 1'b0;
    sb_param_tx_msg_id      = msg_no_e'(NOTHING);
    sb_param_tx_MsgInfo     = MB_default_MSG_Info;
    sb_param_tx_data_Field  = MB_default_data_Field;

    case(current_state)
        // ── S1 Param REQ SEND: drive msg every cycle until FIFO accepts ──
        MB_S1_PARAM_REQ_SEND: begin
            sb_param_tx_valid      = 1'b1;
            sb_param_tx_msg_id     = MBINIT_PARAM_configuration_req;
            sb_param_tx_MsgInfo    = MB_default_MSG_Info;
            sb_param_tx_data_Field = local_capabilities_DataField_S1;
        end
        // ── S1 Param RSP SEND ─────────────────────────────────────────────
        MB_S1_PARAM_RSP_SEND: begin
            sb_param_tx_valid      = 1'b1;
            sb_param_tx_msg_id     = MBINIT_PARAM_configuration_resp;
            sb_param_tx_MsgInfo    = MB_default_MSG_Info;
            sb_param_tx_data_Field = negotiated_capabilities_S1;
        end
        // ── S3 Feature REQ SEND ───────────────────────────────────────────
        MB_S3_FEATURE_REQ_SEND: begin
            sb_param_tx_valid      = 1'b1;
            sb_param_tx_msg_id     = MBINIT_PARAM_SBFE_req;
            sb_param_tx_MsgInfo    = MB_default_MSG_Info;
            sb_param_tx_data_Field = local_capabilities_DataField_S2;
        end
        // ── S3 Feature RSP SEND ───────────────────────────────────────────
        MB_S3_FEATURE_RSP_SEND: begin
            sb_param_tx_valid      = 1'b1;
            sb_param_tx_msg_id     = MBINIT_PARAM_SBFE_resp;
            sb_param_tx_MsgInfo    = MB_default_MSG_Info;
            sb_param_tx_data_Field = negotiated_capabilities_S2;
        end
        default: begin
            sb_param_tx_valid      = 1'b0;
            sb_param_tx_msg_id     = msg_no_e'(NOTHING);
            sb_param_tx_MsgInfo    = MB_default_MSG_Info;
            sb_param_tx_data_Field = MB_default_data_Field;
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
