// UCIe 3.0 §4.5.3.2 SBINIT state (Standard Package flow, Steps 1-8).
//
// Mgmt-Transport-protocol branch and its retry-N rules are intentionally
// not implemented (project does not support Mgmt Transport).
//
// MB tri-state / SB Tx hold-low / SB Rx enable are hard-wired by the top
// LTSM module; not driven from here.

module SBINIT
    import UCIe_pkg::*;
#(
    parameter int CLK_FRQ_HZ = 800000000
) (
    input  logic    clk,
    input  logic    rst_n,

    // ---- Top LTSM ----
    input  logic    sbinit_enable,
    output logic    sbinit_done,
    output logic    sbinit_error,

    // ---- From SB block ----
    input  logic    sb_rx_valid,
    input  msg_no_e sb_rx_msg_id,
    input  logic    iter_done,            // pulse: SB finished req_iter_count pattern iterations
    input  logic    sb_det_pattern_rcvd,  // SB raised on 128-UI clock pattern detected

    // ---- To SB block ----
    output logic       sb_tx_valid,
    output msg_no_e    sb_tx_msg_id,
    output logic       sbinit_pattern_mode, // 1 while in pattern detect / emit phases
    output logic       sb_det_pattern_req,  // 1ms/1ms duty: 1 = SB emits pattern, 0 = hold low
    output logic [2:0] req_iter_count,      // # of post-detection iterations SB must send (= 3'd4 for SP Step 4)

    // ---- SB FIFO handshake ----
    input  logic    ltsm_rdy,             // 1 = SB FIFO accepted our tx

    // ---- Timer (8 ms watchdog) ----
    output logic    sbinit_timer_enable,
    input  logic    sbinit_timeout_expired
);

    // ---------------- States ----------------
    typedef enum logic [2:0] {
        SB_S0_IDLE,
        SB_S1_DET_PATTERN,    // Steps 1-3 / 5: send pattern in 1ms/1ms duty; wait for detect
        SB_S2_LINK_SYNCH,     // Step 4: 4 more pattern iterations, then enable msg tx/rx
        SB_S3_OUT_OF_RESET,   // Steps 6-7: send {Out of Reset} until received
        SB_S4_DONE_HANDSHAKE, // Step 8: send done_req; respond to partner done_req with done_resp
        SB_S5_ERROR,          // 8 ms timeout -> TRAINERROR
        SB_S6_DONE            // Exit -> MBINIT
    } sb_state_e;

    sb_state_e current_state, next_state;

    // ---------------- Outer watchdog wiring ----------------
    logic sbinit_timeout_error;
    assign sbinit_timeout_error = sbinit_timeout_expired && !sbinit_done;
    assign sbinit_timer_enable  = sbinit_enable && !sbinit_done && !sbinit_error;

    // ---------------- 1 ms toggle for pattern duty cycle (Step 5) ----------------
    localparam int MS_CYCLES = CLK_FRQ_HZ / 1000;
    logic [$clog2(MS_CYCLES)-1:0] cycle_cnt;
    logic                         one_ms_toggle;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_cnt     <= '0;
            one_ms_toggle <= 1'b0;
        end else if (current_state == SB_S1_DET_PATTERN) begin
            if (cycle_cnt == MS_CYCLES - 1) begin
                cycle_cnt     <= '0;
                one_ms_toggle <= ~one_ms_toggle;
            end else begin
                cycle_cnt <= cycle_cnt + 1'b1;
            end
        end else begin
            cycle_cnt     <= '0;
            one_ms_toggle <= 1'b0;
        end
    end

    // Pattern-detected sticky.
    logic pattern_rcvd_sticky;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pattern_rcvd_sticky <= 1'b0;
        else if (current_state == SB_S0_IDLE)
            pattern_rcvd_sticky <= 1'b0;
        else if (sb_det_pattern_rcvd)
            pattern_rcvd_sticky <= 1'b1;
    end

    // ---------------- RX message stickies ----------------
    logic out_of_reset_rcvd;
    logic done_req_rcvd;
    logic done_resp_rcvd;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_of_reset_rcvd <= 1'b0;
            done_req_rcvd     <= 1'b0;
            done_resp_rcvd    <= 1'b0;
        end else if (current_state == SB_S0_IDLE) begin
            out_of_reset_rcvd <= 1'b0;
            done_req_rcvd     <= 1'b0;
            done_resp_rcvd    <= 1'b0;
        end else if (sb_rx_valid) begin
            unique case (sb_rx_msg_id)
                SBINIT_Out_of_Reset : out_of_reset_rcvd <= 1'b1;
                SBINIT_done_req     : done_req_rcvd     <= 1'b1;
                SBINIT_done_resp    : done_resp_rcvd    <= 1'b1;
                default             : ;
            endcase
        end
    end

    // ---------------- S4 TX-side stickies (deadlock-free Step 8) ----------------
    // done_req_sent  : our SBINIT_done_req  was accepted by SB FIFO (ltsm_rdy seen).
    // done_resp_sent : our SBINIT_done_resp was accepted by SB FIFO.
    logic done_req_sent;
    logic done_resp_sent;
    logic sending_done_req;   // combinational: we are driving done_req  this cycle
    logic sending_done_resp;  // combinational: we are driving done_resp this cycle

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            done_req_sent  <= 1'b0;
            done_resp_sent <= 1'b0;
        end else if (current_state == SB_S0_IDLE) begin
            done_req_sent  <= 1'b0;
            done_resp_sent <= 1'b0;
        end else begin
            if (sending_done_req  && ltsm_rdy) done_req_sent  <= 1'b1;
            if (sending_done_resp && ltsm_rdy) done_resp_sent <= 1'b1;
        end
    end

    // ---------------- State register ----------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            current_state <= SB_S0_IDLE;
        else
            current_state <= next_state;
    end

    // ---------------- Next state ----------------
    always_comb begin
        next_state = current_state;

        if (!sbinit_enable) begin
            next_state = SB_S0_IDLE;
        end else if (sbinit_timeout_error) begin
            next_state = SB_S5_ERROR;
        end else begin
            case (current_state)
                SB_S0_IDLE          : next_state = SB_S1_DET_PATTERN;

                SB_S1_DET_PATTERN   : if (pattern_rcvd_sticky)
                                          next_state = SB_S2_LINK_SYNCH;

                SB_S2_LINK_SYNCH    : if (iter_done)
                                          next_state = SB_S3_OUT_OF_RESET;

                SB_S3_OUT_OF_RESET  : if (out_of_reset_rcvd)
                                          next_state = SB_S4_DONE_HANDSHAKE;

                SB_S4_DONE_HANDSHAKE: if (done_req_sent  && done_resp_sent &&
                                          done_req_rcvd  && done_resp_rcvd)
                                          next_state = SB_S6_DONE;

                SB_S5_ERROR         : ;  // sink until enable drops
                SB_S6_DONE          : ;  // sink until enable drops
                default             : next_state = SB_S0_IDLE;
            endcase
        end
    end

    // ---------------- Outputs ----------------
    always_comb begin
        sb_tx_msg_id        = msg_no_e'(NOTHING);
        sb_tx_valid         = 1'b0;
        sb_det_pattern_req  = 1'b0;
        sbinit_pattern_mode = 1'b0;
        req_iter_count      = 3'd0;
        sending_done_req    = 1'b0;
        sending_done_resp   = 1'b0;

        case (current_state)
            SB_S1_DET_PATTERN: begin
                // Spec Step 5: 1 ms send pattern / 1 ms hold low (level encoding to SB).
                sb_det_pattern_req  = one_ms_toggle && !pattern_rcvd_sticky;
                sbinit_pattern_mode = 1'b1;
            end

            SB_S2_LINK_SYNCH: begin
                // Spec Step 4: emit 4 more pattern iterations, then enable msg tx/rx.
                req_iter_count      = 3'd4;
                sbinit_pattern_mode = 1'b1;
            end

            SB_S3_OUT_OF_RESET: begin
                // Spec Steps 6-7: send {Out of Reset} continuously until partner echoes back.
                sb_tx_valid  = 1'b1;
                sb_tx_msg_id = SBINIT_Out_of_Reset;
            end

            SB_S4_DONE_HANDSHAKE: begin
                // Spec Step 8: independent send-our-req and react-to-partner-req paths.
                //  - First: drive our done_req until FIFO accepts.
                //  - Once partner's done_req has arrived: drive our done_resp until FIFO accepts.
                // Exit when both ours are sent AND both partner's are received.
                if (!done_req_sent) begin
                    sb_tx_valid      = 1'b1;
                    sb_tx_msg_id     = SBINIT_done_req;
                    sending_done_req = 1'b1;
                end else if (done_req_rcvd && !done_resp_sent) begin
                    sb_tx_valid       = 1'b1;
                    sb_tx_msg_id      = SBINIT_done_resp;
                    sending_done_resp = 1'b1;
                end
            end

            default: ; // safe defaults already assigned above
        endcase
    end

    assign sbinit_done  = (current_state == SB_S6_DONE);
    assign sbinit_error = (current_state == SB_S5_ERROR);

endmodule
