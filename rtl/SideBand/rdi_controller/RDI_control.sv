// =============================================================================
//  RDI_Control  (Full Integration)
//  UCIe Sideband RDI Controller
//
//  Architecture: SB_RDI_control_arch.png
//
//  ─── Interfaces ─────────────────────────────────────────────────────────────
//
//    ADAPTER  side  : 32-bit RDI chunks  (lp_cfg / pl_cfg)
//    LINK CTL side  : 128-bit SB packets (Adapter_msg_rcvd / Adapter_msg_send)
//    REG_ACCESS     : 128-bit SB packets (reg_msg / completion_msg)
//    RDI_SM         : traffic_req / traffic_ready / phy_in_reset
//
//  ─── Downstream path (Adapter ─→ Link / Reg_Access) ────────────────────────
//
//    lp_cfg / lp_cfg_vld  (32-bit chunks, NC+1 wide on adapter side)
//         │
//    rdi_aggregator           reassembles chunks → 128-bit lp_msg
//         │
//    sb_downstream_demux      routes by dstid / opcode / phy_in_reset
//        ├──→ reg_msg / reg_vld      ────────────→ Reg_Access (local)
//        └──→ RDI_ctrl_down_comp_FIFO  (hp)  ─┐
//             RDI_ctrl_down_req_FIFO   (lp)  ─┤
//                                             ↓
//                         sb_priority_arbiter #1  (downstream FIFO arbiter)
//                                             │
//                         sb_priority_arbiter #2  (Router)
//                             hp ─ FIFO arbiter output  ─────────────────────┐
//                             lp ─ completion_msg from Reg_Access             │
//                                             │                               │
//                         Adapter_msg_send / Adapter_vld_send ──→ Link_Ctrl  │
//                                                                             │
//    pl_cfg_crd ←── dfifo_req_rinc  (credit returned when req sent to link) ─┘
//
//  ─── Upstream path (Link / Reg_Access ─→ Adapter) ──────────────────────────
//
//    Adapter_msg_rcvd / Adapter_vld_rcvd  (128-bit from Link Controller)
//         │
//    sb_fifo_demux                split req vs completion
//        ├──→ RDI_ctrl_up_req_FIFO   (lp)
//        └──→ RDI_ctrl_up_comp_FIFO  (hp)
//                    │                  │
//             sb_priority_arbiter #3  (upstream, hp=comp, lp=req gated by no_crd)
//              ← no_crd from credit_counter ← lp_cfg_crd (adapter credit grant)
//              ← crd_out = ufifo_req_rinc (upstream req consumed = credit used)
//                    │
//    rdi_de_aggregator            breaks 128-bit → 32-bit pl_cfg chunks
//         │
//    pl_cfg / pl_cfg_vld  ────────────────────────────────→ Adapter
//
// =============================================================================

module RDI_control
    import sb_pkg::*;
(
    input  logic         clk,
    input  logic         rst_n,

    // =========================================================================
    //  Adapter interface  (32-bit RDI chunks)
    // =========================================================================
    input  logic [31:0]  lp_cfg,         // Downstream: adapter → RDI_Control (32-bit config chunk)
    input  logic         lp_cfg_vld,

    output logic         pl_cfg_crd,     // Credit return: downstream req FIFO consumed → adapter notified
    input  logic         lp_cfg_crd,     // Credit grant:  adapter consumed one pl_cfg chunk

    output logic [31:0]  pl_cfg,         // Upstream: RDI_Control → adapter (32-bit config chunk)
    output logic         pl_cfg_vld,

    // =========================================================================
    //  Link Controller interface  (128-bit assembled SB packets)
    // =========================================================================
    input  logic [127:0] Adapter_msg_rcvd,   // Upstream:   Link → RDI_Control
    input  logic         Adapter_vld_rcvd,

    output logic [127:0] Adapter_msg_send,   // Downstream: RDI_Control → Link
    output logic         Adapter_vld_send,
    input  logic         Adapter_ready,      // Back-pressure from Link Controller

    // =========================================================================
    //  Reg_Access interface  (128-bit SB packets)
    // =========================================================================
    output logic [127:0] reg_msg,            // Request  → Reg_Access
    output logic         reg_vld,
    input  logic         reg_ready,

    input  logic [127:0] completion_msg,     // Completion ← Reg_Access
    input  logic         completion_vld,
    output logic         completion_ready,

    // =========================================================================
    //  RDI_SM interface
    // =========================================================================
    output logic         traffic_req,        // Upstream traffic pending (to RDI_SM)
    input  logic         traffic_ready,      // SM grants upstream send window
    input  logic         phy_in_reset        // Link/Soft Reset → route all requests locally (UR)
);

