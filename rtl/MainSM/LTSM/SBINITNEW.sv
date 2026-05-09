module SBINITNEW

import UCIe_pkg::*;

#( parameter int CLK_FRQ_HZ = 800000000)
 ( 
    input logic clk,
    input logic rst_n,
    
    //Signal FROM TOP LTSM.
    input logic sbinit_enable,
    
    //Signal TO TOP LTSM.
    output logic sbinit_done,
    output logic sbinit_error,

    //====================
    //Signals from SB block.
        //MESSAGES signals.
    input logic    sb_rx_valid,
    input msg_no_e sb_rx_msg_id,
        //Control signals.
    input logic four_iteration_done,    // New: 4 iteration request done signal.
    input logic sb_det_pattern_rcvd,    // state S1: Detected pattern received from SB block.
    
    //====================
    //Signals to SB block.  
        //MESSAGES signals.
    output logic    sb_tx_valid,
    output msg_no_e sb_tx_msg_id,
        //NEW signal.
    output logic sbinit_pattern_mode,    // New:
    output logic sb_det_pattern_req,     // state S1: Request signal to SB block to start sending the pattern for detection.
    output logic send_4_iteration,       // New: send 4 iteration request to SB block.

    //====================
    // Sideband FIFO ready signal (write-side handshake).
    // High  => FIFO has space, message was accepted.
    // Low   => FIFO is full, push was ignored.
    input  logic ltsm_rdy,

    //====================
    // Timer signals.
    output logic sbinit_timer_enable,
    input  logic sbinit_timeout_expired

 );  
  
//=====================================================  
// -------------------------------------------------------
// STATE ENCODING
// -------------------------------------------------------
// S3 (Out-of-Reset) keeps sending continuously until the
// partner's Out-of-Reset is received – identical to the
// original design.
//
// S4 (done_req / done_resp) IS split into _SEND / _WAIT
// to guarantee the FIFO accepted the push before we start
// waiting for the partner's response:
//   _SEND : drives sb_tx_valid=1 until ltsm_rdy=1.
//   _WAIT : message confirmed in FIFO; wait for partner.
// -------------------------------------------------------
typedef enum logic [4:0]{
    SB_S0_IDLE,

    SB_S1_DET_PATTERN,      // send det-pattern req, wait for pattern received

    SB_S2_LINK_SYNCH,       // send 4-iteration, wait for done

    // S3 – Out-of-Reset (continuous TX, single state)
    SB_S3_OUT_OF_RESET,     // keep sending Out-of-Reset until partner replies

    // S4 – Completion-Request handshake (split)
    SB_S4_REQ_SEND,         // drive done_req msg until FIFO accepts (ltsm_rdy=1)
    SB_S4_REQ_WAIT,         // msg confirmed; wait for partner's done_req

    // S4 – Completion-Response handshake (split)
    SB_S4_RSP_SEND,         // drive done_resp msg until FIFO accepts
    SB_S4_RSP_WAIT,         // msg confirmed; wait for partner's done_resp

    SB_S5_ERROR,

    SB_S6_DONE

} sb_state_e;

sb_state_e current_state , next_state ;

//=====================================================
//===================  Timer  =========================
//=====================================================
logic sbinit_timeout_error;
assign sbinit_timeout_error = sbinit_timeout_expired && !sbinit_done ;
assign sbinit_timer_enable  = sbinit_enable && !sbinit_done && !sbinit_error;

// Internal 1-ms-tick generator (used in S1)
localparam int MS_CYCLES = CLK_FRQ_HZ / 1000;
logic [$clog2(MS_CYCLES)-1:0] cycle_cnt;
logic [3:0] ms_cnt;

logic pattern_rcvd_sticky;
logic one_ms_timer_toggle;
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cycle_cnt           <= 0;
        one_ms_timer_toggle <= 1'b0;
    end else if (current_state == SB_S1_DET_PATTERN) begin
        if (cycle_cnt == MS_CYCLES - 1) begin
            cycle_cnt           <= 0;
            one_ms_timer_toggle <= ~one_ms_timer_toggle;
        end else begin
            cycle_cnt <= cycle_cnt + 1;
        end
    end else begin
        cycle_cnt           <= 0;
        one_ms_timer_toggle <= 1'b0;
    end
end

//=====================================================
//================= RX handshake logic ================
//=====================================================

