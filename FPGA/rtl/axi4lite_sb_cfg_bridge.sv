`timescale 1ns/1ps
// =============================================================================
// Module  : axi4lite_sb_cfg_bridge
// Project : UCIe 3.0 PHY - FPGA bring-up (HW/SW co-design)
//
// Purpose : AXI4-Lite *slave* that lets a processor (Zynq PS / MicroBlaze)
//           read/write the UCIe Sideband register file through the adapter
//           config face (lp_cfg / pl_cfg) of the PHY.
//
//           A single AXI4-Lite access is turned into one Sideband config
//           packet and the matching completion is turned back into the AXI
//           response:
//
//             AXI WRITE  -> SB_32_CFG_WRITE  -> wait SB_COMPLETION_WITHOUT_DATA
//                                            -> BRESP  (OKAY / SLVERR)
//             AXI READ   -> SB_32_CFG_READ   -> wait SB_COMPLETION_WITH_32_DATA
//                                            -> RDATA + RRESP (OKAY / SLVERR)
//
//           The bridge emulates the *adapter (LP) side* of the config face:
//
//               m_lp_cfg / m_lp_cfg_vld   : request chunks  (bridge -> PHY)
//               m_pl_cfg_crd              : downstream credit return (PHY -> bridge)
//               m_pl_cfg / m_pl_cfg_vld   : completion chunks (PHY -> bridge)
//               m_lp_cfg_crd              : upstream  credit grant  (bridge -> PHY)
//
// Packet wire format (matches rdi_aggregator / rdi_de_aggregator chunk order):
//               word0 = header[31:0]   (opcode in [4:0])
//               word1 = header[63:32]  (addr in [23:0], cpl status in [2:0])
//               word2 = payload[31:0]  (write data / read-completion data)
//
// IMPORTANT - NOT INTEGRATED ON PURPOSE
//   * This file only *defines* the bridge. It is not wired into the FPGA
//     loopback wrapper yet.
//   * The config face (lp_cfg/pl_cfg) runs on the Sideband clock (clk_sb).
//     This bridge is single-clock: s_axi_aclk MUST be the same clock that
//     drives lp_cfg/pl_cfg. If the AXI clock differs, put an async-FIFO /
//     CDC on the m_* port set during integration.
//   * Single outstanding transaction (one config access in flight). That is
//     the natural model for register config and keeps completion matching
//     trivial (no tag tracking needed).
//   * cr/cp/dp parity bits in the header are left 0. If the Sideband checks
//     sideband parity, add a parity generator here during integration.
// =============================================================================

import sb_pkg::*;

module axi4lite_sb_cfg_bridge #(
    parameter int          AXI_ADDR_W   = 32,    // AXI byte-address width (>= 25)
    // Register-access opcodes. The Sideband reg file sees a 25-bit address
    // rf_addr[24:0]; bit[24] (the "space" select) is NOT carried in the packet
    // header (header addr is 24-bit) — Reg_DePacketizer reconstructs it from the
    // opcode: space=0 -> CFG_* , space=1 -> MEM_*. So the opcode is picked from
    // {AXI addr[24], is_write} = 4 possibilities:
    parameter sb_opcode_e  OPC_CFG_RD   = SB_32_CFG_READ,   // addr[24]=0, read
    parameter sb_opcode_e  OPC_CFG_WR   = SB_32_CFG_WRITE,  // addr[24]=0, write
    parameter sb_opcode_e  OPC_MEM_RD   = SB_32_MEM_READ,   // addr[24]=1, read
    parameter sb_opcode_e  OPC_MEM_WR   = SB_32_MEM_WRITE,  // addr[24]=1, write
    parameter sb_srcid_e   SRCID        = ADAPTER,      // who we pretend to be
    parameter sb_dstid_e   DSTID        = LOCAL_PHY,    // where the reg file lives
    // Downstream request credits. 0 => credit gating disabled (always allowed),
    // handy for early bring-up. Otherwise must be <= sideband downstream req FIFO.
    parameter int          DN_CRD_INIT  = 4,
    // Cycles to wait for a completion before returning SLVERR (avoids hanging
    // the AXI bus if the far end never answers).
    parameter int          TIMEOUT_CYCLES = 4096
)(
    // ---- AXI4-Lite slave (config domain == clk_sb) ----
    input  logic                    s_axi_aclk,
    input  logic                    s_axi_aresetn,

    input  logic [AXI_ADDR_W-1:0]   s_axi_awaddr,
    input  logic [2:0]              s_axi_awprot,
    input  logic                    s_axi_awvalid,
    output logic                    s_axi_awready,

    input  logic [31:0]             s_axi_wdata,
    input  logic [3:0]              s_axi_wstrb,
    input  logic                    s_axi_wvalid,
    output logic                    s_axi_wready,

    output logic [1:0]              s_axi_bresp,
    output logic                    s_axi_bvalid,
    input  logic                    s_axi_bready,

    input  logic [AXI_ADDR_W-1:0]   s_axi_araddr,
    input  logic [2:0]              s_axi_arprot,
    input  logic                    s_axi_arvalid,
    output logic                    s_axi_arready,

    output logic [31:0]             s_axi_rdata,
    output logic [1:0]              s_axi_rresp,
    output logic                    s_axi_rvalid,
    input  logic                    s_axi_rready,

    // ---- Sideband adapter config face (PHY side) ----
    output logic [31:0]             m_lp_cfg,      // request chunk out
    output logic                    m_lp_cfg_vld,
    input  logic                    m_pl_cfg_crd,  // downstream credit return
    output logic                    m_lp_cfg_crd,  // upstream  credit grant
    input  logic [31:0]             m_pl_cfg,      // completion chunk in
    input  logic                    m_pl_cfg_vld
);

    // ---- AXI response encodings ----
    localparam logic [1:0] RESP_OKAY   = 2'b00;
    localparam logic [1:0] RESP_SLVERR = 2'b10;

    localparam int TO_W = (TIMEOUT_CYCLES <= 1) ? 1 : $clog2(TIMEOUT_CYCLES+1);

    // ---- FSM ----
    typedef enum logic [2:0] {
        ST_IDLE,   // accept AW/W or AR
        ST_REQ,    // stream request chunks onto lp_cfg
        ST_WAIT,   // collect completion chunks from pl_cfg
        ST_RESP    // drive B or R channel
    } state_e;

    state_e        state;
    logic          is_write;
    logic [AXI_ADDR_W-1:0] addr_q;
    logic [31:0]   wdata_q;
    logic [3:0]    wstrb_q;
    logic [4:0]    tag_q;

    logic [1:0]    req_cnt;     // request chunk index
    logic [1:0]    req_len;     // 2 (read) or 3 (write)

    logic [1:0]    cpl_cnt;     // completion chunk index
    logic [1:0]    cpl_len;     // 2 (no data) or 3 (with 32 data)
    logic [31:0]   cpl_w0, cpl_w1, cpl_w2;

    logic [1:0]    resp_q;
    logic [31:0]   rdata_q;
    logic [TO_W-1:0] to_cnt;

    // -------------------------------------------------------------------------
    // Downstream request credit counter (per request packet).
    //   crd_in  = m_pl_cfg_crd ; crd_out = packet sent (req_commit)
    // -------------------------------------------------------------------------
    localparam bit USE_DN_CRD = (DN_CRD_INIT != 0);
    localparam int DN_CRD_W   = (DN_CRD_INIT <= 1) ? 1 : $clog2(DN_CRD_INIT+1);
    logic [DN_CRD_W-1:0] dn_credit;
    logic                req_commit;       // last request chunk leaves this cycle
    logic                req_grant;        // allowed to start sending a packet

    assign req_grant = (!USE_DN_CRD) || (dn_credit != '0);

    generate
    if (USE_DN_CRD) begin : g_dn_crd
        always_ff @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
            if (!s_axi_aresetn)
                dn_credit <= DN_CRD_W'(DN_CRD_INIT);
            else begin
                case ({m_pl_cfg_crd, req_commit})
                    2'b10  : dn_credit <= (dn_credit == '1) ? dn_credit : dn_credit + 1'b1;
                    2'b01  : dn_credit <= (dn_credit == '0) ? dn_credit : dn_credit - 1'b1;
                    default: dn_credit <= dn_credit; // 2'b11 net zero / 2'b00 hold
                endcase
            end
        end
    end else begin : g_no_dn_crd
        assign dn_credit = '0;
    end
    endgenerate

    // -------------------------------------------------------------------------
    // Request header build (combinational from latched address/data)
    // -------------------------------------------------------------------------
    // opcode select from {space, is_write}; space = AXI address bit [24]
    logic       space_sel;
    sb_opcode_e req_opcode;
    assign space_sel = addr_q[24];              // 0 = CFG space, 1 = MEM space

    always_comb begin
        unique case ({space_sel, is_write})
            2'b00:   req_opcode = OPC_CFG_RD;
            2'b01:   req_opcode = OPC_CFG_WR;
            2'b10:   req_opcode = OPC_MEM_RD;
            default: req_opcode = OPC_MEM_WR;   // 2'b11
        endcase
    end

    sb_req_header_t req_hdr;
    logic [63:0]    req_hdr_raw;

    always_comb begin
        req_hdr        = '0;
        req_hdr.opcode = req_opcode;
        req_hdr.ep     = 1'b0;
        req_hdr.be     = is_write ? {4'b0000, wstrb_q} : 8'h0F;
        req_hdr.tag    = tag_q;
        req_hdr.srcid  = SRCID;
        req_hdr.addr   = addr_q[23:0];          // 24-bit header addr (rf_addr[23:0])
        req_hdr.dstid  = DSTID;
        // rf_addr[24] (space) is conveyed by the opcode, not the addr field.
        // cr/cp/dp parity bits left 0 (see header note)
    end
    assign req_hdr_raw = req_hdr;

    always_comb begin
        unique case (req_cnt)
            2'd0:    m_lp_cfg = req_hdr_raw[31:0];
            2'd1:    m_lp_cfg = req_hdr_raw[63:32];
            default: m_lp_cfg = wdata_q;        // word2 = payload (write only)
        endcase
    end
    assign m_lp_cfg_vld = (state == ST_REQ) && req_grant;
    assign req_commit   = (state == ST_REQ) && req_grant && (req_cnt == req_len - 2'd1);

    // Return one upstream credit per completion chunk we accept.
    assign m_lp_cfg_crd = (state == ST_WAIT) && m_pl_cfg_vld;

    // -------------------------------------------------------------------------
    // Completion decode helpers
    //   cpl_opcode  : opcode field, valid on the first completion chunk (word0)
    //   cpl_eff_len : chunk count (2 = no-data, 3 = with-32-data); decoded from
    //                 the first chunk, then taken from the locked cpl_len
    //   cpl_status  : completion status (header word1 [2:0]) at the final chunk
    // -------------------------------------------------------------------------
    sb_opcode_e  cpl_opcode;
    logic [1:0]  cpl_eff_len;
    logic [2:0]  cpl_status;

    assign cpl_opcode  = sb_opcode_e'(m_pl_cfg[4:0]);
    assign cpl_eff_len = (cpl_cnt == 2'd0)
                         ? ((cpl_opcode == SB_COMPLETION_WITH_32_DATA) ? 2'd3 : 2'd2)
                         : cpl_len;
    // with-data: status was stored in cpl_w1; no-data: status is the current word1 chunk
    assign cpl_status  = (cpl_eff_len == 2'd3) ? cpl_w1[2:0] : m_pl_cfg[2:0];

    // -------------------------------------------------------------------------
    // AXI handshake outputs
    // -------------------------------------------------------------------------
    logic accept_wr, accept_rd;
    assign accept_wr = (state == ST_IDLE) && s_axi_awvalid && s_axi_wvalid;
    assign accept_rd = (state == ST_IDLE) && s_axi_arvalid && !(s_axi_awvalid && s_axi_wvalid);

    assign s_axi_awready = accept_wr;
    assign s_axi_wready  = accept_wr;
    assign s_axi_arready = accept_rd;

    assign s_axi_bvalid  = (state == ST_RESP) &&  is_write;
    assign s_axi_bresp   = resp_q;
    assign s_axi_rvalid  = (state == ST_RESP) && !is_write;
    assign s_axi_rdata   = rdata_q;
    assign s_axi_rresp   = resp_q;

    // -------------------------------------------------------------------------
    // Main FSM
    // -------------------------------------------------------------------------
    always_ff @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            state    <= ST_IDLE;
            is_write <= 1'b0;
            addr_q   <= '0;
            wdata_q  <= '0;
            wstrb_q  <= '0;
            tag_q    <= '0;
            req_cnt  <= '0;
            req_len  <= '0;
            cpl_cnt  <= '0;
            cpl_len  <= '0;
            cpl_w0   <= '0;
            cpl_w1   <= '0;
            cpl_w2   <= '0;
            resp_q   <= RESP_OKAY;
            rdata_q  <= '0;
            to_cnt   <= '0;
        end else begin
            case (state)

            // -----------------------------------------------------------------
            ST_IDLE: begin
                to_cnt  <= '0;
                req_cnt <= '0;
                cpl_cnt <= '0;
                if (accept_wr) begin
                    is_write <= 1'b1;
                    addr_q   <= s_axi_awaddr;
                    wdata_q  <= s_axi_wdata;
                    wstrb_q  <= s_axi_wstrb;
                    req_len  <= 2'd3;          // header(2) + data(1)
                    state    <= ST_REQ;
                end else if (accept_rd) begin
                    is_write <= 1'b0;
                    addr_q   <= s_axi_araddr;
                    req_len  <= 2'd2;          // header only
                    state    <= ST_REQ;
                end
            end

            // -----------------------------------------------------------------
            ST_REQ: begin
                if (req_grant) begin           // a chunk is being driven this cycle
                    if (req_cnt == req_len - 2'd1) begin
                        req_cnt <= '0;
                        cpl_cnt <= '0;
                        to_cnt  <= '0;
                        state   <= ST_WAIT;
                    end else begin
                        req_cnt <= req_cnt + 2'd1;
                    end
                end
            end

            // -----------------------------------------------------------------
            ST_WAIT: begin
                to_cnt <= to_cnt + 1'b1;
                if (m_pl_cfg_vld) begin
                    // store this chunk and advance
                    case (cpl_cnt)
                        2'd0:    cpl_w0 <= m_pl_cfg;
                        2'd1:    cpl_w1 <= m_pl_cfg;   // completion header word1: status in [2:0]
                        default: cpl_w2 <= m_pl_cfg;   // read data
                    endcase
                    cpl_cnt <= cpl_cnt + 2'd1;
                    if (cpl_cnt == 2'd0)
                        cpl_len <= cpl_eff_len;        // lock length from first chunk's opcode

                    // is this the final chunk of the completion?
                    if (cpl_cnt == cpl_eff_len - 2'd1) begin
                        // no-data cpl: status is in this (word1) chunk
                        // with-data cpl: status is in already-stored cpl_w1, data is this chunk
                        resp_q  <= (cpl_status == 3'b000) ? RESP_OKAY : RESP_SLVERR;
                        rdata_q <= (cpl_eff_len == 2'd3) ? m_pl_cfg : 32'h0;
                        tag_q   <= tag_q + 5'd1;
                        state   <= ST_RESP;
                    end
                end else if (to_cnt >= TO_W'(TIMEOUT_CYCLES)) begin
                    // far end never answered -> don't hang the AXI bus
                    resp_q  <= RESP_SLVERR;
                    rdata_q <= 32'hDEAD_DEAD;
                    tag_q   <= tag_q + 5'd1;
                    state   <= ST_RESP;
                end
            end

            // -----------------------------------------------------------------
            ST_RESP: begin
                if ( is_write && s_axi_bready) state <= ST_IDLE;
                if (!is_write && s_axi_rready) state <= ST_IDLE;
            end

            default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
