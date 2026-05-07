module SBINIT

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
    output logic sbinit_pattern_mode,     // New:
    output logic sb_det_pattern_req,     // state S1: Request signal to SB block to start sending the pattern for detection.
    output logic send_4_iteration,        // New: send 4 iteration request to SB block.

    //====================
    // Timer signals.
    output logic sbinit_timer_enable,
    input  logic sbinit_timeout_expired

 );  
  
//=====================================================  
typedef enum logic [3:0]{
    SB_S0_IDLE,
    
    SB_S1_DET_PATTERN,
    
    SB_S2_LINK_SYNCH,

    SB_S3_OUT_OF_RESET,

    SB_S4_COMPLETION_REQ,
    SB_S4_COMPLETION_RSP,

    SB_S5_DONE

      } sb_state_e;

sb_state_e current_state , next_state ;

//=====================================================
//===================  Timer  =========================
//=====================================================
logic sbinit_timeout_error;
assign sbinit_timeout_error = sbinit_timeout_expired && !sbinit_done ;
assign sbinit_timer_enable = sbinit_enable && !sbinit_done && !sbinit_error;

// Internal 8ms timer with 1ms granularity
localparam int MS_CYCLES = CLK_FRQ_HZ / 1000;
logic [$clog2(MS_CYCLES)-1:0] cycle_cnt;
logic [3:0] ms_cnt;

logic pattern_rcvd_sticky;
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cycle_cnt <= 0;
        ms_cnt <= 0;
    end else if (current_state == SB_S1_DET_PATTERN) begin
        // Count only while in S1 AND pattern has NOT been received
        if (cycle_cnt == MS_CYCLES - 1) begin
            cycle_cnt <= 0;
            if (ms_cnt < 8)
                ms_cnt <= ms_cnt + 1;
        end else begin
            cycle_cnt <= cycle_cnt + 1;
        end
    end else if (current_state != SB_S1_DET_PATTERN) begin
        // Reset counters when leaving S1
        cycle_cnt <= 0;
        ms_cnt    <= 0;
    end
    // else: in S1 with pattern_rcvd_sticky=1 -> hold counts frozen
end

logic sbinit_1ms_timeout_error;
assign sbinit_1ms_timeout_error = ((current_state == SB_S1_DET_PATTERN) && (ms_cnt == 8));
//=====================================================
//================= Handshake =========================
//=====================================================

//===================== S3 handshake logic =============================
//==================== SENT =========================
logic out_of_reset_msg_sent ;
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        out_of_reset_msg_sent <= 1'b0;
    end
    else if(current_state == SB_S3_OUT_OF_RESET)begin
        out_of_reset_msg_sent <= 1'b1;
    end
    else if(current_state != SB_S3_OUT_OF_RESET)begin
        out_of_reset_msg_sent <= 1'b0;
    end
end
//==================== RCVD =========================
logic out_of_reset_msg_rcvd ;
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        out_of_reset_msg_rcvd <= 1'b0;
    end
    else if(current_state != SB_S3_OUT_OF_RESET)begin
        out_of_reset_msg_rcvd <= 1'b0;
    end
    else if( sb_rx_valid && sb_rx_msg_id == SBINIT_Out_of_Reset)begin
        out_of_reset_msg_rcvd <= 1'b1;
    end
end

//===================== S4 handshake logic =============================
//==================== SENT =========================
logic done_req_rcvd ;  
always_ff @(posedge clk , negedge rst_n) begin
    if(!rst_n)begin
        done_req_rcvd <= 1'b0;
    end
    else if(current_state == SB_S4_COMPLETION_REQ && sb_rx_valid && sb_rx_msg_id == SBINIT_done_req)begin
        done_req_rcvd <= 1'b1 ;
    end
    else if(current_state != SB_S4_COMPLETION_REQ)begin
        done_req_rcvd <= 1'b0 ;
    end
end
//==================== RCVD =========================
logic done_rsp_rcvd ;
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        done_rsp_rcvd <= 1'b0;
    end
    else if(current_state == SB_S4_COMPLETION_RSP && sb_rx_valid && sb_rx_msg_id == SBINIT_done_resp)begin
        done_rsp_rcvd <= 1'b1;
    end
    else if(current_state != SB_S4_COMPLETION_RSP)begin
        done_rsp_rcvd <= 1'b0;
    end
end
//=====================================================
//=================== PATTERN =========================
//=====================================================
assign sbinit_pattern_mode = ((current_state == SB_S0_IDLE && sbinit_enable) ||
                              (current_state == SB_S1_DET_PATTERN) || 
                              (current_state == SB_S2_LINK_SYNCH));