// ---------- S3: Out-of-Reset received (continuous TX state) ----------
logic out_of_reset_msg_rcvd ;
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        out_of_reset_msg_rcvd <= 1'b0;
    else if(sb_rx_valid && sb_rx_msg_id == SBINIT_Out_of_Reset)
        out_of_reset_msg_rcvd <= 1'b1;
    else if(current_state != SB_S3_OUT_OF_RESET)
        out_of_reset_msg_rcvd <= 1'b0;
end

// ---------- S4-REQ-WAIT: done_req received ----------
logic done_req_rcvd;
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        done_req_rcvd <= 1'b0;
    else if(sb_rx_valid && sb_rx_msg_id == SBINIT_done_req)
        done_req_rcvd <= 1'b1;
    else if(current_state != SB_S4_REQ_WAIT)
        done_req_rcvd <= 1'b0;
end

// ---------- S4-RSP-WAIT: done_resp received ----------
logic done_rsp_rcvd;
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        done_rsp_rcvd <= 1'b0;
    else if(sb_rx_valid && sb_rx_msg_id == SBINIT_done_resp)
        done_rsp_rcvd <= 1'b1;
    else if(current_state != SB_S4_RSP_WAIT)
        done_rsp_rcvd <= 1'b0;
end

// ---------- S1: pattern-received sticky ----------
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        pattern_rcvd_sticky <= 1'b0;
    else if (sb_det_pattern_rcvd)
        pattern_rcvd_sticky <= 1'b1;
    else if (current_state != SB_S1_DET_PATTERN)
        pattern_rcvd_sticky <= 1'b0;
end

//=====================================================
//============ State register logic =================
//=====================================================
always_ff @( posedge clk , negedge rst_n ) begin
    if(!rst_n)
        current_state <= SB_S0_IDLE ;
    else
        current_state <= next_state ;
end

//=====================================================
//============ State transition logic =================
//=====================================================
always_comb begin
    next_state = current_state ;

    case(current_state)
        // ------------------------------------------------------------------
        SB_S0_IDLE: begin
            if(sbinit_enable)
                next_state = SB_S1_DET_PATTERN ;
        end

        // ------------------------------------------------------------------
        // S1 – Detection pattern
        // ------------------------------------------------------------------
        SB_S1_DET_PATTERN: begin
            if(!sbinit_enable)
                next_state = SB_S0_IDLE ;
            else if(sbinit_timeout_error)
                next_state = SB_S5_ERROR ;
            else if(sb_det_pattern_rcvd)
                next_state = SB_S2_LINK_SYNCH ;
        end

        // ------------------------------------------------------------------
        // S2 – Link Synchronisation (4 iterations – no direct TX message)
        // ------------------------------------------------------------------
        SB_S2_LINK_SYNCH: begin
            if(!sbinit_enable)
                next_state = SB_S0_IDLE ;
            else if(sbinit_timeout_error)
                next_state = SB_S5_ERROR ;
            else if(four_iteration_done)
                next_state = SB_S3_OUT_OF_RESET ;
        end

        // ------------------------------------------------------------------
        // S3 – Out-of-Reset (single state, continuous TX)
        // Keeps sending SBINIT_Out_of_Reset every cycle until the partner
        // sends its own Out-of-Reset back.
        // ------------------------------------------------------------------
        SB_S3_OUT_OF_RESET: begin
            if(!sbinit_enable)
                next_state = SB_S0_IDLE ;
            else if(sbinit_timeout_error)
                next_state = SB_S5_ERROR ;
            else if(out_of_reset_msg_rcvd)
                next_state = SB_S4_REQ_SEND ;
        end

        // ------------------------------------------------------------------
        // S4 – Completion Request
        // _SEND: keep driving until FIFO accepts
        // _WAIT: wait for partner's done_req
        // ------------------------------------------------------------------
        SB_S4_REQ_SEND: begin
            if(!sbinit_enable)
                next_state = SB_S0_IDLE ;
            else if(sbinit_timeout_error)
                next_state = SB_S5_ERROR ;
            else if(ltsm_rdy)
                next_state = SB_S4_REQ_WAIT ;
        end

        SB_S4_REQ_WAIT: begin
            if(!sbinit_enable)
                next_state = SB_S0_IDLE ;
            else if(sbinit_timeout_error)
                next_state = SB_S5_ERROR ;
            else if(done_req_rcvd)
                next_state = SB_S4_RSP_SEND ;
        end

        // ------------------------------------------------------------------
        // S4 – Completion Response
        // _SEND: keep driving until FIFO accepts
        // _WAIT: wait for partner's done_resp
        // ------------------------------------------------------------------
        SB_S4_RSP_SEND: begin
            if(!sbinit_enable)
                next_state = SB_S0_IDLE ;
            else if(sbinit_timeout_error)
                next_state = SB_S5_ERROR ;
            else if(ltsm_rdy)
                next_state = SB_S4_RSP_WAIT ;
        end

        SB_S4_RSP_WAIT: begin
            if(!sbinit_enable)
                next_state = SB_S0_IDLE ;
            else if(sbinit_timeout_error)
                next_state = SB_S5_ERROR ;
            else if(done_rsp_rcvd)
                next_state = SB_S6_DONE ;
        end

        // ------------------------------------------------------------------
        SB_S6_DONE: begin
            if(!sbinit_enable)
                next_state = SB_S0_IDLE ;
        end

        SB_S5_ERROR: begin
            if(!sbinit_enable)
                next_state = SB_S0_IDLE ;
        end

        default: next_state = SB_S0_IDLE ;
    endcase
