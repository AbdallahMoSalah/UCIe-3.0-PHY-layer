import RDI_SM_pkg::*;
import UCIe_pkg::*;
module unit_massage_send_MUX(
    input  msg_no_e        Reset_massage_send,
    input  msg_no_e        Retrain_massage_send,
    input  msg_no_e        Active_massage_send,
    input  msg_no_e        Active_PMNAK_massage_send,
    input  msg_no_e        L1_massage_send,
    input  msg_no_e        L2_massage_send,
    input  msg_no_e        LinkReset_massage_send,
    input  RDI_state       rdi_state_sts,

    output msg_no_e        massage_send
);
    always_comb begin
        case(rdi_state_sts)
            Reset: massage_send = Reset_massage_send;
            Retrain: massage_send = Retrain_massage_send;
            Active: massage_send = Active_massage_send;
            Active_PMNAK: massage_send = Active_PMNAK_massage_send;
            L1: massage_send = L1_massage_send;
            L2: massage_send = L2_massage_send;
            LinkReset: massage_send = LinkReset_massage_send;
            default: massage_send = NOP;
        endcase
    end
endmodule