import UCIe_pkg::*;
import RDI_SM_pkg::*;
import LTSM_state_pkg::*;
import reset_state_pkg::*;
// ============================================================================
// Module      : unit_reset_state
// Description : Manages the main state transitions for the Reset/Active flows
//               in the RDI state machine. Evaluates various link error,
//               disable, reset, and active requests to determine the next state
//               and issue corresponding outgoing messages.
// ============================================================================
module unit_reset_state (
    input logic lclk,                        // Local clock signal
    input logic lp_linkerror,                // Link error indication from physical layer
    input logic Active_handshake_done,       // Signal indicating Active handshake sequence completion
    input logic EN,                          // State machine enable signal
    input LTSM_state_e state_sts,            // Link training state machine status
    input RDI_state lp_state_req,            // State requested by the local/remote layer
    input msg_no_e Massage_Recieve,          // Incoming RDI message decoded by SideBand
    
    output RDI_state next_state,             // Next state computed by the FSM
    output logic Active_handshake_strt,      // Start signal for Active handshake sequence
    output msg_no_e Massage_Send             // Outgoing message to be sent appropriately
);
    typedef enum logic[3:0] {idle,
                             le_req, 
                             le_resp, 
                             linkerror, 
                             d_req, 
                             d_resp, 
                             disabled, 
                             lr_req, 
                             lr_resp, 
                             linkreset, 
                             NOP_rcvd, 
                             training, 
                             INPP, 
                             active_hs, 
                             active,
                             state_disable } reset_state;
    reset_state cs=idle;

    // FSM State transitions and outputs
    always @(posedge lclk) begin
        case (cs)
            idle: begin
                Massage_Send<=NOP;
                next_state<=Reset;
                Active_handshake_strt<=0;
                if (lp_linkerror) begin 
                    Massage_Send<=RDI_LINK_ERROR_REQ;
                    cs<=le_req;
                end
                else if (lp_state_req == Nop) 
                    cs<=NOP_rcvd;
                else if (Massage_Recieve == RDI_LINK_ERROR_REQ) begin
                    Massage_Send<=RDI_LINK_ERROR_RSP;
                    cs<= le_resp;
                end
                else if ((lp_state_req == Active)||state_sts!=RESET)
                    cs<= training;    
                else if (Massage_Recieve== RDI_DISABLE_REQ) begin
                    Massage_Send<=RDI_DISABLE_RSP;
                    cs<= d_resp;
                end
                else if (Massage_Recieve== RDI_LINK_RESET_REQ) begin
                    Massage_Send<=RDI_LINK_RESET_RSP;
                    cs<= lr_resp;
                end
                else if(state_sts==LINKINIT)begin
                    cs<=INPP;

                end
            end
//===========================================================
            le_req: begin   
                Massage_Send<=NOP;             
                if (Massage_Recieve == RDI_LINK_ERROR_RSP)begin
                    cs <= linkerror;
                    next_state<=LinkError;
                    Massage_Send<=NOP;
                end
            end
//===========================================================
            le_resp: begin
                cs <= linkerror;
                next_state<=LinkError;
                Massage_Send<=NOP;
            end
//===========================================================
            // linkerror: Main LinkError resting state. Exits to idle upon disable.
            linkerror: begin
                if (~EN)begin
                    next_state<=Nop;
                    cs <= state_disable;
                end
            end
//===========================================================
            d_req: begin
                Massage_Send<=NOP;
                if (Massage_Recieve == RDI_DISABLE_RSP)begin
                    cs <= disabled;
                    next_state<=Disabled;
                end
            end
//===========================================================
            d_resp: begin
                Massage_Send<=NOP;
                next_state<=Disabled;
                cs <= disabled;
            end
//===========================================================
            // disabled: Main Disabled resting state. Exits to idle upon disable.
            disabled: begin
                if (~EN)begin
                    next_state<=Nop;
                    cs <= state_disable;
                end
            end
//===========================================================
            lr_req: begin
                Massage_Send<=RDI_LINK_RESET_REQ;
                if (Massage_Recieve == RDI_LINK_RESET_RSP)begin
                    next_state<=LinkReset;
                    cs <= linkreset;
                end
            end
//===========================================================
            lr_resp: begin
                Massage_Send<=NOP;
                next_state<=LinkReset;
                cs <= linkreset;
            end
//===========================================================
            // linkreset: Main LinkReset resting state. Exits to idle upon disable.
            linkreset: begin
                if (~EN)begin
                    next_state<=Nop;
                    cs <= state_disable;
                end
            end
//===========================================================
            // NOP_rcvd: Resting state waiting for target active, linkreset, or disable states
            NOP_rcvd: begin
                if (lp_state_req == Active) begin
                    cs <= active_hs;
                    Active_handshake_strt<=1;
                end
                else if (lp_state_req == LinkReset) begin
                    cs <= lr_req;
                    Massage_Send<=RDI_LINK_RESET_REQ;
                end
                else if (lp_state_req == Disabled) begin
                    cs <= d_req;
                    Massage_Send<=RDI_DISABLE_REQ;
                end
            end
//===========================================================
            training: begin
                if (state_sts == LINKINIT)
                    cs <= INPP;
            end
//===========================================================
            INPP: begin
                if (lp_state_req == Nop)
                    cs <= NOP_rcvd;
            end
//===========================================================
            active_hs: begin
                if (Active_handshake_done)begin
                    cs <= active;
                    Active_handshake_strt<=0;
                    next_state<=Active;
                    L2_exit<=0;
                end
            end
//===========================================================
            // active: Main Active resting state. Operates here until disabled.
            active: begin
                if (~EN)begin
                    cs <= state_disable;
                    next_state<=Nop;
                end
            end
//===========================================================
            state_disable: begin
                if (EN)begin
                    next_state<=Reset;
                    cs <= idle;
                end
            end
        endcase
    end
    assign cs_reg = cs;
endmodule