// Sticky bit: latch when sb_det_pattern_rcvd arrives in S1, clear when leaving S1.
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        pattern_rcvd_sticky <= 1'b0;
    else if (current_state != SB_S1_DET_PATTERN)
        pattern_rcvd_sticky <= 1'b0;
    else if (sb_det_pattern_rcvd)
        pattern_rcvd_sticky <= 1'b1;
end

//=====================================================
//================ STATE ENTRIES ======================
//=====================================================
logic s1_entry;
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        s1_entry <= 0;
    end
    else begin
        s1_entry <= (current_state != SB_S1_DET_PATTERN) && (next_state == SB_S1_DET_PATTERN);
    end
end
//===================== S1 ===========================
logic s2_entry;
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        s2_entry <= 0;
    end
    else begin
        s2_entry <= (current_state != SB_S2_LINK_SYNCH) && (next_state == SB_S2_LINK_SYNCH);
    end
end
//===================== S2 ===========================
logic s3_entry;
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        s3_entry <= 0;
    end
    else begin
        s3_entry <= (current_state != SB_S3_OUT_OF_RESET) && (next_state == SB_S3_OUT_OF_RESET);
    end
end
//===================== S4_Req =======================
logic s4_req_entry;
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        s4_req_entry <= 0;
    end
    else begin
        s4_req_entry <= (current_state != SB_S4_COMPLETION_REQ) && (next_state == SB_S4_COMPLETION_REQ);
    end
end
//===================== S4_Rsp =====================
logic s4_rsp_entry;
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        s4_rsp_entry <= 0;
    end
    else begin
        s4_rsp_entry <= (current_state != SB_S4_COMPLETION_RSP) && (next_state == SB_S4_COMPLETION_RSP);
    end
end
//=====================================================


//Register to detect the rising edge of sb_det_pattern_rcvd signal.
// logic sb_det_pattern_rcvd_d;
// always_ff @(posedge clk or negedge rst_n) begin
//     if(!rst_n)
//         sb_det_pattern_rcvd_d <= 1'b0;
//     else
//         sb_det_pattern_rcvd_d <= sb_det_pattern_rcvd;
// end
// logic sb_det_pattern_rcvd_edge;
// assign sb_det_pattern_rcvd_edge = sb_det_pattern_rcvd && !sb_det_pattern_rcvd_d;
//===========================

// //S2 pattern send counter
// logic [2:0] pattern_req_cnt;
// logic four_patterns_done;
// always_ff @(posedge clk or negedge rst_n) begin
//     if(!rst_n || current_state != SB_S2_LINK_SYNCH)
//         pattern_req_cnt <= 3'd0;
//     else if(pattern_req_cnt < 4) // to count only the rising edge of the pattern request signal.
//         pattern_req_cnt <= pattern_req_cnt + 1;
// end
// assign four_patterns_done = (pattern_req_cnt >= 4);

//=====================================================
//============ State register logic =================
//=====================================================
always_ff @( posedge clk , negedge rst_n ) begin
    if(!rst_n) begin
        current_state <= SB_S0_IDLE ;
    end
    else begin
        current_state <= next_state ;
    end
end
//=====================================================
//============ State transition logic =================
//=====================================================

always_comb begin
    next_state = current_state ;
    if(sbinit_error)
        next_state = SB_S0_IDLE;
    else 
    case(current_state)           
        SB_S0_IDLE: begin
            if(sbinit_enable && !sbinit_error) begin
                next_state = SB_S1_DET_PATTERN ;
            end
        end
        SB_S1_DET_PATTERN: begin
            if(!sbinit_enable || sbinit_error)begin
                next_state = SB_S0_IDLE ;
            end
            else if(sb_det_pattern_rcvd )begin
                next_state = SB_S2_LINK_SYNCH ;
            end
        end
        
        SB_S2_LINK_SYNCH: begin
            if(!sbinit_enable|| sbinit_error)begin
                next_state = SB_S0_IDLE ;
            end
            else if(four_iteration_done)begin
                next_state = SB_S3_OUT_OF_RESET ;
            end
        end
        
        SB_S3_OUT_OF_RESET: begin
            if(!sbinit_enable || sbinit_error)
                next_state = SB_S0_IDLE ;               
            else if(out_of_reset_msg_sent && out_of_reset_msg_rcvd)
                next_state = SB_S4_COMPLETION_REQ ;
        end
        
        SB_S4_COMPLETION_REQ: begin
            if(!sbinit_enable || sbinit_error )
                next_state = SB_S0_IDLE ;
            else if(done_req_rcvd && !done_rsp_rcvd)
                next_state = SB_S4_COMPLETION_RSP ;
        end
        SB_S4_COMPLETION_RSP: begin
            if(!sbinit_enable || sbinit_error)begin
                next_state = SB_S0_IDLE ;
            end
            else if(done_rsp_rcvd)begin
                next_state = SB_S5_DONE ;
            end
        end
        SB_S5_DONE: begin
            if(!sbinit_enable)begin
                next_state = SB_S0_IDLE ;
            end
            else begin
                next_state = SB_S5_DONE ;
            end
        end
        default: begin
            next_state = SB_S0_IDLE ;
        end
    endcase
