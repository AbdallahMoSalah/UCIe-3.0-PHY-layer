//-----------------------------------------------------------------------------
// Module      : unit_active_state
// Description : Active State Machine for RDI (Raw Data Interface) in UCIe PHY.
//               This module manages state transitions and message exchanges 
//               when the link is in the Active state. It handles operations like
//               Retrain, LinkReset, Disable, L1, L2, and Link Errors.
//-----------------------------------------------------------------------------
import RDI_SM_pkg::*;
import UCIe_pkg::*;
import LTSM_state_pkg::*;

module unit_active_state (
    input  logic         lclk,             // Local clock
    input  logic         rst_n,            // Asynchronous active-low reset
    input  logic         en,               // Enable signal for the active state machine
    input  logic         stall_done,       // Indicator that the stall handshake is complete
    input  logic         timeout_1us,      // 1us timeout for L1/L2 entry
    input  logic         lp_linkerror,     // Link error indicator from Adapter
    input  logic         pl_error,         // Physical Layer error indicator from the PHY wrapper. Triggers transition to Retrain.
    input  RDI_state     lp_state_req,     // Requested state from Adapter
    input  LTSM_state_e  state_sts,        // Current status from the Link Training and Status State Machine (LTSM). Monitored for retraining conditions.
    input  msg_no_e      message_receive,  // Received message from the other interface

    output RDI_state     next_state,       // Next main state to transition to
    output logic         stall_req,        // Request to stall the interface pipeline
    output logic         start_1us_timer,  // Start 1us timer for L1/L2 entry
    output msg_no_e      message_send      // Message to send to the other interface
);

    // active_state enumeration declaring main operational statuses.
    // One-hot encoding is selected here because high-speed interfaces like UCIe benefit
    // from one-hot state machines on both FPGA and ASIC targets. In FPGAs, register
    // resources are abundant, and one-hot encoding reduces next-state combinational logic
    // depth, helping to achieve timing closure at high clock frequencies.
    typedef enum logic [25:0] {
        STATE_DISABLED  = 26'h0000001,
        IDLE            = 26'h0000002,
        LE_SEND_RESP    = 26'h0000004,
        LE_SEND_REQ     = 26'h0000008,
        STALL_HANDSHAKE = 26'h0000010,
        RT_SEND_REQ     = 26'h0000020,
        RT_SEND_RESP    = 26'h0000040,
        LR_SEND_REQ     = 26'h0000080,
        LR_SEND_RESP    = 26'h0000100,
        D_SEND_REQ      = 26'h0000200,
        D_SEND_RESP     = 26'h0000400,
        L1_SEND_REQ     = 26'h0000800,
        L2_SEND_REQ     = 26'h0001000,
        L1_RECEIVE_RESP = 26'h0002000,
        L2_RECEIVE_RESP = 26'h0004000,
        L1_SEND_RESP    = 26'h0008000,
        L2_SEND_RESP    = 26'h0010000,
        L1              = 26'h0020000,
        L2              = 26'h0040000,
        LINK_ERROR      = 26'h0080000,
        RETRAIN         = 26'h0100000,
        LINK_RESET      = 26'h0200000,
        DISABLED        = 26'h0400000,
        WAIT            = 26'h0800000,
        SEND_PMNAK_RESP = 26'h1000000,
        ACTIVE_PMNAK    = 26'h2000000
    } active_state;

    // flow_state enumeration to preserve intent across the 'stall_handshake' delay
    typedef enum logic [3:0] {
        FLOW_RETRAIN_REQ,
        FLOW_RETRAIN_RSP,
        FLOW_LINK_RESET_REQ,
        FLOW_LINK_RESET_RSP,
        FLOW_DISABLE_REQ,
        FLOW_DISABLE_RSP,
        FLOW_L1_FROM_LP,
        FLOW_L1_FROM_ADAPTER,
        FLOW_L2_FROM_LP,
        FLOW_L2_FROM_ADAPTER
    } flow_state;

    // Internal state registers
    active_state current_state;
    flow_state   flow;

    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            current_state   <= STATE_DISABLED;
            flow            <= FLOW_RETRAIN_REQ;
            next_state      <= Nop;
            stall_req       <= 1'b0;
            message_send    <= NOP;
            start_1us_timer <= 1'b0;
        end else if (!en) begin
            current_state   <= STATE_DISABLED;
            flow            <= FLOW_RETRAIN_REQ;
            next_state      <= Nop;
            stall_req       <= 1'b0;
            message_send    <= NOP;
            start_1us_timer <= 1'b0;
        end else begin
            case (current_state)
                // --- STATE_DISABLED STATE ---
                STATE_DISABLED: begin
                    current_state <= IDLE;
                    next_state    <= Active;
                end

                // --- IDLE STATE ---
                IDLE: begin
                    if (message_receive == RDI_LINK_ERROR_REQ) begin
                        current_state <= LE_SEND_RESP; 
                        message_send  <= RDI_LINK_ERROR_RSP;
                    end else if (lp_linkerror) begin
                        current_state <= LE_SEND_REQ; 
                        message_send  <= RDI_LINK_ERROR_REQ;
                    end else if (lp_state_req == Retrain || pl_error || state_sts == PHYRETRAIN) begin
                        flow          <= FLOW_RETRAIN_REQ;
                        current_state <= STALL_HANDSHAKE;
                        stall_req     <= 1'b1;
                    end else if (message_receive == RDI_RETRAIN_REQ) begin
                        current_state <= STALL_HANDSHAKE;
                        flow          <= FLOW_RETRAIN_RSP;
                        stall_req     <= 1'b1;
                    end else if (lp_state_req == LinkReset) begin
                        current_state <= STALL_HANDSHAKE;
                        flow          <= FLOW_LINK_RESET_REQ;
                        stall_req     <= 1'b1;
                    end else if (message_receive == RDI_LINK_RESET_REQ) begin
                        current_state <= STALL_HANDSHAKE;
                        flow          <= FLOW_LINK_RESET_RSP;
                        stall_req     <= 1'b1;
                    end else if (lp_state_req == Disabled) begin
                        current_state <= STALL_HANDSHAKE;
                        flow          <= FLOW_DISABLE_REQ;
                        stall_req     <= 1'b1;
                    end else if (message_receive == RDI_DISABLE_REQ) begin
                        current_state <= STALL_HANDSHAKE;
                        flow          <= FLOW_DISABLE_RSP;
                        stall_req     <= 1'b1;
                    end else if (lp_state_req == L_1) begin
                        current_state <= STALL_HANDSHAKE;
                        flow          <= FLOW_L1_FROM_LP;
                        stall_req     <= 1'b1;
                    end else if (message_receive == RDI_L1_REQ) begin
                        current_state   <= WAIT;
                        start_1us_timer <= 1'b1;
                        flow            <= FLOW_L1_FROM_ADAPTER;
                    end else if (lp_state_req == L_2) begin
                        current_state <= STALL_HANDSHAKE;
                        flow          <= FLOW_L2_FROM_ADAPTER;
                        stall_req     <= 1'b1;
                    end else if (message_receive == RDI_L2_REQ) begin
                        current_state   <= WAIT;
                        start_1us_timer <= 1'b1;
                        flow            <= FLOW_L2_FROM_LP;
                    end 
                end

                // --- STALL HANDSHAKE STATE ---
                STALL_HANDSHAKE: begin
                    stall_req <= 1'b0;
                    if (stall_done) begin
                        case (flow)
                            FLOW_RETRAIN_REQ: begin
                                message_send  <= RDI_RETRAIN_REQ;
                                current_state <= RT_SEND_REQ;
                            end
                            FLOW_RETRAIN_RSP: begin
                                message_send  <= RDI_RETRAIN_RSP;
                                current_state <= RT_SEND_RESP;
                            end
                            FLOW_LINK_RESET_REQ: begin
                                message_send  <= RDI_LINK_RESET_REQ;
                                current_state <= LR_SEND_REQ;      
                            end
                            FLOW_LINK_RESET_RSP: begin
                                message_send  <= RDI_LINK_RESET_RSP;
                                current_state <= LR_SEND_RESP;
                            end
                            FLOW_DISABLE_REQ: begin
                                message_send  <= RDI_DISABLE_REQ;
                                current_state <= D_SEND_REQ;
                            end
                            FLOW_DISABLE_RSP: begin
                                message_send  <= RDI_DISABLE_RSP;
                                current_state <= D_SEND_RESP;
                            end
                            // Both Adapter-initiated and LP-initiated low-power state flows send requests to
                            // establish symmetric agreement on the link state transition.
                            FLOW_L1_FROM_LP: begin
                                message_send  <= RDI_L1_REQ;
                                current_state <= L1_SEND_REQ;
                            end
                            FLOW_L1_FROM_ADAPTER: begin
                                message_send  <= RDI_L1_REQ;
                                current_state <= L1_SEND_REQ;
                            end
                            FLOW_L2_FROM_LP: begin
                                message_send  <= RDI_L2_REQ;
                                current_state <= L2_SEND_REQ;
                            end
                            FLOW_L2_FROM_ADAPTER: begin
                                message_send  <= RDI_L2_REQ;
                                current_state <= L2_SEND_REQ;
                            end
                            default: begin
                                message_send  <= NOP;
                                current_state <= STALL_HANDSHAKE;
                            end
                        endcase
                    end
                end

                // --- WAIT STATE ---
                WAIT: begin
                    if ((lp_state_req == L_1) || (lp_state_req == L_2)) begin
                        current_state   <= STALL_HANDSHAKE;
                        stall_req       <= 1'b1;
                        start_1us_timer <= 1'b0;
                    end else if (timeout_1us) begin
                        current_state   <= SEND_PMNAK_RESP;
                        message_send    <= RDI_PMNAK_RSP;
                        start_1us_timer <= 1'b0;
                    end else begin
                        start_1us_timer <= 1'b1;
                    end
                end

                // --- SEND_PMNAK_RESP STATE ---
                SEND_PMNAK_RESP: begin
                    current_state <= IDLE;
                    message_send  <= NOP;
                    flow          <= FLOW_RETRAIN_REQ;
                end

                // --- LINK ERROR HANDSHAKE STATES ---
                LE_SEND_REQ: begin
                    message_send <= NOP;
                    if (message_receive == RDI_LINK_ERROR_RSP) begin
                        current_state <= LINK_ERROR;
                        next_state    <= LinkError;
                    end
                end
                
                LE_SEND_RESP: begin
                    message_send  <= NOP;
                    current_state <= LINK_ERROR;
                    next_state    <= LinkError;
                end
                
                LINK_ERROR: begin
                    // When en is de-asserted, the outer always block resets current_state to STATE_DISABLED
                end

                // --- RETRAIN HANDSHAKE STATES ---
                RT_SEND_REQ: begin
                    message_send <= NOP;
                    if (message_receive == RDI_RETRAIN_RSP) begin
                        current_state <= RETRAIN;
                        next_state    <= Retrain;
                    end
                end
                
                RT_SEND_RESP: begin
                    message_send  <= NOP;
                    current_state <= RETRAIN;
                    next_state    <= Retrain;
                end
                
                RETRAIN: begin
                    // When en is de-asserted, the outer always block resets current_state to STATE_DISABLED
                end

                // --- LINK RESET HANDSHAKE STATES ---
                LR_SEND_REQ: begin
                    message_send <= NOP;
                    if (message_receive == RDI_LINK_RESET_RSP) begin
                        current_state <= LINK_RESET;
                        next_state    <= LinkReset;
                    end
                end
                
                LR_SEND_RESP: begin
                    message_send  <= NOP;
                    current_state <= LINK_RESET;
                    next_state    <= LinkReset;
                end
                
                LINK_RESET: begin
                    // When en is de-asserted, the outer always block resets current_state to STATE_DISABLED
                end

                // --- DISABLE HANDSHAKE STATES ---
                D_SEND_REQ: begin
                    message_send <= NOP;
                    if (message_receive == RDI_DISABLE_RSP) begin
                        current_state <= DISABLED;
                        next_state    <= Disabled;
                    end
                end
                
                D_SEND_RESP: begin
                    message_send  <= NOP;
                    current_state <= DISABLED;
                    next_state    <= Disabled;
                end
                
                DISABLED: begin
                    // When en is de-asserted, the outer always block resets current_state to STATE_DISABLED
                end

                // --- L1 STATES ---
                L1_SEND_REQ: begin
                    message_send <= NOP;
                    if ((message_receive == RDI_L1_REQ) && (flow == FLOW_L1_FROM_LP)) begin
                        current_state <= L1_RECEIVE_RESP;
                    end else if (message_receive == RDI_PMNAK_RSP) begin
                        current_state <= ACTIVE_PMNAK;
                        next_state    <= Active_PMNAK;
                    end else if (flow == FLOW_L1_FROM_ADAPTER) begin
                        message_send  <= RDI_L1_RSP;
                        current_state <= L1_SEND_RESP;
                    end
                end
                
                L1_RECEIVE_RESP: begin
                    if ((message_receive == RDI_L1_RSP) && (flow == FLOW_L1_FROM_LP)) begin
                        current_state <= L1_SEND_RESP;
                        message_send  <= RDI_L1_RSP;
                    end else if ((message_receive == RDI_L1_RSP) && (flow == FLOW_L1_FROM_ADAPTER)) begin 
                        current_state <= L1;
                        next_state    <= L_1;
                    end
                end
                
                L1_SEND_RESP: begin
                    message_send <= NOP;
                    if (flow == FLOW_L1_FROM_LP) begin
                        current_state <= L1;
                        next_state    <= L_1;
                    end else if (flow == FLOW_L1_FROM_ADAPTER) begin
                        current_state <= L1_RECEIVE_RESP;
                    end
                end
                
                L1: begin
                    // When en is de-asserted, the outer always block resets current_state to STATE_DISABLED
                end

                // --- L2 STATES ---
                L2_SEND_REQ: begin
                    message_send <= NOP;
                    if ((message_receive == RDI_L2_REQ) && (flow == FLOW_L2_FROM_ADAPTER)) begin
                        current_state <= L2_RECEIVE_RESP;
                    end else if (message_receive == RDI_PMNAK_RSP) begin
                        current_state <= ACTIVE_PMNAK;
                        next_state    <= Active_PMNAK;
                    end else if (flow == FLOW_L2_FROM_LP) begin
                        message_send  <= RDI_L2_RSP;
                        current_state <= L2_SEND_RESP;
                    end
                end
                
                L2_RECEIVE_RESP: begin
                    if ((message_receive == RDI_L2_RSP) && (flow == FLOW_L2_FROM_ADAPTER)) begin
                        current_state <= L2_SEND_RESP;
                        message_send  <= RDI_L2_RSP;
                    end else if ((message_receive == RDI_L2_RSP) && (flow == FLOW_L2_FROM_LP)) begin 
                        current_state <= L2;
                        next_state    <= L_2;
                    end
                end
                
                L2_SEND_RESP: begin
                    message_send <= NOP;
                    if (flow == FLOW_L2_FROM_ADAPTER) begin
                        current_state <= L2;
                        next_state    <= L_2;
                    end else if (flow == FLOW_L2_FROM_LP) begin
                        current_state <= L2_RECEIVE_RESP;
                    end
                end
                
                L2: begin
                    // When en is de-asserted, the outer always block resets current_state to STATE_DISABLED
                end

                // --- ACTIVE_PMNAK STATE ---
                ACTIVE_PMNAK: begin
                    // When en is de-asserted, the outer always block resets current_state to STATE_DISABLED
                end

                default: begin
                    current_state <= STATE_DISABLED;
                    next_state    <= Nop;
                    stall_req     <= 1'b0;
                    message_send  <= NOP;
                end
            endcase
        end
    end
endmodule