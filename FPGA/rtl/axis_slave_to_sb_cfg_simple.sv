`timescale 1ns/1ps
// =============================================================================
// Module  : axis_slave_to_sb_cfg_simple
// Project : UCIe 3.0 PHY - FPGA bring-up
//
// Purpose : A simplified AXI4-Stream Slave bridge for Sideband TX.
//           Instead of decoding packet opcodes to determine length, it uses a
//           simple chunk counter that assumes a fixed packet length (default 4).
// =============================================================================

module axis_slave_to_sb_cfg_simple #(
    parameter int TDATA_W     = 32,
    parameter int TKEEP_W     = TDATA_W/8,
    parameter int PACKET_LEN  = 4,           // fixed packet size in chunks
    parameter int DN_CRD_INIT = 32           // credit count (0 to disable)
)(
    input  logic                 clk,
    input  logic                 rst_n,

    // ---- AXI4-Stream slave ----
    input  logic [TDATA_W-1:0]   s_axis_tdata,
    input  logic [TKEEP_W-1:0]   s_axis_tkeep,   // unused
    input  logic                 s_axis_tlast,   // unused
    input  logic                 s_axis_tvalid,
    output logic                 s_axis_tready,

    // ---- Sideband config DOWNSTREAM face (-> PHY lp_cfg) ----
    output logic [TDATA_W-1:0]   lp_cfg,
    output logic                 lp_cfg_vld,
    input  logic                 pl_cfg_crd      // downstream credit return
);

    localparam bit USE_CRD = (DN_CRD_INIT != 0);
    localparam int CRD_W   = (DN_CRD_INIT <= 1) ? 1 : $clog2(DN_CRD_INIT+1);
    localparam int CNT_W   = $clog2(PACKET_LEN);

    logic [CRD_W-1:0] credit;
    logic [CNT_W-1:0] chunk_cnt;
    logic             in_packet;

    // Credit-gating is checked only at the start of a packet
    wire crd_ok   = (!USE_CRD) || (credit != '0);
    wire start_ok = in_packet ? 1'b1 : crd_ok;

    assign s_axis_tready = start_ok;
    wire   beat          = s_axis_tvalid && s_axis_tready;

    // Drive PHY config ports
    assign lp_cfg     = s_axis_tdata;
    assign lp_cfg_vld = beat;

    // Spend 1 credit at the start of a new packet
    wire req_commit = beat && !in_packet && USE_CRD;

    // Chunk counter
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            chunk_cnt <= '0;
            in_packet <= 1'b0;
        end else if (beat) begin
            if (chunk_cnt == CNT_W'(PACKET_LEN - 1)) begin
                chunk_cnt <= '0;
                in_packet <= 1'b0;
            end else begin
                chunk_cnt <= chunk_cnt + 1'b1;
                in_packet <= 1'b1;
            end
        end
    end

    // Credit tracking
    generate
    if (USE_CRD) begin : g_crd
        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                credit <= CRD_W'(DN_CRD_INIT);
            end else begin
                case ({pl_cfg_crd, req_commit})
                    2'b10:   credit <= (credit == '1) ? credit : credit + 1'b1;
                    2'b01:   credit <= (credit == '0) ? credit : credit - 1'b1;
                    default: credit <= credit; // 00 or 11: no change
                endcase
            end
        end
    end else begin : g_no_crd
        assign credit = '0;
    end
    endgenerate

endmodule
