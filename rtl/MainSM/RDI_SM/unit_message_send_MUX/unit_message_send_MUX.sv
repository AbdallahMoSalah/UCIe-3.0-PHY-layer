/*
 * Module: unit_message_send_MUX
 * Description: Multiplexes sideband messages from various RDI state machine handlers
 *              based on the current RDI status state.
 */

import RDI_SM_pkg::*;
import UCIe_pkg::*;

module unit_message_send_MUX(
    // Message inputs from different state handlers
    input  msg_no_e        Reset_message_send,         // Message to send during Reset state
    input  msg_no_e        Retrain_message_send,       // Message to send during Retrain state
    input  msg_no_e        Active_message_send,        // Message to send during Active state
    input  msg_no_e        Active_PMNAK_message_send,  // Message to send during Active_PMNAK state
    input  msg_no_e        L1_message_send,            // Message to send during L1 state
    input  msg_no_e        L2_message_send,            // Message to send during L2 state
    input  msg_no_e        LinkReset_message_send,     // Message to send during LinkReset state
    
    // Control input
    input  RDI_state       rdi_state_sts,              // Current RDI status state

    // Selected message output
    output msg_no_e        message_send                // Final message to be transmitted
);

    // Combinational multiplexing logic based on the current RDI status state
    always_comb begin
        case(rdi_state_sts)
            Reset:        message_send = Reset_message_send;
            Retrain:      message_send = Retrain_message_send;
            Active:       message_send = Active_message_send;
            Active_PMNAK: message_send = Active_PMNAK_message_send;
            L1:           message_send = L1_message_send;
            L2:           message_send = L2_message_send;
            LinkReset:    message_send = LinkReset_message_send;
            default:      message_send = NOP; // Default to No-Operation if state is unhandled or Nop
        endcase
    end

endmodule