// =============================================================================
//  Parameters
// =============================================================================
localparam int FIFO_DEPTH = 5;      // 2^5 = 32 entries per FIFO
localparam int CRD_W      = 5;      // credit counter width
localparam int CRD_INIT   = 32;     // initial credits at reset (matches 32-entry upstream req FIFO)

// =============================================================================
//  Internal wires
// =============================================================================

// ── rdi_aggregator output ───────────────────────────────────────────────────
logic [127:0] lp_msg;
logic         lp_msg_vld;

// ── rdi_comp_req_decoder output ───────────────────────────────────────────
logic comp_req_sel;   // 0 = request → down_req_FIFO,  1 = completion → down_comp_FIFO

// ── u_up_merge_arb output → rdi_comp_req_decoder + sb_demux ───────────────────
logic [127:0] merge_arb_msg;
logic         merge_arb_vld;

// ── rdi_comp_req_decoder output (upstream) ───────────────────────────────
logic up_comp_req_sel;   // 0 = req → up_req_FIFO,  1 = comp → up_comp_FIFO

// ── sb_demux output (upstream) ─────────────────────────────────────────
logic [127:0] up_req_data,  up_comp_data;
logic         up_req_vld,   up_comp_vld;

// ── Upstream req FIFO ────────────────────────────────────────────────────────────
logic [127:0] ufifo_req_rdata;
logic         ufifo_req_rvalid;
logic         ufifo_req_rinc;

// ── Upstream comp FIFO ─────────────────────────────────────────────────────────
logic [127:0] ufifo_comp_rdata;
logic         ufifo_comp_rvalid;
logic         ufifo_comp_rinc;

// ── credit_counter ───────────────────────────────────────────────────────────────
logic         no_crd;

// ── u_up_fifo_arb (arb #3) → rdi_de_aggregator ─────────────────────────────────
// Named to match rdi_de_aggregator port names directly
logic [127:0] pl_msg;
logic         pl_msg_vld;
logic         pl_msg_ready;

// ── sb_demux #2 output: comp vs req split ──────────────────────────────
logic [127:0] dmx_req_data;    // port 0 → down_req_FIFO
logic         dmx_req_vld;
logic [127:0] dmx_comp_data;   // port 1 → down_comp_FIFO
logic         dmx_comp_vld;

// ── Downstream req FIFO read side ────────────────────────────────────────────
logic [127:0] dfifo_req_rdata;
logic         dfifo_req_rvalid;
logic         dfifo_req_rinc;

// ── Downstream comp FIFO read side ───────────────────────────────────────────
logic [127:0] dfifo_comp_rdata;
logic         dfifo_comp_rvalid;
logic         dfifo_comp_rinc;

// ── sb_priority_arbiter #1 output (downstream FIFO arbiter) ──────────────────
logic [127:0] down_arb_msg;
logic         down_arb_vld;
logic         down_arb_ready;

// =============================================================================
//  ─── DOWNSTREAM PATH ────────────────────────────────────────────────────────
// =============================================================================

// ─── 1. rdi_aggregator ───────────────────────────────────────────────────────
// Reassembles 32-bit adapter chunks into a 128-bit SB packet.
rdi_aggregator u_aggregator (
    .clk        (clk),
    .rst_n      (rst_n),
    .lp_cfg     (lp_cfg),
    .lp_cfg_vld (lp_cfg_vld),
    .lp_msg     (lp_msg),
    .lp_msg_vld (lp_msg_vld)
);

// ─── 2a. rdi_comp_req_decoder ─────────────────────────────────────────────────
// Classifies remote traffic as completion or request based on opcode:
//   comp_req_sel = 0 → request    (opcode is not a completion)
//   comp_req_sel = 1 → completion (SB_COMPLETION_WITHOUT/WITH_32/WITH_64_DATA)
rdi_comp_req_decoder u_comp_req_decoder (
    .pkt (lp_msg),
    .sel (comp_req_sel)
);


// ─── 2b. sb_demux #1  —  req vs comp split ───────────────────────────────────
//   port 0 (comp_req_sel=0) → dmx_req_data   → RDI_ctrl_down_req_FIFO  (lp)
//   port 1 (comp_req_sel=1) → dmx_comp_data  → RDI_ctrl_down_comp_FIFO (hp)
sb_demux #(
    .DATA_WIDTH (128)
) u_downstream_split_demux (
    .data_in    (lp_msg),
    .vld_in     (lp_msg_vld),
    .sel        (comp_req_sel),
    .data_out_0 (dmx_req_data),
    .vld_out_0  (dmx_req_vld),
    .data_out_1 (dmx_comp_data),
    .vld_out_1  (dmx_comp_vld)
);

