// ============================================================================
// RDI_SM_tb : Integration testbench for the RDI state machine.
//
// The repo build flow compiles a single filelist into a single top
// (make run CONFIG=RDI_SM TOP=RDI_SM_tb), so the verification plan's
// driver / monitor / scoreboard / sequence / test components are realised
// here as sections of this top module:
//   * clock & reset generation
//   * auto CLK-ack and STALL-ack responders (the adapter handshake side)
//   * a symmetric RDI peer message model (REQ->RSP auto-responder)
//   * adapter / LTSM / DVSEC driver tasks
//   * reusable protocol sequence tasks
//   * directed tests (TG-01..TG-15, TC-ILL, TC-TIM, SC-01..SC-10)
//   * functional coverage
//   * a simple scoreboard (pass/fail counters + transition legality)
//
// SVA assertions A01..A14 live in RDI_SM_checker.sv (bound to the DUT).
// ============================================================================
`timescale 1ns/1ps

// LinkError 16ms residency expressed in lclk cycles at the scaled TB clock
// (10MHz -> 16ms = 160000 cycles).  A macro so the same constant feeds both the
// TB localparam and the bound checker's parameter (a bind cannot take a TB
// localparam as a parameter override - it must be a compile-time constant).
`define RDI_CYC_16MS 160000

import RDI_SM_pkg::*;
import UCIe_pkg::*;
import LTSM_state_pkg::*;