end
//=====================================================
//===================  OUTPUT  ========================
//=====================================================

//Message Output logic.
always_comb begin
    sb_tx_msg_id        = msg_no_e'(NOTHING) ;
    sb_tx_valid         = 1'b0 ;
    sb_det_pattern_req  = 1'b0;
    send_4_iteration    = 1'b0;
        
    case(current_state)
            
        SB_S1_DET_PATTERN:begin
            sb_det_pattern_req  = (sbinit_enable && (ms_cnt[0] == 0) && (next_state == SB_S1_DET_PATTERN) && !pattern_rcvd_sticky) ;
        end
        SB_S2_LINK_SYNCH:begin
            send_4_iteration  = 1'b1;
        end
        SB_S3_OUT_OF_RESET:begin
            if(s3_entry) begin
                sb_tx_valid  = 1'b1 ;
                sb_tx_msg_id = SBINIT_Out_of_Reset ;
            end
            else begin
                sb_tx_valid  = 1'b0 ;
                sb_tx_msg_id = msg_no_e'(NOTHING);
            end
        end
            
        SB_S4_COMPLETION_REQ:begin
            if(s4_req_entry)begin
                sb_tx_valid  = 1'b1 ;
                sb_tx_msg_id = SBINIT_done_req;
            end
            else begin
                sb_tx_valid  = 1'b0 ;
                sb_tx_msg_id = msg_no_e'(NOTHING);
            end
        end
                
        SB_S4_COMPLETION_RSP:begin
            if(s4_rsp_entry)begin
                sb_tx_valid  = 1'b1 ;
                sb_tx_msg_id = SBINIT_done_resp;
            end
            else begin
                sb_tx_valid  = 1'b0 ;
                sb_tx_msg_id = msg_no_e'(NOTHING);
            end
        end
                
        default begin
            sb_tx_msg_id        = msg_no_e'(NOTHING);
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
    if(current_state == SB_S5_DONE) begin       
        sbinit_done = 1;
    end
    else begin
        sbinit_done = 0;
    end
end

//=====================================================
//====================  ERROR  ========================
//=====================================================
always_ff @( posedge clk , negedge rst_n ) begin
    if(!rst_n) begin
        sbinit_error <= 1'b0 ;
    end
    else if(sbinit_1ms_timeout_error) begin
        sbinit_error <= 1'b1 ;
    end
    else if (sbinit_timeout_error) begin
        sbinit_error <= 1'b1 ;
    end
    else if(current_state == SB_S0_IDLE) begin
        sbinit_error <= 1'b0 ;
    end
    else begin
        // S1 and S2: Any valid message received is an error.
        if( (current_state == SB_S1_DET_PATTERN || current_state == SB_S2_LINK_SYNCH ) &&  sb_rx_valid ) begin
            sbinit_error <= 1'b1 ;
        end
        // S3: Any valid message other than Out_Of_Reset is an error.
        else if(current_state == SB_S3_OUT_OF_RESET && sb_rx_valid && sb_rx_msg_id !== SBINIT_Out_of_Reset)begin
            sbinit_error <= 1'b1 ;
        end
        // S4-req: Any valid message other than Done_req is an error.
        else if(current_state == SB_S4_COMPLETION_REQ && sb_rx_valid && sb_rx_msg_id !== SBINIT_done_req)begin
            sbinit_error <= 1'b1 ;
        end
        // S4-rsp: Any valid message other than Done_rsp is an error.
        else if(current_state == SB_S4_COMPLETION_RSP && sb_rx_valid && sb_rx_msg_id !== SBINIT_done_resp)begin
            sbinit_error <= 1'b1 ;
        end
    end
end

endmodule 