// ─── 3a. RDI_ctrl_down_req_FIFO ──────────────────────────────────────────────
fifo #(
    .DATA_WIDTH (128),
    .ADDR_WIDTH (FIFO_DEPTH),
    .ASYNC      (0)
) u_fifo_down_req (
    .W_CLK   (clk),   .WRST_N  (rst_n),
    .WINC    (dmx_req_vld),
    .WR_DATA (dmx_req_data),
    .WFULL   (),
    .WREADY  (),                       // not used; FIFO assumed never full by design

    .R_CLK   (clk),   .RRST_N  (rst_n),
    .RINC    (dfifo_req_rinc),
    .RD_DATA (dfifo_req_rdata),
    .REMPTY  (),
    .RVALID  (dfifo_req_rvalid)
);

// ─── 3b. RDI_ctrl_down_comp_FIFO ─────────────────────────────────────────────
fifo #(
    .DATA_WIDTH (128),
    .ADDR_WIDTH (FIFO_DEPTH),
    .ASYNC      (0)
) u_fifo_down_comp (
    .W_CLK   (clk),   .WRST_N  (rst_n),
    .WINC    (dmx_comp_vld),
    .WR_DATA (dmx_comp_data),
    .WFULL   (),
    .WREADY  (),                       // stubbed path; not used

    .R_CLK   (clk),   .RRST_N  (rst_n),
    .RINC    (dfifo_comp_rinc),
    .RD_DATA (dfifo_comp_rdata),
    .REMPTY  (),
    .RVALID  (dfifo_comp_rvalid)
);

// ─── 4. sb_priority_arbiter #1  (Downstream FIFO arbiter) ────────────────────
// hp = completion FIFO  (completions always take priority per UCIe ordering)
// lp = request    FIFO
// Output feeds sb_priority_arbiter #2 (the Router).
sb_priority_arbiter #(
    .DATA_WIDTH (128)
) u_down_arb (
    .hip_msg   (dfifo_comp_rdata),
    .hip_vld   (dfifo_comp_rvalid),
    .hip_ready (dfifo_comp_rinc),

    .lop_msg   (dfifo_req_rdata),
    .lop_vld   (dfifo_req_rvalid),
    .lop_ready (dfifo_req_rinc),

    .out_msg   (down_arb_msg),
    .out_vld   (down_arb_vld),
    .out_ready (down_arb_ready)
);

// Credit: one pl_cfg_crd pulse per downstream request sent to the Link Controller.
// This notifies the adapter that a slot in the downstream req FIFO was consumed.
assign pl_cfg_crd = dfifo_req_rinc;

// ─── 5. rdi_router  (downstream Router) ────────────────────────────────────
// Acts as the downstream Router: takes the single arbitrated output from
// u_down_arb and routes it based on reset flag and dstid:
//   reset || LOCAL_PHY  → reg_msg / reg_vld  → Reg_Access
//   otherwise           → Adapter_msg_send   → Link Controller
rdi_router u_rdi_router (
    .rst_n           (rst_n),
    .reset           (phy_in_reset),

    .rdi_msg         (down_arb_msg),
    .rdi_vld         (down_arb_vld),
    .rdi_ready       (down_arb_ready),   // backpressure → u_down_arb out_ready

    .reg_msg         (reg_msg),
    .reg_vld         (reg_vld),
    .reg_ready       (reg_ready),

    .Adapter_msg_send(Adapter_msg_send),
    .Adapter_vld_send(Adapter_vld_send),
    .Adapter_ready   (Adapter_ready)
);



// =============================================================================
//  ─── UPSTREAM PATH ───────────────────────────────────────────────────
// =============================================================================

// ─── 6. u_up_merge_arb  (arb #2)  ──────────────────────────────────────────────
// Arbitrates incoming Link traffic with local Reg_Access completions:
//   hp = Adapter_msg_rcvd  (Link Controller — always wins)
//   lp = completion_msg    (Reg_Access — fills gaps in link traffic)
// Merged output feeds the decoder + demux split.
// out_ready tied 1'b1: decoder is combinational, FIFOs never full by design.
sb_priority_arbiter #(
    .DATA_WIDTH (128)
) u_up_merge_arb (
    .hip_msg   (Adapter_msg_rcvd),
    .hip_vld   (Adapter_vld_rcvd),
    .hip_ready (),                       // Link Controller is free-running; unused

    .lop_msg   (completion_msg),
    .lop_vld   (completion_vld),
    .lop_ready (completion_ready),       // ← driven here; Reg_Access backpressure

    .out_msg   (merge_arb_msg),
    .out_vld   (merge_arb_vld),
    .out_ready (1'b1)                    // decoder + FIFOs always ready
);

// ─── 7a. rdi_comp_req_decoder  (upstream instance) ──────────────────────────────
// Classifies the merged packet by opcode:
//   up_comp_req_sel = 0 → request    → up_req_FIFO  (lp, credit-gated)
//   up_comp_req_sel = 1 → completion → up_comp_FIFO (hp)
rdi_comp_req_decoder u_up_comp_req_decoder (
    .pkt (merge_arb_msg),
    .sel (up_comp_req_sel)
);

// ─── 7b. sb_demux  (upstream instance) ───────────────────────────────────────────
// Routes merged packet to the correct upstream FIFO:
//   port 0 (up_comp_req_sel=0) → up_req_data/vld  → up_req_FIFO  (lp)
//   port 1 (up_comp_req_sel=1) → up_comp_data/vld → up_comp_FIFO (hp)
sb_demux #(
    .DATA_WIDTH (128)
) u_upstream_split_demux (
    .data_in    (merge_arb_msg),
    .vld_in     (merge_arb_vld),
    .sel        (up_comp_req_sel),
    .data_out_0 (up_req_data),
    .vld_out_0  (up_req_vld),
    .data_out_1 (up_comp_data),
    .vld_out_1  (up_comp_vld)
);

