// =============================================================================
// Module      : Link_Mgmt_Demux
// Description : Specialized demultiplexer for UCIe Link Management RX messages.
//               Routes messages to either RDI or LTSM interfaces based on
//               the decoded message number.
// =============================================================================

import UCIe_pkg::*;

module Link_Mgmt_Demux (
    // Inputs from DePacketizer
    input  msg_no_e      rx_msg_no_raw,
    input  logic [15:0]  rx_msginfo_raw,
    input  logic [63:0]  rx_payload_raw,
    input  logic         rx_vld_raw,
    input  logic         rx_stall_raw,

    // RDI Interface
    output logic         RDI_vld_rcvd,
    output logic [ 7:0]  RDI_msg_no_rcvd,
    output logic         stall_rcvd,

    // LTSM Interface
    output logic         ltsm_vld_rcvd,
    output logic [ 7:0]  ltsm_msg_no_rcvd,
    output logic [63:0]  msg_data_rcvd,
    output logic [15:0]  msg_info_rcvd
);

    logic is_rdi_msg;

    always_comb begin
        // RDI messages in UCIe_pkg occupy the range from RDI_ACTIVE_REQ to RDI_PMNAK_RSP.
        // NOP (32) is also part of this range.
        is_rdi_msg = (rx_msg_no_raw >= RDI_ACTIVE_REQ && rx_msg_no_raw <= RDI_PMNAK_RSP);
    end

    // RDI Outputs
    assign RDI_vld_rcvd    = rx_vld_raw && is_rdi_msg;
    assign RDI_msg_no_rcvd = rx_msg_no_raw[7:0];
    assign stall_rcvd      = rx_stall_raw;

    // LTSM Outputs
    assign ltsm_vld_rcvd    = rx_vld_raw && !is_rdi_msg;
    assign ltsm_msg_no_rcvd = rx_msg_no_raw[7:0];
    assign msg_data_rcvd    = rx_payload_raw;
    assign msg_info_rcvd    = rx_msginfo_raw;

endmodule
