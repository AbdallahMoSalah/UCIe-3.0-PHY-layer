`timescale 1ns/1ps
// =============================================================================
// Module  : axis_slave_to_sb_cfg
// Project : UCIe 3.0 PHY - FPGA bring-up
//
// Purpose : AXI4-Stream SLAVE (sink) that drives the Sideband RDI config
//           DOWNSTREAM face (adapter -> PHY): lp_cfg / lp_cfg_vld.
//           A DMA's MM2S channel (or an AXIS-stream FIFO the CPU fills) pushes
//           32-bit config chunks in here; each AXIS beat == one lp_cfg chunk.
//
// Wire format (matches rdi_aggregator chunk order):
//     chunk0 = header[31:0]   (opcode in [4:0])
//     chunk1 = header[63:32]
//     chunk2 = payload[31:0]  (write data)        -- only for 3-chunk messages
//     chunk3 = payload[63:32] (write data hi)     -- only for 4-chunk messages
//   The message length (2 / 3 / 4 chunks) is decoded from the chunk0 opcode,
//   exactly as rdi_aggregator does, so the two stay in lock-step.  TLAST is
//   accepted for DMA compatibility but NOT relied upon for framing.
//
// ---- Credit loop (downstream) -------------------------------------------------
//   The Sideband aggregator has NO ready/back-pressure on lp_cfg; it simply
//   consumes a chunk on every lp_cfg_vld cycle (and tolerates bubbles).  Flow
//   control is by CREDITS instead:
//
//     pl_cfg_crd : PHY -> adapter, one pulse per *request* message drained from
//                  the downstream req FIFO  (RDI_control: pl_cfg_crd=dfifo_req_rinc).
//
//   This bridge is the adapter side, so it owns the downstream credit counter:
//     - starts at DN_CRD_INIT (= the PHY downstream req-FIFO depth, 32),
//     - spends 1 credit when it launches a REQUEST message,
//     - replenishes 1 on every pl_cfg_crd pulse.
//   Credit is checked only at a message boundary; once a message is in flight
//   its remaining chunks always flow (we never half-send a message).
//
//   COMPLETION messages from the adapter go to a separate (comp) FIFO in the
//   PHY and never return a pl_cfg_crd, so they are NOT credit-gated and do NOT
//   spend a credit -- otherwise the counter would leak to 0 and deadlock.
//
//   DN_CRD_INIT = 0 disables gating entirely (always allowed) for early bring-up.
// =============================================================================

import sb_pkg::*;

module axis_slave_to_sb_cfg #(
    parameter int CFG_W       = 32,          // Sideband config chunk width (fixed 32)
    parameter int TDATA_W     = CFG_W,       // AXIS data width (must equal CFG_W)
    parameter int TKEEP_W     = TDATA_W/8,
    parameter int DN_CRD_INIT = 32           // downstream credits (0 = gating off)
)(
    input  logic                 clk,        // Sideband config clock (clk_sb)
    input  logic                 rst_n,

    // ---- AXI4-Stream slave (from DMA MM2S / stream FIFO) ----
    input  logic [TDATA_W-1:0]   s_axis_tdata,
    input  logic [TKEEP_W-1:0]   s_axis_tkeep,   // accepted, unused
    input  logic                 s_axis_tlast,   // accepted, unused (opcode frames)
    input  logic                 s_axis_tvalid,
    output logic                 s_axis_tready,

    // ---- Sideband config DOWNSTREAM face (-> PHY lp_cfg) ----
    output logic [CFG_W-1:0]     lp_cfg,
    output logic                 lp_cfg_vld,
    input  logic                 pl_cfg_crd      // downstream credit return (PHY->us)
);

    // Compile-time guard: this bridge does no width conversion.
    initial begin
        if (TDATA_W != CFG_W)
            $error("axis_slave_to_sb_cfg: TDATA_W (%0d) must equal CFG_W (%0d)",
                   TDATA_W, CFG_W);
    end

    // Unused inputs (kept on the port list for DMA/AXIS compatibility).
    wire _unused_ok = &{1'b0, s_axis_tkeep, s_axis_tlast};

    // -------------------------------------------------------------------------
    // Chunk-count decode from the chunk0 opcode (identical to rdi_aggregator).
    // -------------------------------------------------------------------------
    function automatic logic [2:0] msg_chunks(input logic [CFG_W-1:0] chunk0);
        sb_opcode_e op;
        op = sb_opcode_e'(chunk0[4:0]);
        case (op)
            SB_32_MEM_READ,
            SB_32_DMS_REG_READ,
            SB_32_CFG_READ,
            SB_64_MEM_READ,
            SB_64_DMS_REG_READ,
            SB_64_CFG_READ,
            SB_COMPLETION_WITHOUT_DATA,
            SB_MSG_WITHOUT_DATA,
            SB_MNGT_PORT_MSG_WITHOUT_DATA           : msg_chunks = 3'd2;
            SB_32_MEM_WRITE,
            SB_32_DMS_REG_WRITE,
            SB_32_CFG_WRITE,
            SB_COMPLETION_WITH_32_DATA              : msg_chunks = 3'd3;
            SB_64_MEM_WRITE,
            SB_64_DMS_REG_WRITE,
            SB_64_CFG_WRITE,
            SB_COMPLETION_WITH_64_DATA,
            SB_MSG_WITH_64_DATA                   : msg_chunks = 3'd4;
            default                                 : msg_chunks = 3'd2;
        endcase
    endfunction

    function automatic logic is_completion(input logic [CFG_W-1:0] chunk0);
        sb_opcode_e op;
        op = sb_opcode_e'(chunk0[4:0]);
        is_completion = (op == SB_COMPLETION_WITHOUT_DATA) ||
                        (op == SB_COMPLETION_WITH_32_DATA) ||
                        (op == SB_COMPLETION_WITH_64_DATA);
    endfunction

    // -------------------------------------------------------------------------
    // Downstream credit counter
    // -------------------------------------------------------------------------
    localparam bit USE_CRD = (DN_CRD_INIT != 0);
    localparam int CRD_W   = (DN_CRD_INIT <= 1) ? 1 : $clog2(DN_CRD_INIT+1);

    logic [CRD_W-1:0] credit;
    logic             req_commit;            // a REQUEST message is launched this cycle

    wire crd_ok = (!USE_CRD) || (credit != '0);

    // -------------------------------------------------------------------------
    // Message tracking
    // -------------------------------------------------------------------------
    logic       in_msg;
    logic [2:0] chunk_cnt;                   // chunks accepted so far in this message
    logic [2:0] expected;                    // total chunks of the current message

    // chunk0 (message-start) decode of the head-of-stream beat
    wire [2:0] exp0     = msg_chunks(s_axis_tdata);
    wire       is_comp0 = is_completion(s_axis_tdata);

    // Start grant: at a boundary, requests need a credit; completions are free.
    wire start_ok = in_msg ? 1'b1 : (is_comp0 ? 1'b1 : crd_ok);

    assign s_axis_tready = start_ok;
    wire   beat          = s_axis_tvalid && s_axis_tready;

    // Drive the PHY: each accepted beat is one config chunk.
    assign lp_cfg     = s_axis_tdata;
    assign lp_cfg_vld = beat;

    // Spend exactly one credit when a REQUEST message's first chunk is accepted.
    assign req_commit = beat && !in_msg && !is_comp0;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            in_msg    <= 1'b0;
            chunk_cnt <= '0;
            expected  <= '0;
        end else if (beat) begin
            if (!in_msg) begin
                // first chunk of a new message (always >= 2 chunks, never last)
                expected  <= exp0;
                chunk_cnt <= 3'd1;
                in_msg    <= 1'b1;
            end else begin
                if (chunk_cnt == expected - 3'd1) begin
                    in_msg    <= 1'b0;       // last chunk accepted
                    chunk_cnt <= '0;
                end else begin
                    chunk_cnt <= chunk_cnt + 3'd1;
                end
            end
        end
    end

    generate
    if (USE_CRD) begin : g_crd
        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n)
                credit <= CRD_W'(DN_CRD_INIT);
            else begin
                case ({pl_cfg_crd, req_commit})
                    2'b10  : credit <= (credit == '1) ? credit : credit + 1'b1;
                    2'b01  : credit <= (credit == '0) ? credit : credit - 1'b1;
                    default: credit <= credit;        // 2'b11 net zero / 2'b00 hold
                endcase
            end
        end
    end else begin : g_no_crd
        assign credit = '0;
    end
    endgenerate

endmodule