// ─── 8a. RDI_ctrl_up_req_FIFO ────────────────────────────────────────────────────
fifo #(
    .DATA_WIDTH (128),
    .ADDR_WIDTH (FIFO_DEPTH),
    .ASYNC      (0)
) u_fifo_up_req (
    .W_CLK   (clk),   .WRST_N  (rst_n),
    .WINC    (up_req_vld),
    .WR_DATA (up_req_data),
    .WFULL   (),
    .WREADY  (),

    .R_CLK   (clk),   .RRST_N  (rst_n),
    .RINC    (ufifo_req_rinc),
    .RD_DATA (ufifo_req_rdata),
    .REMPTY  (),
    .RVALID  (ufifo_req_rvalid)
);

// ─── 8b. RDI_ctrl_up_comp_FIFO ──────────────────────────────────────────────────
fifo #(
    .DATA_WIDTH (128),
    .ADDR_WIDTH (FIFO_DEPTH),
    .ASYNC      (0)
) u_fifo_up_comp (
    .W_CLK   (clk),   .WRST_N  (rst_n),
    .WINC    (up_comp_vld),
    .WR_DATA (up_comp_data),
    .WFULL   (),
    .WREADY  (),

    .R_CLK   (clk),   .RRST_N  (rst_n),
    .RINC    (ufifo_comp_rinc),
    .RD_DATA (ufifo_comp_rdata),
    .REMPTY  (),
    .RVALID  (ufifo_comp_rvalid)
);

// ─── 9. credit_counter ───────────────────────────────────────────────────────
// Tracks adapter credits for upstream request forwarding.
//   crd_in  : adapter returns credit after consuming one pl_cfg chunk
//   crd_out : one upstream req FIFO slot consumed by u_up_fifo_arb
//   no_crd  : gates lop_vld of u_up_fifo_arb only (completions are credit-free)
credit_counter #(
    .CRD_W    (CRD_W),
    .CRD_INIT (CRD_INIT)
) u_credit_counter (
    .clk     (clk),
    .rst_n   (rst_n),
    .crd_in  (lp_cfg_crd),
    .crd_out (ufifo_req_rinc),
    .no_crd  (no_crd)
);

// ─── 10. u_up_fifo_arb  (arb #3) ─────────────────────────────────────────────
// hp = up_comp_FIFO  (completions always win, credit-independent)
// lp = up_req_FIFO   (credit-gated via no_crd)
// Output wires named to match rdi_de_aggregator port names directly.
sb_priority_arbiter #(
    .DATA_WIDTH (128)
) u_up_fifo_arb (
    .hip_msg   (ufifo_comp_rdata),
    .hip_vld   (ufifo_comp_rvalid),
    .hip_ready (ufifo_comp_rinc),

    .lop_msg   (ufifo_req_rdata),
    .lop_vld   (ufifo_req_rvalid & ~no_crd),   // credit gate
    .lop_ready (ufifo_req_rinc),

    .out_msg   (pl_msg),
    .out_vld   (pl_msg_vld),
    .out_ready (pl_msg_ready)
);

// ─── 11. rdi_de_aggregator ───────────────────────────────────────────────────
// Breaks the 128-bit packet into 32-bit pl_cfg chunks for the adapter.
rdi_de_aggregator u_de_aggregator (
    .clk          (clk),
    .rst_n        (rst_n),
    .pl_msg       (sb_packet_t'(pl_msg)),
    .pl_msg_vld   (pl_msg_vld),
    .pl_msg_ready (pl_msg_ready),
    .traffic_req  (traffic_req),
    .traffic_ready(traffic_ready),
    .pl_cfg       (pl_cfg),
    .pl_cfg_vld   (pl_cfg_vld)
);

endmodule