module RDI_SM_tb;

    // ------------------------------------------------------------------
    // Timing.  The RTL timers default to 2GHz (16ms = 32M cycles which is
    // infeasible to simulate).  We override CLK_FREQ on the timer and the
    // gating logic to 10MHz via defparam below, giving:
    //     1us  = 10 cycles
    //     16ms = 160000 cycles
    // ------------------------------------------------------------------
    localparam int  CLK_FREQ_TB = 10_000_000;          // 10 MHz
    localparam real CLK_PERIOD  = 1.0e9 / CLK_FREQ_TB;  // ns  -> 100ns
    localparam int  CYC_1US     = 10;
    localparam int  CYC_16MS    = `RDI_CYC_16MS;

    // ------------------------------------------------------------------
    // DUT connectivity
    // ------------------------------------------------------------------
    logic        lclk;
    logic        rst_n;

    // adapter inputs
    logic        lp_clk_ack;
    logic        lp_wake_req;
    logic        lp_stallack;
    RDI_state    lp_state_req;
    logic        lp_linkerror;

    // PL outputs
    logic        pl_clk_req;
    logic        pl_stallreq;
    logic        pl_wake_ack;
    logic        pl_trainerror;
    logic        pl_inband_pres;
    logic        pl_phyinrecenter;
    RDI_state    pl_state_sts;
    logic        pl_max_speedmode;
    logic [2:0]  pl_speedmode;
    logic [2:0]  pl_lnk_cfg;

    // sideband interface
    logic [3:0]  cap_7to4;
    logic [3:0]  sts_17to11;
    logic [3:0]  sts_10to7;
    msg_no_e     Link_Mgmt_Msg_Receive;
    logic        valid_r;
    msg_no_e     Link_Mgmt_Msg_Send;
    logic        valid_s;

    // MB / misc
    logic        traffic_req;
    logic        clk_handshake_done;
    logic        lclk_g;
    logic        stall_done;
    logic        pl_error;

    // LTSM
    LTSM_state_e state_sts;

    // ------------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------------
    RDI_SM dut (
        .lclk             (lclk),
        .rst_n            (rst_n),
        .lp_clk_ack       (lp_clk_ack),
        .lp_wake_req      (lp_wake_req),
        .lp_stallack      (lp_stallack),
        .lp_state_req     (lp_state_req),
        .lp_linkerror     (lp_linkerror),

        .pl_clk_req       (pl_clk_req),
        .pl_stallreq      (pl_stallreq),
        .pl_wake_ack      (pl_wake_ack),
        .pl_trainerror    (pl_trainerror),
        .pl_inband_pres   (pl_inband_pres),
        .pl_phyinrecenter (pl_phyinrecenter),
        .pl_state_sts     (pl_state_sts),
        .pl_max_speedmode (pl_max_speedmode),
        .pl_speedmode     (pl_speedmode),
        .pl_lnk_cfg       (pl_lnk_cfg),

        .UCIe_Link_DVSEC_UCIe_Link_Capability_7to4 (cap_7to4),
        .UCIe_Link_DVSEC_UCIe_Link_Status_17to11   (sts_17to11),
        .UCIe_Link_DVSEC_UCIe_Link_Status_10to7    (sts_10to7),
        .Link_Mgmt_Msg_Receive (Link_Mgmt_Msg_Receive),
        .valid_r          (valid_r),
        .Link_Mgmt_Msg_Send (Link_Mgmt_Msg_Send),
        .valid_s          (valid_s),

        .traffic_req      (traffic_req),
        .clk_handshake_done (clk_handshake_done),

        .lclk_g           (lclk_g),
        .stall_done       (stall_done),
        .pl_error         (pl_error),

        .state_sts        (state_sts)
    );

    // Shrink the RTL timers so 1us/16ms are simulatable.
    defparam dut.sm.u_unit_Timer.CLK_FREQ  = CLK_FREQ_TB;
    defparam dut.gating_logic.CLK_FREQ      = CLK_FREQ_TB;

    // Bind the SVA checker (A01..A14) into every RDI_SM instance.  Kept here in
    // an elaborated module scope so it is guaranteed to elaborate (a
    // compilation-unit-scope bind can be silently dropped by vsim - vlog-2650).
    bind RDI_SM RDI_SM_checker #(.CYC_16MS(`RDI_CYC_16MS)) u_rdi_sm_checker (
        .lclk                  (lclk),
        .rst_n                 (rst_n),
        .pl_state_sts          (pl_state_sts),
        .pl_inband_pres        (pl_inband_pres),
        .pl_trainerror         (pl_trainerror),
        .pl_stallreq           (pl_stallreq),
        .stall_done            (stall_done),
        .pl_clk_req            (pl_clk_req),
        .clk_handshake_done    (clk_handshake_done),
        .pl_wake_ack           (pl_wake_ack),
        .lp_wake_req           (lp_wake_req),
        .lp_linkerror          (lp_linkerror),
        .valid_s               (valid_s),
        .Link_Mgmt_Msg_Send    (Link_Mgmt_Msg_Send),
        .lp_state_req          (lp_state_req),
        .state_sts             (state_sts),
        .lclk_g                (lclk_g),
        .Active_handshake_done (Active_handshake_done),
        .Active_handshake_strt (Active_handshake_strt)
    );

    // ------------------------------------------------------------------
    // Clock
    // ------------------------------------------------------------------
    initial lclk = 1'b0;
    always #(CLK_PERIOD/2.0) lclk = ~lclk;

    // ==================================================================
    // Auto adapter-side handshake responders
    //   * CLK handshake : lp_clk_ack follows pl_clk_req (1-cycle delay).
    //   * STALL handshake: lp_stallack follows pl_stallreq (1-cycle delay).
    // These are essential: pl_state_sts only updates once a CLK handshake
    // completes, so without the auto CLK-ack nothing would ever be visible.
    // Both can be disabled to drive the handshakes manually (TG-09).
    // ------------------------------------------------------------------
    bit auto_clk_ack   = 1'b1;
    bit auto_stall_ack = 1'b1;

    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n)        lp_clk_ack <= 1'b0;
        else if (auto_clk_ack) lp_clk_ack <= pl_clk_req;
    end

    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n)          lp_stallack <= 1'b0;
        else if (auto_stall_ack) lp_stallack <= pl_stallreq;
    end

    // ==================================================================
    // Peer message model (symmetric RDI partner)
    //   peer_send() drives valid_r/Link_Mgmt_Msg_Receive for one cycle,
    //   serialized by a semaphore so concurrent responses never collide.
    //   The auto-responder answers each DUT-initiated REQ with the
    //   matching RSP (and, for the symmetric ACTIVE/L1/L2 flows, the
    //   peer's own REQ as well).
    // ------------------------------------------------------------------
    bit      peer_en       = 1'b1;   // auto-responder enable
    bit      peer_pmnak    = 1'b0;   // answer L1/L2 REQ with PMNAK_RSP
    bit      peer_drop_rsp = 1'b0;   // drop responses (timeout scenarios)
    int      peer_delay    = 2;      // cycles before a response is driven
    semaphore rx_lock      = new(1);

    task automatic peer_send(msg_no_e m);
        rx_lock.get(1);
        repeat (peer_delay) @(negedge lclk);
        Link_Mgmt_Msg_Receive = m;
        valid_r               = 1'b1;
        @(negedge lclk);
        valid_r               = 1'b0;
        Link_Mgmt_Msg_Receive = NOP;
        repeat (2) @(negedge lclk);   // let msg_handler consume the entry
        rx_lock.put(1);
    endtask

    task automatic respond_to(msg_no_e m);
        if (peer_drop_rsp) return;
        case (m)
            RDI_ACTIVE_REQ     : begin peer_send(RDI_ACTIVE_RSP);  peer_send(RDI_ACTIVE_REQ); end
            RDI_RETRAIN_REQ    : peer_send(RDI_RETRAIN_RSP);
            RDI_LINK_RESET_REQ : peer_send(RDI_LINK_RESET_RSP);
            RDI_LINK_ERROR_REQ : peer_send(RDI_LINK_ERROR_RSP);
            RDI_DISABLE_REQ    : peer_send(RDI_DISABLE_RSP);
            RDI_L1_REQ         : if (peer_pmnak) peer_send(RDI_PMNAK_RSP);
                                 else begin peer_send(RDI_L1_REQ); peer_send(RDI_L1_RSP); end
            RDI_L2_REQ         : if (peer_pmnak) peer_send(RDI_PMNAK_RSP);
                                 else begin peer_send(RDI_L2_REQ); peer_send(RDI_L2_RSP); end
            default            : /* RSPs and NOP need no peer action */ ;
        endcase
    endtask

    // Watch DUT-initiated messages and fire the matching peer response.
    msg_no_e prev_send;
    bit      prev_vs;
    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            prev_vs   <= 1'b0;
            prev_send <= NOP;
        end else begin
            if (peer_en && valid_s && (!prev_vs || (Link_Mgmt_Msg_Send != prev_send)))
                fork respond_to(Link_Mgmt_Msg_Send); join_none
            prev_vs   <= valid_s;
            prev_send <= Link_Mgmt_Msg_Send;
        end
    end

    // ==================================================================
    // Scoreboard : pass/fail counters + state-transition legality.
    // ------------------------------------------------------------------
    int unsigned checks_run  = 0;
    int unsigned checks_fail = 0;
    string       cur_test    = "";

    function automatic void check(bit cond, string msg);
        checks_run++;
        if (!cond) begin
            checks_fail++;
            $error("[%0t] [%s] CHECK FAILED: %s", $time, cur_test, msg);
        end
    endfunction

    // Legal pl_state_sts arcs (RDI spec Table 10-4, as implemented).
    function automatic bit legal_arc(RDI_state f, RDI_state t);
        if (f == t) return 1'b1;
        case (f)
            Reset       : return t inside {Active, LinkError, Disabled, LinkReset};
            Active       : return t inside {Retrain, L_1, L_2, LinkReset, LinkError,
                                            Disabled, Active_PMNAK};
            Active_PMNAK : return t inside {Active, Retrain, LinkReset, LinkError, Disabled};
            Retrain      : return t inside {Active, LinkReset, LinkError, Disabled};
            L_1          : return t inside {Retrain, LinkReset, LinkError, Disabled};
            L_2          : return t inside {Reset, LinkReset, LinkError, Disabled};
            LinkReset    : return t inside {Reset, LinkError, Disabled};
            LinkError    : return t inside {Reset};
            Disabled     : return t inside {Reset, LinkError};
            default      : return 1'b0;
        endcase
    endfunction

    RDI_state prev_pl_state;
    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) prev_pl_state <= Reset;
        else begin
            if (pl_state_sts !== prev_pl_state) begin
                if (!legal_arc(prev_pl_state, pl_state_sts))
                    $error("[%0t] [%s] ILLEGAL transition %s -> %s",
                           $time, cur_test, prev_pl_state.name(), pl_state_sts.name());
                prev_pl_state <= pl_state_sts;
            end
        end
    end

    // ==================================================================
    // Functional coverage
    // ------------------------------------------------------------------
    covergroup cg_state @(posedge lclk);
        option.per_instance = 1;
        cp_state : coverpoint pl_state_sts iff (rst_n) {
            bins reset    = {Reset};
            bins active   = {Active};
            bins pmnak    = {Active_PMNAK};
            bins l1       = {L_1};
            bins l2       = {L_2};
            bins lreset   = {LinkReset};
            bins lerror   = {LinkError};
            bins retrain  = {Retrain};
            bins disabled = {Disabled};
        }
        cp_trans : coverpoint pl_state_sts iff (rst_n) {
            bins bringup   = (Reset    => Active);
            bins to_l1     = (Active   => L_1);
            bins to_l2     = (Active   => L_2);
            bins to_retr   = (Active   => Retrain);
            bins to_pmnak  = (Active   => Active_PMNAK);
            bins to_lreset = (Active   => LinkReset);
            bins to_lerror = (Active   => LinkError);
            bins to_dis    = (Active   => Disabled);
            bins retr_act  = (Retrain  => Active);
            bins l1_retr   = (L_1      => Retrain);
            bins l2_reset  = (L_2      => Reset);
            bins le_reset  = (LinkError=> Reset);
            bins pmnak_act = (Active_PMNAK => Active);
        }
    endgroup

    covergroup cg_msg_tx @(posedge lclk iff (rst_n && valid_s));
        option.per_instance = 1;
        cp_tx : coverpoint Link_Mgmt_Msg_Send {
            bins active_req = {RDI_ACTIVE_REQ};
            bins active_rsp = {RDI_ACTIVE_RSP};
            bins l1_req     = {RDI_L1_REQ};
            bins l1_rsp     = {RDI_L1_RSP};
            bins l2_req     = {RDI_L2_REQ};
            bins l2_rsp     = {RDI_L2_RSP};
            bins retr_req   = {RDI_RETRAIN_REQ};
            bins retr_rsp   = {RDI_RETRAIN_RSP};
            bins lr_req     = {RDI_LINK_RESET_REQ};
            bins lr_rsp     = {RDI_LINK_RESET_RSP};
            bins le_req     = {RDI_LINK_ERROR_REQ};
            bins le_rsp     = {RDI_LINK_ERROR_RSP};
            bins dis_req    = {RDI_DISABLE_REQ};
            bins dis_rsp    = {RDI_DISABLE_RSP};
            bins pmnak_rsp  = {RDI_PMNAK_RSP};
        }
    endgroup

    covergroup cg_msg_rx @(posedge lclk iff (rst_n && valid_r));
        option.per_instance = 1;
        cp_rx : coverpoint Link_Mgmt_Msg_Receive {
            bins active_req = {RDI_ACTIVE_REQ};
            bins active_rsp = {RDI_ACTIVE_RSP};
            bins l1_req     = {RDI_L1_REQ};
            bins l1_rsp     = {RDI_L1_RSP};
            bins l2_req     = {RDI_L2_REQ};
            bins l2_rsp     = {RDI_L2_RSP};
            bins retr_rsp   = {RDI_RETRAIN_RSP};
            bins retr_req   = {RDI_RETRAIN_REQ};
            bins lr_req     = {RDI_LINK_RESET_REQ};
            bins lr_rsp     = {RDI_LINK_RESET_RSP};
            bins le_req     = {RDI_LINK_ERROR_REQ};
            bins le_rsp     = {RDI_LINK_ERROR_RSP};
            bins dis_req    = {RDI_DISABLE_REQ};
            bins dis_rsp    = {RDI_DISABLE_RSP};
            bins pmnak_rsp  = {RDI_PMNAK_RSP};
        }
    endgroup

    cg_state  cov_state;
    cg_msg_tx cov_tx;
    cg_msg_rx cov_rx;

    // ==================================================================
    // Low-level helpers
    // ------------------------------------------------------------------
    task automatic tick(int n = 1);
        repeat (n) @(posedge lclk);
    endtask

    task automatic banner(string name);
        cur_test = name;
        $display("\n================ %s ================", name);
    endtask

    // Wait until pl_state_sts == s (or fail after `tmo` cycles).
    task automatic wait_state(RDI_state s, int tmo = 4000);
        int c = 0;
        while ((pl_state_sts !== s) && (c < tmo)) begin
            @(posedge lclk); c++;
        end
        check(pl_state_sts === s,
              $sformatf("expected pl_state_sts==%s, got %s after %0d cyc",
                        s.name(), pl_state_sts.name(), c));
    endtask

    // Expect pl_state_sts to stay == s for `n` cycles.
    task automatic expect_stable(RDI_state s, int n = 40);
        for (int i = 0; i < n; i++) begin
            check(pl_state_sts === s,
                  $sformatf("expected stable %s, saw %s", s.name(), pl_state_sts.name()));
            @(posedge lclk);
        end
    endtask

    // Check whether lclk_g is gated, sampled during the HIGH phase of lclk.
    // (Sampling at the negedge is useless: lclk is 0 there, so a gated and an
    // ungated lclk_g both read 0.)  expect_gated=1 -> lclk_g must be 0 while
    // lclk is high; expect_gated=0 -> lclk_g must track lclk (==1).
    task automatic check_gated(bit expect_gated, string msg);
        @(posedge lclk);
        #1;  // settle into the high phase (period is 100ns, so well clear of edges)
        if (expect_gated) check(lclk_g === 1'b0, msg);
        else              check(lclk_g === 1'b1, msg);
    endtask

    // Wait for a particular DUT-sent message (returns 1 if seen).
    task automatic wait_msg_sent(msg_no_e m, output bit seen, input int tmo = 200);
        int c = 0;
        seen = 0;
        while (c < tmo) begin
            @(posedge lclk);
            if (valid_s && (Link_Mgmt_Msg_Send == m)) begin seen = 1; break; end
            c++;
        end
    endtask

    // ==================================================================
    // Driver tasks
    // ------------------------------------------------------------------
    task automatic init_inputs();
        lp_clk_ack            = 0;
        lp_wake_req           = 0;
        lp_stallack           = 0;
        lp_state_req          = Nop;
        lp_linkerror          = 0;
        traffic_req           = 0;
        pl_error              = 0;
        state_sts             = RESET;
        Link_Mgmt_Msg_Receive = NOP;
        valid_r               = 0;
        cap_7to4              = 4'h0;
        sts_17to11            = 4'h0;
        sts_10to7             = 4'h0;
        peer_en               = 1;
        peer_pmnak            = 0;
        peer_drop_rsp         = 0;
        peer_delay            = 2;
        auto_clk_ack          = 1;
        auto_stall_ack        = 1;
    endtask

    task automatic do_reset(int cycles = 5);
        rst_n = 0;
        init_inputs();
        tick(cycles);
        @(negedge lclk);
        rst_n = 1;
        tick(2);
    endtask

    // ==================================================================
    // Reusable protocol sequences
    // ------------------------------------------------------------------
    // Reset -> Active bring-up (FLOW_0 via the peer auto-responder).
    task automatic seq_reset_to_active();
        lp_state_req = Nop;
        state_sts    = LINKINIT;
        tick(4);                 // reset_state settles into NOP_rcvd
        lp_state_req = Active;
        wait_state(Active);
    endtask

    // Active -> L1 (adapter initiated).  Leaves lp_state_req == L_1.
    task automatic seq_active_to_l1();
        lp_state_req = L_1;
        wait_state(L_1);
    endtask

    // Active -> L2 (adapter initiated).
    task automatic seq_active_to_l2();
        lp_state_req = L_2;
        wait_state(L_2);
    endtask

    // Active -> Retrain (adapter initiated).
    task automatic seq_active_to_retrain();
        lp_state_req = Retrain;
        wait_state(Retrain);
    endtask

    // Retrain/L1 -> Active (drive LINKINIT then Active).
    task automatic seq_exit_to_active();
        state_sts    = LINKINIT;
        lp_state_req = Nop;
        tick(3);
        lp_state_req = Active;
        wait_state(Active);
    endtask

    // Active -> LinkError (adapter initiated) and recover to Reset/Active.
    task automatic seq_linkerror_recovery();
        lp_linkerror = 1;
        wait_state(LinkError);
        // hold for the 16ms residency, then release with Active requested
        tick(CYC_16MS + 50);
        lp_linkerror = 0;
        lp_state_req = Active;
        wait_state(Reset);
    endtask

    // ==================================================================
    // TG-01 : Reset & Initialisation
    // ------------------------------------------------------------------
    task automatic tg01_reset();
        banner("TG-01 Reset & Initialisation");

        // TC-01.1 : reset values
        do_reset();
        check(pl_state_sts === Reset, "TC-01.1 pl_state_sts == Reset after reset");
        check(pl_stallreq  === 1'b0,  "TC-01.1 pl_stallreq == 0 after reset");
        check(pl_clk_req   === 1'b0,  "TC-01.1 pl_clk_req == 0 after reset");
        check(pl_wake_ack  === 1'b0,  "TC-01.1 pl_wake_ack == 0 after reset");
        check(pl_trainerror=== 1'b0,  "TC-01.1 pl_trainerror == 0 after reset");

        // TC-01.3 : reset with a non-NOP request still lands in Reset
        do_reset();
        lp_state_req = Disabled;
        tick(3);
        do_reset();
        check(pl_state_sts === Reset, "TC-01.3 Reset regardless of lp_state_req");

        // TC-01.2 : reset mid-operation returns to Reset
        do_reset();
        seq_reset_to_active();
        check(pl_state_sts === Active, "TC-01.2 reached Active before reset");
        do_reset();
        check(pl_state_sts === Reset, "TC-01.2 returned to Reset after async reset");
    endtask

    // ==================================================================
    // TG-02 : Reset -> Active bring-up
    // ------------------------------------------------------------------
    task automatic tg02_bringup();
        banner("TG-02 Reset -> Active bring-up");

        // TC-02.1 : standard FLOW_0
        do_reset();
        seq_reset_to_active();
        check(pl_state_sts === Active,   "TC-02.1 reached Active");
        check(pl_inband_pres === 1'b1,   "TC-02.1 pl_inband_pres asserted in Active");

        // TC-02.3 : Active requested before LINKINIT -> must wait
        do_reset();
        lp_state_req = Nop;
        state_sts    = MBTRAIN;       // not LINKINIT yet
        tick(4);
        lp_state_req = Active;        // requested early
        expect_stable(Reset, 20);    // stays in Reset until LINKINIT
        state_sts    = LINKINIT;
        wait_state(Active);
        check(pl_state_sts === Active, "TC-02.3 reaches Active once LINKINIT seen");
    endtask

    // ==================================================================
    // TG-03 : Active -> Retrain flows
    // ------------------------------------------------------------------
    task automatic tg03_retrain();
        bit seen;
        banner("TG-03 Active -> Retrain");

        // TC-03.1 : adapter-initiated retrain
        do_reset(); seq_reset_to_active();
        lp_state_req = Retrain;
        wait_msg_sent(RDI_RETRAIN_REQ, seen);
        check(seen, "TC-03.1 RDI_RETRAIN_REQ sent");
        wait_state(Retrain);
        check(pl_state_sts === Retrain, "TC-03.1 reached Retrain");

        // TC-03.5 : Retrain -> Active
        seq_exit_to_active();
        check(pl_state_sts === Active, "TC-03.5 Retrain -> Active");

        // TC-03.2 : pl_error-triggered retrain
        do_reset(); seq_reset_to_active();
        pl_error = 1; tick(1); pl_error = 0;
        wait_state(Retrain);
        check(pl_state_sts === Retrain, "TC-03.2 pl_error triggers Retrain");

        // TC-03.3 : PHYRETRAIN-triggered retrain
        do_reset(); seq_reset_to_active();
        state_sts = PHYRETRAIN;
        wait_state(Retrain);
        check(pl_state_sts === Retrain, "TC-03.3 PHYRETRAIN triggers Retrain");

        // TC-03.4 : peer-initiated retrain
        do_reset(); seq_reset_to_active();
        peer_send(RDI_RETRAIN_REQ);
        wait_state(Retrain);
        check(pl_state_sts === Retrain, "TC-03.4 peer RETRAIN_REQ -> Retrain");
    endtask

    // ==================================================================
    // TG-04 : PM entry (L1/L2) and PMNAK
    // ------------------------------------------------------------------
    task automatic tg04_pm();
        bit seen;
        banner("TG-04 PM entry / PMNAK");

        // TC-04.1 : L1 entry (adapter)
        do_reset(); seq_reset_to_active();
        lp_state_req = L_1;
        wait_msg_sent(RDI_L1_REQ, seen);
        check(seen, "TC-04.1 RDI_L1_REQ sent");
        wait_state(L_1);
        check(pl_state_sts === L_1, "TC-04.1 reached L1");

        // TC-04.2 : L2 entry (adapter)
        do_reset(); seq_reset_to_active();
        lp_state_req = L_2;
        wait_msg_sent(RDI_L2_REQ, seen);
        check(seen, "TC-04.2 RDI_L2_REQ sent");
        wait_state(L_2);
        check(pl_state_sts === L_2, "TC-04.2 reached L2");

        // TC-04.4 : PMNAK - peer NAKs the L1 request
        do_reset(); seq_reset_to_active();
        peer_pmnak   = 1;
        lp_state_req = L_1;
        wait_state(Active_PMNAK);
        check(pl_state_sts === Active_PMNAK, "TC-04.4 PMNAK -> Active_PMNAK");
        // after PMNAK, request Active again -> back to Active
        peer_pmnak   = 0;
        lp_state_req = Active;
        wait_state(Active);
        check(pl_state_sts === Active, "TC-04.4 PMNAK returns to Active");
    endtask

    // ==================================================================
    // TG-05 : L1/L2 exit & error flows
    // ------------------------------------------------------------------
    task automatic tg05_l1l2();
        bit seen;
        banner("TG-05 L1/L2 exit & errors");

        // TC-05.1 : L1 -> Active
        do_reset(); seq_reset_to_active(); seq_active_to_l1();
        check(pl_state_sts === L_1, "TC-05.1 in L1");
        lp_state_req = Active;
        wait_state(Retrain);                 // L1 exits via Retrain
        check(pl_state_sts === Retrain, "TC-05.1 L1 -> Retrain on exit");

        // TC-05.2 : L2 -> Reset
        do_reset(); seq_reset_to_active(); seq_active_to_l2();
        check(pl_state_sts === L_2, "TC-05.2 in L2");
        lp_state_req = Active;
        wait_state(Reset);
        check(pl_state_sts === Reset, "TC-05.2 L2 -> Reset on exit");

        // TC-05.3 : link error while in L1
        do_reset(); seq_reset_to_active(); seq_active_to_l1();
        lp_linkerror = 1;
        wait_state(LinkError);
        check(pl_state_sts === LinkError, "TC-05.3 L1 -> LinkError");

        // TC-05.5 : Disable while in L1
        do_reset(); seq_reset_to_active(); seq_active_to_l1();
        lp_state_req = Disabled;
        wait_state(Disabled);
        check(pl_state_sts === Disabled, "TC-05.5 L1 -> Disabled");
    endtask

    // ==================================================================
    // TG-06 : LinkReset state
    // ------------------------------------------------------------------
    task automatic tg06_linkreset();
        bit seen;
        banner("TG-06 LinkReset");

        // TC-06.1 : Active -> LinkReset
        do_reset(); seq_reset_to_active();
        lp_state_req = LinkReset;
        wait_msg_sent(RDI_LINK_RESET_REQ, seen);
        check(seen, "TC-06.1 RDI_LINK_RESET_REQ sent");
        wait_state(LinkReset);
        check(pl_state_sts === LinkReset, "TC-06.1 reached LinkReset");

        // TC-06.2 : LinkReset -> Reset
        lp_state_req = Active;
        wait_state(Reset);
        check(pl_state_sts === Reset, "TC-06.2 LinkReset -> Reset");

        // TC-06.3 : LinkReset -> Disabled
        do_reset(); seq_reset_to_active();
        lp_state_req = LinkReset;
        wait_state(LinkReset);
        lp_state_req = Disabled;
        wait_state(Disabled);
        check(pl_state_sts === Disabled, "TC-06.3 LinkReset -> Disabled");

        // TC-06.4 : link error in LinkReset
        do_reset(); seq_reset_to_active();
        lp_state_req = LinkReset;
        wait_state(LinkReset);
        lp_linkerror = 1;
        wait_state(LinkError);
        check(pl_state_sts === LinkError, "TC-06.4 LinkReset -> LinkError");
    endtask

    // ==================================================================
    // TG-07 : LinkError state
    // ------------------------------------------------------------------
    task automatic tg07_linkerror();
        bit seen;
        banner("TG-07 LinkError");

        // TC-07.1 : link error from Active
        do_reset(); seq_reset_to_active();
        lp_linkerror = 1;
        wait_msg_sent(RDI_LINK_ERROR_REQ, seen);
        check(seen, "TC-07.1 RDI_LINK_ERROR_REQ sent");
        wait_state(LinkError);
        check(pl_state_sts === LinkError, "TC-07.1 reached LinkError");
        check(pl_trainerror === 1'b1,     "TC-07.1 pl_trainerror asserted");

        // TC-07.6 : must NOT exit before 16ms
        lp_linkerror = 0;
        lp_state_req = Active;
        expect_stable(LinkError, 200);    // far less than 16ms
        check(pl_state_sts === LinkError, "TC-07.6 stays in LinkError before 16ms");

        // TC-07.5 : exit after 16ms
        tick(CYC_16MS);
        wait_state(Reset);
        check(pl_state_sts === Reset, "TC-07.5 LinkError -> Reset after 16ms");

        // TC-07.2 : peer-initiated link error
        do_reset(); seq_reset_to_active();
        peer_send(RDI_LINK_ERROR_REQ);
        wait_state(LinkError);
        check(pl_state_sts === LinkError, "TC-07.2 peer LINK_ERROR_REQ -> LinkError");

        // TC-07.3 : link error in Reset
        do_reset();
        lp_linkerror = 1;
        wait_state(LinkError);
        check(pl_state_sts === LinkError, "TC-07.3 Reset -> LinkError");
    endtask

    // ==================================================================
    // TG-08 : Disabled state
    // ------------------------------------------------------------------
    task automatic tg08_disabled();
        bit seen;
        banner("TG-08 Disabled");

        // TC-08.1 : Active -> Disabled
        do_reset(); seq_reset_to_active();
        lp_state_req = Disabled;
        wait_msg_sent(RDI_DISABLE_REQ, seen);
        check(seen, "TC-08.1 RDI_DISABLE_REQ sent");
        wait_state(Disabled);
        check(pl_state_sts === Disabled, "TC-08.1 reached Disabled");

        // TC-08.2 : Disabled -> Reset
        lp_state_req = Active;
        wait_state(Reset);
        check(pl_state_sts === Reset, "TC-08.2 Disabled -> Reset");

        // TC-08.3 : link error while Disabled
        do_reset(); seq_reset_to_active();
        lp_state_req = Disabled;
        wait_state(Disabled);
        lp_state_req = Nop;
        lp_linkerror = 1;
        wait_state(LinkError);
        check(pl_state_sts === LinkError, "TC-08.3 Disabled -> LinkError");
    endtask

    // ==================================================================
    // TG-09 : handshake sub-modules (manual control)
    // ------------------------------------------------------------------
    task automatic tg09_handshakes();
        banner("TG-09 handshake sub-modules");

        // TC-09.7/09.8 : AWAKE handshake
        do_reset();
        lp_wake_req = 1;
        // ungating completes (UNGATING -> ACK) -> pl_wake_ack
        fork begin
            int c = 0;
            while (!pl_wake_ack && c < 200) begin @(posedge lclk); c++; end
        end join
        check(pl_wake_ack === 1'b1, "TC-09.7 pl_wake_ack after lp_wake_req");
        tick(2);   // hold lp_wake_req past pl_wake_ack (spec: drop only after ack)
        lp_wake_req = 0;
        tick(3);
        check(pl_wake_ack === 1'b0, "TC-09.8 pl_wake_ack clears after lp_wake_req drops");

        // TC-09.5 : CLK handshake via traffic_req path
        do_reset();
        traffic_req = 1;
        fork begin
            int c = 0;
            while (!pl_clk_req && c < 50) begin @(posedge lclk); c++; end
        end join
        check(pl_clk_req === 1'b1, "TC-09.5 traffic_req drives pl_clk_req");
        // auto clk-ack completes it
        fork begin
            int c = 0;
            while (!clk_handshake_done && c < 50) begin @(posedge lclk); c++; end
        end join
        check(clk_handshake_done === 1'b1, "TC-09.5 clk_handshake_done asserts");
        traffic_req = 0;
    endtask

    // ==================================================================
    // TG-10 : clock gating logic
    // ------------------------------------------------------------------
    task automatic tg10_gating();
        int c;
        banner("TG-10 clock gating");

        // TC-10.2 : Active never gates
        do_reset(); seq_reset_to_active();
        lp_state_req = Active;
        tick(4 * CYC_1US);
        check_gated(0, "TC-10.2 lclk_g tracks lclk in Active");

        // TC-10.1 : gateable state (L1) gates after >1us of stable conditions
        do_reset(); seq_reset_to_active(); seq_active_to_l1();
        lp_state_req = Nop;
        lp_wake_req  = 0;
        tick(3 * CYC_1US);
        check_gated(1, "TC-10.1 lclk_g gated (0) in L1 after 1us");

        // TC-10.3 : wake request ungates the clock.  Hold lp_wake_req until
        // pl_wake_ack (per spec: lp_wake_req de-asserts only after pl_wake_ack).
        lp_wake_req = 1;
        c = 0; while (!pl_wake_ack && c < 200) begin @(posedge lclk); c++; end
        check(pl_wake_ack === 1'b1, "TC-10.3 pl_wake_ack asserts after wake req");
        check_gated(0, "TC-10.3 wake request ungates lclk_g");
        lp_wake_req = 0;
        tick(3);
    endtask

    // ==================================================================
    // TG-11 : message handler
    // ------------------------------------------------------------------
    task automatic tg11_msg_handler();
        bit seen;
        banner("TG-11 message handler");

        // TC-11.1 : Message_send path produces valid_s + correct message
        do_reset(); seq_reset_to_active();
        lp_state_req = Retrain;
        wait_msg_sent(RDI_RETRAIN_REQ, seen);
        check(seen, "TC-11.1 valid_s + Link_Mgmt_Msg_Send driven for TX");
        wait_state(Retrain);

        // TC-11.2 : received message is processed (peer DISABLE_REQ honoured).
        // Drop lp_state_req to Nop first: a peer-initiated disable is not an
        // adapter Active request, and holding Active would (correctly) bounce
        // Disabled straight back to Reset (TC-08.2).
        do_reset(); seq_reset_to_active();
        lp_state_req = Nop;
        peer_send(RDI_DISABLE_REQ);
        wait_msg_sent(RDI_DISABLE_RSP, seen);
        check(seen, "TC-11.2 RX message processed -> DISABLE_RSP sent");
        wait_state(Disabled);
    endtask

    // ==================================================================
    // TG-12 : signal transition detector
    // ------------------------------------------------------------------
    task automatic tg12_sig_trans();
        banner("TG-12 signal transition detector");

        // TC-12.1 : pl_state_sts only updates after the clk handshake.
        // Disable auto clk-ack so the state change is held off.
        do_reset();
        seq_reset_to_active();             // get to Active first
        auto_clk_ack = 0;
        lp_state_req = Retrain;            // request a transition
        tick(40);
        check(pl_state_sts === Active,
              "TC-12.1 pl_state_sts frozen while clk handshake stalled");
        check(pl_clk_req === 1'b1,
              "TC-12.1 pl_clk_req asserted waiting for ack");
        auto_clk_ack = 1;                  // release the handshake
        wait_state(Retrain);
        check(pl_state_sts === Retrain, "TC-12.1 transition completes after ack");
    endtask

    // ==================================================================
    // TG-13 : status decoder
    // ------------------------------------------------------------------
    task automatic tg13_decoder();
        banner("TG-13 status decoder");
        do_reset();
        sts_10to7  = 4'h3;   // pl_lnk_cfg   = 3
        sts_17to11 = 4'h5;   // pl_speedmode = 5
        cap_7to4   = 4'h7;   // pl_max_speedmode = (7>5) = 1
        tick(2);
        check(pl_lnk_cfg      === 3'h3, "TC-13.1 pl_lnk_cfg decode");
        check(pl_speedmode    === 3'h5, "TC-13.1 pl_speedmode decode");
        check(pl_max_speedmode === 1'b1, "TC-13.1 pl_max_speedmode decode");

        cap_7to4 = 4'h2;     // 2 > 5 -> 0
        tick(2);
        check(pl_max_speedmode === 1'b0, "TC-13.2 pl_max_speedmode low encoding");
        check(!$isunknown(pl_speedmode), "TC-13.2 no X on pl_speedmode");
    endtask

    // ==================================================================
    // TG-14 : timer (via PMNAK 1us and LinkError 16ms behaviour)
    // ------------------------------------------------------------------
    task automatic tg14_timers();
        int c;
        banner("TG-14 timers");

        // 1us : peer-initiated L1 with no adapter follow-up -> PMNAK_RSP
        // sent after ~1us, leaving the DUT in Active (it NAKs the peer).
        do_reset(); seq_reset_to_active();
        peer_en = 0;                       // drive the peer manually
        peer_send(RDI_L1_REQ);             // peer asks for L1
        // adapter does NOT request L1 -> DUT should NAK after 1us
        begin
            bit seen;
            wait_msg_sent(RDI_PMNAK_RSP, seen, 200);
            check(seen, "TC-14.1 PMNAK_RSP sent ~1us after unmatched L1 REQ");
        end
        peer_en = 1;
        expect_stable(Active, 10);
        check(pl_state_sts === Active, "TC-14.1 remains Active after NAK");
    endtask

    // ==================================================================
    // TG-15 : error / corner cases
    // ------------------------------------------------------------------
    task automatic tg15_corner();
        banner("TG-15 corner cases");

        // TC-15.4 : link error takes precedence over a Retrain request
        do_reset(); seq_reset_to_active();
        lp_linkerror = 1;
        lp_state_req = Retrain;
        wait_state(LinkError);
        check(pl_state_sts === LinkError, "TC-15.4 LinkError precedence over Retrain");

        // TC-15.5 : pl_error ignored outside Active
        do_reset();
        pl_error = 1;
        expect_stable(Reset, 20);
        check(pl_state_sts === Reset, "TC-15.5 pl_error ignored in Reset");
        pl_error = 0;

        // TC-15.6 : single-cycle reset still takes effect
        do_reset(); seq_reset_to_active();
        rst_n = 0; @(negedge lclk); rst_n = 1;
        tick(2);
        check(pl_state_sts === Reset, "TC-15.6 1-cycle reset still resets");
    endtask

    // ==================================================================
    // Illegal-transition tests (a representative subset of TC-ILL)
    // ------------------------------------------------------------------
    // Full illegal/ignored-request set per UCIe spec Table 10-4.
    // (Each entry that the table marks "Ignore" must produce no state change.)
    task automatic test_illegal();
        bit seen;
        banner("TC-ILL illegal / ignored transitions (Table 10-4)");

        // ---- Reset column : L1/Retrain/L2 are Ignore ----
        // TC-ILL-01 : Reset + L1 -> stays Reset
        do_reset(); state_sts = LINKINIT; lp_state_req = L_1;
        expect_stable(Reset, 30);
        check(pl_state_sts === Reset, "TC-ILL-01 Reset ignores L1");

        // TC-ILL-02 : Reset + L2 -> stays Reset
        do_reset(); state_sts = LINKINIT; lp_state_req = L_2;
        expect_stable(Reset, 30);
        check(pl_state_sts === Reset, "TC-ILL-02 Reset ignores L2");

        // TC-ILL-03 : Reset + Retrain -> stays Reset
        do_reset(); state_sts = LINKINIT; lp_state_req = Retrain;
        expect_stable(Reset, 30);
        check(pl_state_sts === Reset, "TC-ILL-03 Reset ignores Retrain");

        // ---- Active column : NOP is Ignore ----
        // TC-ILL-04 : Active + NOP -> stays Active
        do_reset(); seq_reset_to_active();
        lp_state_req = Nop;
        expect_stable(Active, 30);
        check(pl_state_sts === Active, "TC-ILL-04 Active ignores NOP");

        // ---- L1 column : L2/Retrain are Ignore (LinkReset is *considered*) ----
        // TC-ILL-05 : L1 + L2 -> stays L1
        do_reset(); seq_reset_to_active(); seq_active_to_l1();
        lp_state_req = L_2;
        expect_stable(L_1, 30);
        check(pl_state_sts === L_1, "TC-ILL-05 L1 ignores L2");

        // TC-ILL-06 : L1 + Retrain -> stays L1
        do_reset(); seq_reset_to_active(); seq_active_to_l1();
        lp_state_req = Retrain;
        expect_stable(L_1, 30);
        check(pl_state_sts === L_1, "TC-ILL-06 L1 ignores Retrain");

        // TC-ILL-07 : L1 + LinkReset -> LinkReset.  NOTE: the verification plan
        // listed this as "Ignore", but UCIe Table 10-4 marks LinkReset as
        // *considered* (Yes) in the L1 state, so this is a LEGAL transition and
        // the RTL is correct.
        do_reset(); seq_reset_to_active(); seq_active_to_l1();
        lp_state_req = LinkReset;
        wait_state(LinkReset);
        check(pl_state_sts === LinkReset, "TC-ILL-07 L1 + LinkReset -> LinkReset (legal per Table 10-4)");

        // ---- LinkReset column : LinkReset(self) is Ignore ----
        // TC-ILL-08 : LinkReset + LinkReset -> stays LinkReset
        do_reset(); seq_reset_to_active();
        lp_state_req = LinkReset;
        wait_state(LinkReset);
        lp_state_req = LinkReset;            // re-request same state
        expect_stable(LinkReset, 30);
        check(pl_state_sts === LinkReset, "TC-ILL-08 LinkReset ignores LinkReset");

        // ---- Disable column : Disable(self) is Ignore ----
        // TC-ILL-09 : Disabled + Disabled -> stays Disabled
        do_reset(); seq_reset_to_active();
        lp_state_req = Disabled;
        wait_state(Disabled);
        lp_state_req = Disabled;            // re-request same state
        expect_stable(Disabled, 30);
        check(pl_state_sts === Disabled, "TC-ILL-09 Disabled ignores Disabled");

        // ---- LinkError column : L1/L2/Retrain are Ignore ----
        // TC-ILL-10 : LinkError + L1 -> stays LinkError
        do_reset(); seq_reset_to_active();
        lp_linkerror = 1; wait_state(LinkError);
        lp_state_req = L_1;
        expect_stable(LinkError, 30);
        check(pl_state_sts === LinkError, "TC-ILL-10 LinkError ignores L1");

        // TC-ILL-11 : LinkError + L2 -> stays LinkError
        do_reset(); seq_reset_to_active();
        lp_linkerror = 1; wait_state(LinkError);
        lp_state_req = L_2;
        expect_stable(LinkError, 30);
        check(pl_state_sts === LinkError, "TC-ILL-11 LinkError ignores L2");

        // TC-ILL-12 : LinkError + Retrain -> stays LinkError
        do_reset(); seq_reset_to_active();
        lp_linkerror = 1; wait_state(LinkError);
        lp_state_req = Retrain;
        expect_stable(LinkError, 30);
        check(pl_state_sts === LinkError, "TC-ILL-12 LinkError ignores Retrain");

        // ---- Active.PMNAK : no transition to L1/L2 (spec 10.3.3.2) ----
        // TC-ILL-13 : Active.PMNAK + L1 -> stays Active.PMNAK
        do_reset(); seq_reset_to_active();
        peer_pmnak = 1; lp_state_req = L_1;
        wait_state(Active_PMNAK);
        peer_pmnak = 0; lp_state_req = L_1;   // still requesting L1
        expect_stable(Active_PMNAK, 30);
        check(pl_state_sts === Active_PMNAK, "TC-ILL-13 Active.PMNAK ignores L1");

        // TC-ILL-14 : Active.PMNAK + L2 -> stays Active.PMNAK
        do_reset(); seq_reset_to_active();
        peer_pmnak = 1; lp_state_req = L_1;
        wait_state(Active_PMNAK);
        peer_pmnak = 0; lp_state_req = L_2;
        expect_stable(Active_PMNAK, 30);
        check(pl_state_sts === Active_PMNAK, "TC-ILL-14 Active.PMNAK ignores L2");
    endtask

    // ==================================================================
    // TC-TIM : timing-parameter tests (timers observed via hierarchical refs)
    // ------------------------------------------------------------------
    task automatic tctim_timers();
        int n;
        bit seen;
        banner("TC-TIM timing parameters");

        // TC-TIM-01 : 1us PM-wait timer (peer-initiated L1, adapter idle).
        do_reset(); seq_reset_to_active();
        peer_en      = 0;                       // drive the peer manually
        lp_state_req = Nop;
        peer_send(RDI_L1_REQ);                  // DUT -> WAIT, starts the 1us timer
        n = 0; while (!dut.sm.start_time_1us && n < 200) begin @(posedge lclk); n++; end
        check(dut.sm.start_time_1us, "TC-TIM-01 1us timer started");
        n = 0; while (!dut.sm.time_1us && n < 100) begin @(posedge lclk); n++; end
        check(dut.sm.time_1us, "TC-TIM-01 time_1us fired");
        check(n >= CYC_1US-3 && n <= CYC_1US+3,
              $sformatf("TC-TIM-01 1us measured %0d cyc (expect ~%0d)", n, CYC_1US));
        peer_en = 1;

        // TC-TIM-02 : 16ms LinkError residency timer.
        do_reset(); seq_reset_to_active();
        lp_linkerror = 1;
        wait_state(LinkError);
        n = 0; while (!dut.sm.start_time_16ms && n < 500) begin @(posedge lclk); n++; end
        check(dut.sm.start_time_16ms, "TC-TIM-02 16ms timer started");
        n = 0; while (!dut.sm.time_16ms && n < CYC_16MS*2) begin @(posedge lclk); n++; end
        check(dut.sm.time_16ms, "TC-TIM-02 time_16ms fired");
        check(n >= CYC_16MS-32 && n <= CYC_16MS+32,
              $sformatf("TC-TIM-02 16ms measured %0d cyc (expect ~%0d)", n, CYC_16MS));
        lp_linkerror = 0;

        // TC-TIM-03 : clock gating engages within ~1us of stable conditions in
        // L1.  (The gating counter free-runs, so the meaningful guarantee is the
        // bounded gating latency of <=1us, not an exact lower bound.)
        do_reset(); seq_reset_to_active(); seq_active_to_l1();
        lp_state_req = Nop; lp_wake_req = 0;
        // let any L1-entry clk-handshake activity settle
        n = 0; while (pl_clk_req && n < 50) begin @(posedge lclk); n++; end
        // measure cycles from stable conditions until gated
        n = 0; while (dut.gating_logic.GATING_cs !== 1'b1 && n < 4*CYC_1US) begin @(posedge lclk); n++; end
        check(dut.gating_logic.GATING_cs === 1'b1, "TC-TIM-03 gating engaged in stable L1");
        check(n <= CYC_1US + 4, $sformatf("TC-TIM-03 gating within ~1us (took %0d cyc)", n));
        check_gated(1, "TC-TIM-03 lclk_g held gated");

        // TC-TIM-04 : PM retry after a PMNAK.  The RTL has no distinct 2us retry
        // timer; the retry is performed by returning to Active and re-requesting.
        do_reset(); seq_reset_to_active();
        peer_pmnak = 1; lp_state_req = L_1;
        wait_state(Active_PMNAK);
        peer_pmnak = 0; lp_state_req = Active;
        wait_state(Active);
        lp_state_req = L_1;
        wait_msg_sent(RDI_L1_REQ, seen);
        check(seen, "TC-TIM-04 L1 re-requested after PMNAK");
        wait_state(L_1);
        check(pl_state_sts === L_1, "TC-TIM-04 PM retry reaches L1");

        // TC-TIM-05 : 1us timer is abandoned when the request is matched before
        // it fires (adapter requests L1 during WAIT -> no PMNAK, enters L1).
        do_reset(); seq_reset_to_active();
        peer_en = 0; lp_state_req = Nop;
        peer_send(RDI_L1_REQ);                  // DUT -> WAIT, 1us timer running
        n = 0; while (!dut.sm.start_time_1us && n < 200) begin @(posedge lclk); n++; end
        check(dut.sm.start_time_1us, "TC-TIM-05 1us timer running in WAIT");
        tick(CYC_1US/2);                        // well under 1us
        lp_state_req = L_1;                      // adapter matches -> timer reset
        peer_en      = 1;                        // peer completes the L1 entry
        wait_state(L_1);
        check(pl_state_sts === L_1, "TC-TIM-05 entered L1 (no PMNAK) after early match");
    endtask

    // ==================================================================
    // End-to-end scenarios
    // ------------------------------------------------------------------
    task automatic sc01_full_bringup();
        banner("SC-01 full bring-up");
        do_reset();
        seq_reset_to_active();
        check(pl_state_sts === Active, "SC-01 Active reached");
        check(pl_inband_pres === 1'b1, "SC-01 inband_pres asserted");
    endtask

    task automatic sc02_pm_cycle();
        banner("SC-02 Active -> L1 -> Active");
        do_reset(); seq_reset_to_active();
        seq_active_to_l1();
        check(pl_state_sts === L_1, "SC-02 in L1");
        lp_state_req = Active;            // L1 exits via Retrain then Active
        wait_state(Retrain);
        seq_exit_to_active();
        check(pl_state_sts === Active, "SC-02 back to Active");
    endtask

    task automatic sc03_pmnak();
        banner("SC-03 PM abort (PMNAK)");
        do_reset(); seq_reset_to_active();
        peer_pmnak   = 1;
        lp_state_req = L_1;
        wait_state(Active_PMNAK);
        peer_pmnak   = 0;
        lp_state_req = Active;
        wait_state(Active);
        check(pl_state_sts === Active, "SC-03 returns to Active after PMNAK");
    endtask

    task automatic sc04_retrain();
        banner("SC-04 Active -> Retrain -> Active");
        do_reset(); seq_reset_to_active();
        seq_active_to_retrain();
        seq_exit_to_active();
        check(pl_state_sts === Active, "SC-04 round-trip through Retrain");
    endtask

    task automatic sc05_linkerror_recovery();
        banner("SC-05 LinkError recovery");
        do_reset(); seq_reset_to_active();
        seq_linkerror_recovery();
        check(pl_state_sts === Reset, "SC-05 recovered to Reset");
        seq_reset_to_active();
        check(pl_state_sts === Active, "SC-05 re-brought-up to Active");
    endtask

    task automatic sc07_l2_exit();
        banner("SC-07 L2 -> Reset -> Active");
        do_reset(); seq_reset_to_active();
        seq_active_to_l2();
        lp_state_req = Active;
        wait_state(Reset);
        seq_reset_to_active();
        check(pl_state_sts === Active, "SC-07 L2 exit through Reset then Active");
    endtask

    // SC-06 : Active -> Retrain (peer-initiated) -> Active
    task automatic sc06_peer_retrain();
        bit seen;
        banner("SC-06 peer-initiated Retrain -> Active");
        do_reset(); seq_reset_to_active();
        lp_state_req = Nop;                 // adapter idle; retrain is peer-driven
        peer_send(RDI_RETRAIN_REQ);
        wait_msg_sent(RDI_RETRAIN_RSP, seen);
        check(seen, "SC-06 RDI_RETRAIN_RSP sent (stall precedes it - A02)");
        wait_state(Retrain);
        check(pl_state_sts === Retrain, "SC-06 reached Retrain");
        seq_exit_to_active();              // pm_exit==0 : NOP->Active path
        check(pl_state_sts === Active, "SC-06 back to Active");
    endtask

    // SC-08 : Active.PMNAK -> Retrain (Retrain requested during PMNAK)
    task automatic sc08_pmnak_retrain();
        bit seen;
        banner("SC-08 Active.PMNAK -> Retrain");
        do_reset(); seq_reset_to_active();
        peer_pmnak   = 1;
        lp_state_req = L_1;
        wait_state(Active_PMNAK);
        check(pl_state_sts === Active_PMNAK, "SC-08 in Active_PMNAK");
        peer_pmnak   = 0;
        lp_state_req = Retrain;            // interrupt PMNAK with a Retrain request
        wait_msg_sent(RDI_RETRAIN_REQ, seen);
        check(seen, "SC-08 RDI_RETRAIN_REQ from Active_PMNAK");
        wait_state(Retrain);
        check(pl_state_sts === Retrain, "SC-08 Active_PMNAK -> Retrain");
    endtask

    // SC-10 : clock gating during L1 with a wake interrupt and re-gating
    task automatic sc10_gating_wake();
        int c;
        banner("SC-10 gating in L1 with wake interrupt");
        do_reset(); seq_reset_to_active(); seq_active_to_l1();
        lp_state_req = Nop;
        lp_wake_req  = 0;
        tick(3 * CYC_1US);
        check_gated(1, "SC-10 lclk_g gated in L1 after 1us");

        // wake interrupt ungates immediately
        lp_wake_req = 1;
        tick(2);
        check_gated(0, "SC-10 wake ungates lclk_g");
        c = 0;
        while (!pl_wake_ack && c < 200) begin @(posedge lclk); c++; end
        check(pl_wake_ack === 1'b1, "SC-10 pl_wake_ack asserts");

        // hold lp_wake_req past pl_wake_ack (spec: de-assert only after ack),
        // then drop it -> ack clears, gating re-evaluates and re-gates
        tick(2);
        lp_wake_req = 0;
        tick(3);
        check(pl_wake_ack === 1'b0, "SC-10 pl_wake_ack clears after wake drops");
        tick(3 * CYC_1US);
        check_gated(1, "SC-10 re-gates after wake released");
    endtask

    task automatic sc09_stress();
        banner("SC-09 stress (repeat cycles)");
        for (int i = 0; i < 3; i++) begin
            do_reset();
            seq_reset_to_active();
            check(pl_state_sts === Active, $sformatf("SC-09 cycle %0d bring-up", i));
            seq_active_to_retrain();
            seq_exit_to_active();
            check(pl_state_sts === Active, $sformatf("SC-09 cycle %0d retrain rt", i));
        end
    endtask

    // ==================================================================
    // Main
    // ------------------------------------------------------------------
    initial begin
        cov_state = new();
        cov_tx    = new();
        cov_rx    = new();

        init_inputs();
        rst_n = 0;
        tick(5);

        tg01_reset();
        tg02_bringup();
        tg03_retrain();
        tg04_pm();
        tg05_l1l2();
        tg06_linkreset();
        tg07_linkerror();
        tg08_disabled();
        tg09_handshakes();
        tg10_gating();
        tg11_msg_handler();
        tg12_sig_trans();
        tg13_decoder();
        tg14_timers();
        tg15_corner();
        test_illegal();
        tctim_timers();

        sc01_full_bringup();
        sc02_pm_cycle();
        sc03_pmnak();
        sc04_retrain();
        sc05_linkerror_recovery();
        sc06_peer_retrain();
        sc07_l2_exit();
        sc08_pmnak_retrain();
        sc10_gating_wake();
        sc09_stress();

        // ----------------------------------------------------------------
        $display("\n========================================================");
        $display("RDI_SM_tb summary : checks=%0d  failures=%0d  state_cov=%.1f%%",
                 checks_run, checks_fail, cov_state.get_inst_coverage());
        if (checks_fail == 0)
            $display("RESULT: PASS");
        else
            $display("RESULT: FAIL (%0d failing checks)", checks_fail);
        $display("========================================================\n");
        $finish;
    end

    // Global watchdog.
    initial begin
        #(CLK_PERIOD * 5_000_000);
        $error("GLOBAL TIMEOUT - simulation did not finish");
        $finish;
    end

endmodule
