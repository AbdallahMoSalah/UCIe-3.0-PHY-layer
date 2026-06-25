`timescale 1ns/1ps
// =============================================================================
// Module  : axis_master_from_sb_cfg
// Project : UCIe 3.0 PHY - FPGA bring-up
//
// Purpose : AXI4-Stream MASTER (source) driven by the Sideband RDI config
//           UPSTREAM face (PHY -> adapter): pl_cfg / pl_cfg_vld.
//           Received config chunks are streamed out to a DMA's S2MM channel
//           (or an AXIS-stream FIFO the CPU drains); each AXIS beat == one chunk.
//
// Wire format (matches rdi_de_aggregator chunk order):
//     chunk0 = header[31:0]   (opcode in [4:0])
//     chunk1 = header[63:32]
//     chunk2 = payload[31:0]                       -- 3- and 4-chunk messages
//     chunk3 = payload[63:32]                      -- 4-chunk messages
//   Message length (2/3/4 chunks) is decoded from the chunk0 opcode, identical
//   to rdi_de_aggregator, and used to assert TLAST on the last chunk so each
//   SB config message is a self-contained AXIS packet.
//
//   pl_cfg has NO ready: the de-aggregator drives a chunk per pl_cfg_vld cycle
//   and CANNOT be back-pressured by the adapter.  So incoming chunks are buffered
//   in a small synchronous FIFO and drained onto AXIS at the DMA's pace.
//   o_overflow is a STICKY flag: it sets if a chunk arrives while the FIFO is
//   full (a chunk was dropped -> silent loss; surface it to SW / an LED).
//
// ---- Credit loop (upstream) --------------------------------------------------
//   The PHY's credit_counter (RDI_control) gates UPSTREAM REQUEST forwarding:
//     - starts at CRD_INIT (32),
//     - crd_out (-1) per request forwarded to us (ufifo_req_rinc),
//     - crd_in  (+1) on our lp_cfg_crd  (the adapter credit grant).
//   Completions are HIGH-PRIORITY and credit-free (the adapter must always
//   accept them), so they are NOT credited.
//
//   This bridge returns exactly one lp_cfg_crd pulse per REQUEST message, and
//   returns it on DRAIN (when the request's last chunk is popped to AXIS), so
//   the credit loop throttles the PHY's request forwarding to the actual AXIS/
//   DMA drain rate -- genuine end-to-end back-pressure for the credited class.
//   (Completions can still burst; the FIFO + o_overflow are their backstop.)
//
//   Size FIFO_DEPTH for the worst-case in-flight burst; >= a few messages.
// =============================================================================

import sb_pkg::*;

module axis_master_from_sb_cfg #(
    parameter int CFG_W       = 32,          // Sideband config chunk width (fixed 32)
    parameter int TDATA_W     = CFG_W,       // AXIS data width (must equal CFG_W)
    parameter int TKEEP_W     = TDATA_W/8,
    parameter int FIFO_DEPTH  = 16           // absorbs upstream bursts
)(
    input  logic                 clk,        // Sideband config clock (clk_sb)
    input  logic                 rst_n,

    // ---- Sideband config UPSTREAM face (<- PHY pl_cfg) ----
    input  logic [CFG_W-1:0]     pl_cfg,
    input  logic                 pl_cfg_vld,
    output logic                 lp_cfg_crd,     // upstream credit grant (us->PHY)

    // ---- AXI4-Stream master (to DMA S2MM / stream FIFO) ----
    output logic [TDATA_W-1:0]   m_axis_tdata,
    output logic [TKEEP_W-1:0]   m_axis_tkeep,
    output logic                 m_axis_tlast,
    output logic                 m_axis_tvalid,
    input  logic                 m_axis_tready,

    // ---- Status ----
    output logic                 o_overflow      // sticky: a chunk was dropped
);

    localparam int AW = (FIFO_DEPTH <= 1) ? 1 : $clog2(FIFO_DEPTH);

    // Compile-time guard: this bridge does no width conversion.
    initial begin
        if (TDATA_W != CFG_W)
            $error("axis_master_from_sb_cfg: TDATA_W (%0d) must equal CFG_W (%0d)",
                   TDATA_W, CFG_W);
    end

    // -------------------------------------------------------------------------
    // Chunk-count / completion decode from the chunk0 opcode
    // (identical to rdi_de_aggregator).
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
            SB_COMPLETION_WITH_64_DATA, SB_MSG_WITH_64_DATA : msg_chunks = 3'd4;
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
    // Incoming message framing: tag each chunk with last-of-message + is_request
    // -------------------------------------------------------------------------
    logic       in_msg;
    logic [2:0] chunk_cnt;                    // chunks seen so far in this message
    logic [2:0] expected;                     // total chunks of the current message
    logic       msg_is_req;                   // latched at chunk0: 1 = request

    wire [2:0] exp0     = msg_chunks(pl_cfg);
    wire       is_comp0 = is_completion(pl_cfg);

    // Per-chunk framing computed for the chunk currently on pl_cfg:
    wire       cur_first = !in_msg;
    wire [2:0] cur_exp   = cur_first ? exp0       : expected;
    wire       cur_req   = cur_first ? !is_comp0  : msg_is_req;
    wire [2:0] cur_idx   = cur_first ? 3'd0       : chunk_cnt;
    wire       cur_last  = (cur_idx == cur_exp - 3'd1);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            in_msg     <= 1'b0;
            chunk_cnt  <= '0;
            expected   <= '0;
            msg_is_req <= 1'b0;
        end else if (pl_cfg_vld) begin
            if (!in_msg) begin
                expected   <= exp0;
                msg_is_req <= !is_comp0;
                chunk_cnt  <= 3'd1;
                in_msg     <= (exp0 != 3'd1);    // exp0 >= 2 always -> enter message
            end else begin
                if (chunk_cnt == expected - 3'd1) begin
                    in_msg    <= 1'b0;           // last chunk of the message
                    chunk_cnt <= '0;
                end else begin
                    chunk_cnt <= chunk_cnt + 3'd1;
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Synchronous FIFO.  Entry = {is_req, last, data}.
    // -------------------------------------------------------------------------
    localparam int EW = CFG_W + 2;            // +last +is_req
    logic [EW-1:0]  mem [0:FIFO_DEPTH-1];
    logic [AW-1:0]  wr_ptr, rd_ptr;
    logic [AW:0]    count;

    wire full  = (count == FIFO_DEPTH);
    wire empty = (count == 0);

    wire do_push = pl_cfg_vld && !full;
    wire do_pop  = m_axis_tvalid && m_axis_tready;

    wire [EW-1:0] push_entry = {cur_req, cur_last, pl_cfg};

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr     <= '0;
            rd_ptr     <= '0;
            count      <= '0;
            o_overflow <= 1'b0;
        end else begin
            if (do_push) begin
                mem[wr_ptr] <= push_entry;
                wr_ptr      <= wr_ptr + 1'b1;
            end
            if (do_pop) begin
                rd_ptr <= rd_ptr + 1'b1;
            end

            case ({do_push, do_pop})
                2'b10:   count <= count + 1'b1;
                2'b01:   count <= count - 1'b1;
                default: count <= count;       // 00 or 11: no net change
            endcase

            if (pl_cfg_vld && full)
                o_overflow <= 1'b1;            // sticky: a chunk was dropped
        end
    end

    // -------------------------------------------------------------------------
    // AXIS master outputs (drain side)
    // -------------------------------------------------------------------------
    wire [EW-1:0] rd_entry = mem[rd_ptr];

    assign m_axis_tvalid = !empty;
    assign m_axis_tdata  = rd_entry[CFG_W-1:0];
    assign m_axis_tlast  = rd_entry[CFG_W];          // last-of-message bit
    assign m_axis_tkeep  = {TKEEP_W{1'b1}};

    // Return one upstream credit per REQUEST message, on drain of its last chunk.
    assign lp_cfg_crd = do_pop && rd_entry[CFG_W] && rd_entry[CFG_W+1];

endmodule
