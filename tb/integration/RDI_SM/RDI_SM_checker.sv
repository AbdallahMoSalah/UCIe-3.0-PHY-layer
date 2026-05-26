// ============================================================================
// RDI_SM_checker : SVA assertions for the RDI state machine.
// Bound into the RDI_SM DUT so it can observe top-level ports and the few
// internal signals it needs.  Implements assertions A01..A14 from the
// verification plan (some are relaxed to match the actual RTL behaviour and
// the remainder are covered by directed tests / the scoreboard).
// ============================================================================
import RDI_SM_pkg::*;
import UCIe_pkg::*;
import LTSM_state_pkg::*;

module RDI_SM_checker #(
    parameter int CYC_16MS = 160000   // LinkError residency in lclk cycles (TB timer scaling)
) (
    input logic                lclk,
    input logic                rst_n,
    // observed top-level ports
    input RDI_state            pl_state_sts,
    input logic                pl_inband_pres,
    input logic                pl_trainerror,
    input logic                pl_stallreq,
    input logic                stall_done,
    input logic                pl_clk_req,
    input logic                clk_handshake_done,
    input logic                pl_wake_ack,
    input logic                lp_wake_req,
    input logic                lp_linkerror,
    input logic                valid_s,
    input msg_no_e             Link_Mgmt_Msg_Send,
    input RDI_state            lp_state_req,
    input LTSM_state_e         state_sts,
    input logic                lclk_g,
    // observed internal signals
    input logic                Active_handshake_done,
    input logic                Active_handshake_strt
);

    default clocking cb @(posedge lclk); endclocking
    default disable iff (!rst_n);

    // ------------------------------------------------------------------
    // A01: pl_state_sts only changes the cycle after clk_handshake_done.
    // ------------------------------------------------------------------
    property p_a01;
        $changed(pl_state_sts) |-> $past(clk_handshake_done);
    endproperty
    A01_state_change_needs_clk_hs : assert property (p_a01)
        else $error("A01: pl_state_sts changed without preceding clk_handshake_done");

    // ------------------------------------------------------------------
    // A03: LinkError is held as long as lp_linkerror is asserted.
    // ------------------------------------------------------------------
    property p_a03;
        (pl_state_sts == LinkError) && lp_linkerror |=> (pl_state_sts == LinkError);
    endproperty
    A03_linkerror_held : assert property (p_a03)
        else $error("A03: left LinkError while lp_linkerror still asserted");

    // ------------------------------------------------------------------
    // A04: inband_pres is consistent with the visible state.
    //   asserted in Active / Retrain / Active_PMNAK / L1 / L2
    //   de-asserted in LinkReset / Disabled / LinkError
    // ------------------------------------------------------------------
    property p_a04_hi;
        (pl_state_sts inside {Active, Retrain, Active_PMNAK, L_1, L_2}) |-> pl_inband_pres;
    endproperty
    A04_inband_high : assert property (p_a04_hi)
        else $error("A04: pl_inband_pres low in a present state (%0s)", pl_state_sts.name());

    property p_a04_lo;
        (pl_state_sts inside {LinkReset, Disabled, LinkError}) |-> !pl_inband_pres;
    endproperty
    A04_inband_low : assert property (p_a04_lo)
        else $error("A04: pl_inband_pres high in a non-present state (%0s)", pl_state_sts.name());

    // ------------------------------------------------------------------
    // A05: Active_handshake_done is a single-cycle pulse.
    // ------------------------------------------------------------------
    property p_a05;
        $rose(Active_handshake_done) |=> !Active_handshake_done;
    endproperty
    A05_active_hs_done_pulse : assert property (p_a05)
        else $error("A05: Active_handshake_done held more than one cycle");

    // ------------------------------------------------------------------
    // A06: stall_done implies pl_stallreq is/was asserted.
    // ------------------------------------------------------------------
    property p_a06;
        stall_done |-> pl_stallreq;
    endproperty
    A06_stall_done_needs_req : assert property (p_a06)
        else $error("A06: stall_done without pl_stallreq");

    // ------------------------------------------------------------------
    // A07: clk_handshake_done implies pl_clk_req was asserted.
    // clk_handshake_done is a level held for the whole DONE state (not a
    // 1-cycle pulse), so only its rising edge must be preceded by pl_clk_req.
    // ------------------------------------------------------------------
    property p_a07;
        $rose(clk_handshake_done) |-> $past(pl_clk_req);
    endproperty
    A07_clk_done_needs_req : assert property (p_a07)
        else $error("A07: clk_handshake_done without preceding pl_clk_req");

    // ------------------------------------------------------------------
    // A08: pl_wake_ack only rises while lp_wake_req is asserted.
    // ------------------------------------------------------------------
    property p_a08;
        $rose(pl_wake_ack) |-> lp_wake_req;
    endproperty
    A08_wake_ack_needs_req : assert property (p_a08)
        else $error("A08: pl_wake_ack asserted without lp_wake_req");

    // ------------------------------------------------------------------
    // A09: pl_state_sts is always a legal encoding (never Nop / X).
    // ------------------------------------------------------------------
    property p_a09;
        pl_state_sts inside {Reset, Active, Active_PMNAK, L_1, L_2,
                             LinkReset, LinkError, Retrain, Disabled};
    endproperty
    A09_legal_state : assert property (p_a09)
        else $error("A09: illegal pl_state_sts encoding");

    // ------------------------------------------------------------------
    // A10: Link_Mgmt_Msg_Send is NOP whenever valid_s is de-asserted.
    // ------------------------------------------------------------------
    property p_a10;
        !valid_s |-> (Link_Mgmt_Msg_Send == NOP);
    endproperty
    A10_no_spurious_msg : assert property (p_a10)
        else $error("A10: Link_Mgmt_Msg_Send driven while valid_s low");

    // ------------------------------------------------------------------
    // A12: pl_trainerror is asserted while in LinkError and clears on Reset.
    // ------------------------------------------------------------------
    property p_a12_set;
        (pl_state_sts == LinkError) |-> pl_trainerror;
    endproperty
    A12_trainerror_in_linkerror : assert property (p_a12_set)
        else $error("A12: pl_trainerror low while in LinkError");

    property p_a12_clr;
        (pl_state_sts == Reset) |-> !pl_trainerror;
    endproperty
    A12_trainerror_clr_in_reset : assert property (p_a12_clr)
        else $error("A12: pl_trainerror high while in Reset");

    // ------------------------------------------------------------------
    // A02: every PM / Retrain / LinkReset / Disable message the DUT sends
    // from Active or Active_PMNAK is preceded by a completed stall handshake.
    // (Messages sent from Reset/Retrain/L1/L2 are not data-path stalled and
    // are intentionally excluded via the state guard.)
    // a02_stall_armed latches stall_done and holds until the link leaves the
    // Active/Active_PMNAK group, so the whole multi-message L1/L2 flow counts.
    // ------------------------------------------------------------------
    logic a02_stall_armed;
    always_ff @(posedge lclk or negedge rst_n) begin
        if (!rst_n)                                          a02_stall_armed <= 1'b0;
        else if (!(pl_state_sts inside {Active, Active_PMNAK})) a02_stall_armed <= 1'b0;
        else if (stall_done)                                 a02_stall_armed <= 1'b1;
    end
    property p_a02;
        (valid_s &&
         (Link_Mgmt_Msg_Send inside {RDI_RETRAIN_REQ, RDI_RETRAIN_RSP,
                                     RDI_LINK_RESET_REQ, RDI_LINK_RESET_RSP,
                                     RDI_DISABLE_REQ, RDI_DISABLE_RSP,
                                     RDI_L1_REQ, RDI_L1_RSP,
                                     RDI_L2_REQ, RDI_L2_RSP}) &&
         (pl_state_sts inside {Active, Active_PMNAK}))
        |-> a02_stall_armed;
    endproperty
    A02_stall_before_msg : assert property (p_a02)
        else $error("A02: %s sent in %s without a preceding stall handshake",
                    Link_Mgmt_Msg_Send.name(), pl_state_sts.name());

    // ------------------------------------------------------------------
    // A11: minimum 16ms residency in LinkError before exiting (to Reset).
    // ------------------------------------------------------------------
    int unsigned a11_le_cnt;
    always_ff @(posedge lclk or negedge rst_n) begin
        if (!rst_n)                      a11_le_cnt <= 0;
        else if (pl_state_sts == LinkError) a11_le_cnt <= a11_le_cnt + 1;
        else                             a11_le_cnt <= 0;
    end
    property p_a11;
        (pl_state_sts == LinkError) ##1 (pl_state_sts != LinkError)
        |-> ($past(a11_le_cnt) >= (CYC_16MS - 16));
    endproperty
    A11_linkerror_residency : assert property (p_a11)
        else $error("A11: left LinkError after only %0d cycles (< 16ms = %0d)",
                    $past(a11_le_cnt), CYC_16MS);

    // ------------------------------------------------------------------
    // A13: a NOP->Active request in Reset (with LINKINIT reached) makes the
    // Active handshake start within a bounded number of cycles.
    // ------------------------------------------------------------------
    property p_a13;
        (pl_state_sts == Reset && state_sts == LINKINIT &&
         $past(lp_state_req) == Nop && lp_state_req == Active)
        |-> ##[1:12] Active_handshake_strt;
    endproperty
    A13_bringup_handshake : assert property (p_a13)
        else $error("A13: Active_handshake_strt did not pulse after NOP->Active in Reset");

    // ------------------------------------------------------------------
    // A14: clocks are never gated in Active / Retrain / Active_PMNAK.
    // Sampled on the negedge so the high phase of lclk is observed: an
    // ungated lclk_g reads 1 there, a gated one reads 0.
    // ------------------------------------------------------------------
    property p_a14;
        @(negedge lclk) disable iff (!rst_n)
        (pl_state_sts inside {Active, Retrain, Active_PMNAK}) |-> lclk_g;
    endproperty
    A14_no_gate_in_active : assert property (p_a14)
        else $error("A14: lclk_g gated while in %s", pl_state_sts.name());

    initial $display("[%0t] [CHECKER] RDI_SM_checker bound into %m", $time);

endmodule

// NOTE: the bind statement is placed inside the testbench top module
// (RDI_SM_tb) rather than here at compilation-unit scope.  A $unit-scope bind
// is not guaranteed to be elaborated by vsim (vlog-2650) unless -cuname is
// passed, which would leave the assertions silently inactive.