end

//=====================================================
//===================  OUTPUT  ========================
//=====================================================
always_comb begin
    // safe defaults
    sb_tx_msg_id        = msg_no_e'(NOTHING) ;
    sb_tx_valid         = 1'b0 ;
    sb_det_pattern_req  = 1'b0;
    send_4_iteration    = 1'b0;
    sbinit_pattern_mode = 1'b0;
        
    case(current_state)

        SB_S0_IDLE: begin
            sbinit_pattern_mode = sbinit_enable;
        end

        // ---- S1 ----
        SB_S1_DET_PATTERN: begin
            // Request the pattern engine every 1 ms as long as we haven't
            // received the pattern yet.
            sb_det_pattern_req  = (sbinit_enable
                                   && one_ms_timer_toggle
                                   && (next_state == SB_S1_DET_PATTERN)
                                   && !pattern_rcvd_sticky);
            sbinit_pattern_mode = 1'b1;
        end

        // ---- S2 ----
        SB_S2_LINK_SYNCH: begin
            send_4_iteration    = 1'b1;
            sbinit_pattern_mode = 1'b1;
        end

        // ---- S3 – Out-of-Reset (continuous TX) ----
        // Keeps asserting the message every cycle.
        // Transition happens only when the partner's reply is received,
        // not on ltsm_rdy (mirroring the original SBINIT.sv behaviour).
        SB_S3_OUT_OF_RESET: begin
            sb_tx_valid  = 1'b1 ;
            sb_tx_msg_id = SBINIT_Out_of_Reset ;
        end

        // ---- S4 REQ SEND ----
        SB_S4_REQ_SEND: begin
            sb_tx_valid  = 1'b1 ;
            sb_tx_msg_id = SBINIT_done_req ;
        end

        // ---- S4 REQ WAIT ----
        SB_S4_REQ_WAIT: begin
            sb_tx_valid  = 1'b0 ;
            sb_tx_msg_id = msg_no_e'(NOTHING) ;
        end

        // ---- S4 RSP SEND ----
        SB_S4_RSP_SEND: begin
            sb_tx_valid  = 1'b1 ;
            sb_tx_msg_id = SBINIT_done_resp ;
        end

        // ---- S4 RSP WAIT ----
        SB_S4_RSP_WAIT: begin
            sb_tx_valid  = 1'b0 ;
            sb_tx_msg_id = msg_no_e'(NOTHING) ;
        end

        default: begin
            sb_tx_msg_id        = msg_no_e'(NOTHING) ;
            sb_tx_valid         = 1'b0 ;
            sb_det_pattern_req  = 1'b0;
            send_4_iteration    = 1'b0;
        end
    endcase
end

//=====================================================
//====================  DONE  =========================
//=====================================================
always_comb begin
    sbinit_done = (current_state == SB_S6_DONE);
end

//=====================================================
//====================  ERROR  ========================
//=====================================================
always_comb begin
    sbinit_error = (current_state == SB_S5_ERROR);
end

endmodule
