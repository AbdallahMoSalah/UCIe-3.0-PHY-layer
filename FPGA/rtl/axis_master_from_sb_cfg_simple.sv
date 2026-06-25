`timescale 1ns/1ps
// =============================================================================
// Module  : axis_master_from_sb_cfg_simple
// Project : UCIe 3.0 PHY - FPGA bring-up
//
// Purpose : A simplified AXI4-Stream Master bridge for Sideband RX.
//           Instead of decoding opcodes to find the packet length, it uses a
//           simple chunk counter that assumes a fixed packet length (default 4).
// =============================================================================

module axis_master_from_sb_cfg_simple #(
    parameter int TDATA_W     = 32,
    parameter int TKEEP_W     = TDATA_W/8,
    parameter int PACKET_LEN  = 4,           // fixed packet size in chunks
    parameter int FIFO_DEPTH  = 16           // FIFO buffer depth
)(
    input  logic                 clk,
    input  logic                 rst_n,

    // ---- Sideband config UPSTREAM face (<- PHY pl_cfg) ----
    input  logic [TDATA_W-1:0]   pl_cfg,
    input  logic                 pl_cfg_vld,
    output logic                 lp_cfg_crd,     // credit grant (us->PHY)

    // ---- AXI4-Stream master ----
    output logic [TDATA_W-1:0]   m_axis_tdata,
    output logic [TKEEP_W-1:0]   m_axis_tkeep,
    output logic                 m_axis_tlast,
    output logic                 m_axis_tvalid,
    input  logic                 m_axis_tready,

    // ---- Status ----
    output logic                 o_overflow      // sticky overflow
);

    localparam int AW    = (FIFO_DEPTH <= 1) ? 1 : $clog2(FIFO_DEPTH);
    localparam int CNT_W = $clog2(PACKET_LEN);

    // Track chunk index on the input (push) side
    logic [CNT_W-1:0] push_cnt;
    wire cur_last = (push_cnt == CNT_W'(PACKET_LEN - 1));

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            push_cnt <= '0;
        end else if (pl_cfg_vld) begin
            if (cur_last) begin
                push_cnt <= '0;
            end else begin
                push_cnt <= push_cnt + 1'b1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Synchronous FIFO. Entry = {last, data}
    // -------------------------------------------------------------------------
    localparam int EW = TDATA_W + 1; // data + last
    logic [EW-1:0] mem [0:FIFO_DEPTH-1];
    logic [AW-1:0] wr_ptr, rd_ptr;
    logic [AW:0]   count;

    wire full  = (count == FIFO_DEPTH);
    wire empty = (count == 0);

    wire do_push = pl_cfg_vld && !full;
    wire do_pop  = m_axis_tvalid && m_axis_tready;

    wire [EW-1:0] push_entry = {cur_last, pl_cfg};

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
                default: count <= count; // 00 or 11
            endcase

            if (pl_cfg_vld && full) begin
                o_overflow <= 1'b1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // AXI-Stream master outputs
    // -------------------------------------------------------------------------
    wire [EW-1:0] rd_entry = mem[rd_ptr];

    assign m_axis_tvalid = !empty;
    assign m_axis_tdata  = rd_entry[TDATA_W-1:0];
    assign m_axis_tlast  = rd_entry[TDATA_W];
    assign m_axis_tkeep  = {TKEEP_W{1'b1}};

    // Return one upstream credit per packet completed (on drain of the last chunk)
    assign lp_cfg_crd = do_pop && rd_entry[TDATA_W];

endmodule
