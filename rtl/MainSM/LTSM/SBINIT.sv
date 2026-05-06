/*
    add three more signals:
    1- send_4iteration
    2- send_4iteration_done
*/


module SBINIT

import UCIe_pkg::*; // Importing the UCIe package for necessary definitions and utilities.

#( parameter int CLK_FRQ_HZ = 800000000)
 (  //IN/OUT signals. 

    input logic clk,
    input logic rst_n,
    
    //Signal FROM TOP LTSM.
    input logic sbinit_enable,
    
    //Signal TO TOP LTSM.
    output logic sbinit_done,
    output logic sbinit_error,

    //Signals from SB block.
        //MESSAGES signals.
    input logic    sb_rx_valid,
    input msg_no_e sb_rx_msg_id,
        //Control signals.
    output logic sb_det_pattern_req,     // state S1: Request signal to SB block to start sending the pattern for detection.
    output logic send_4iteration,
    input  logic four_iteration_done,
    input logic sb_det_pattern_rcvd,     // state S1: Detected pattern received from SB block.

    //Signals to SB block.  
        //MESSAGES signals.
    output logic    sb_tx_valid,
    output msg_no_e sb_tx_msg_id,
        //NEW signal.
    output logic timeout_error,
    output logic sbinit_pattern_mode
 );    
//=====================================================
    
typedef enum logic [3:0]{
    SB_S0_IDLE,
    SB_S1_DET_PATTERN,
    SB_S2_LINK_SYNCH,
    SB_S3_OUT_OF_RESET,
    SB_S4_COMPLETION_REQ,
    SB_S4_COMPLETION_RSP
      } sb_state_e;
sb_state_e current_state , next_state ;
//=====================================================
//===================  Timer  =========================
//=====================================================
//timeout Timer (8 ms)
logic sb_timer_enable;  // to reset and enable the timeout timer.
assign sb_timer_enable = sbinit_enable && !sbinit_done && !sbinit_error;

logic sb_timeout_expired ;
timeout_counter #(
    .CLK_FRQ_HZ(CLK_FRQ_HZ),
    .TIME_OUT(8)
) sb_timeout_timer (
    .clk(clk),
    .timeout_rst_n(rst_n), 
    .enable_timeout(sb_timer_enable),          
    .timeout_expired(sb_timeout_expired) 
); 

//timeout error logic.
assign timeout_error = sb_timeout_expired && !sbinit_done ;

//=====================================================
//================= Handshake =========================
//=====================================================

    //S3 handshake logic.
    logic out_of_reset_msg_sent ;
    logic out_of_reset_msg_rcvd ;
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        out_of_reset_msg_sent <= 1'b0;
    else if(current_state == SB_S3_OUT_OF_RESET)
        out_of_reset_msg_sent <= 1'b1;
    else if(current_state != SB_S3_OUT_OF_RESET)
        out_of_reset_msg_sent <= 1'b0;
end
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        out_of_reset_msg_rcvd <= 1'b0;
    else if(current_state != SB_S3_OUT_OF_RESET)
        out_of_reset_msg_rcvd <= 1'b0;
    else if( sb_rx_valid && sb_rx_msg_id == SBINIT_Out_of_Reset)
        out_of_reset_msg_rcvd <= 1'b1;
end

    //S4 handshake flags.
    logic done_req_rcvd ;  
    logic done_rsp_rcvd ;
always_ff @(posedge clk , negedge rst_n) begin
    if(!rst_n) 
    done_req_rcvd <= 1'b0;
    else if(current_state == SB_S4_COMPLETION_REQ && sb_rx_valid && sb_rx_msg_id == SBINIT_done_req)
        done_req_rcvd <= 1'b1 ;
    else if(current_state != SB_S4_COMPLETION_REQ)
        done_req_rcvd <= 1'b0 ;
end

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        done_rsp_rcvd <= 1'b0;
    else if(current_state == SB_S4_COMPLETION_RSP && sb_rx_valid && sb_rx_msg_id == SBINIT_done_resp)
        done_rsp_rcvd <= 1'b1;
    else if(current_state != SB_S4_COMPLETION_RSP)
        done_rsp_rcvd <= 1'b0;
end


//=====================================================
//=================== PATTERN =========================
//=====================================================

logic s1_entry;
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        s1_entry <= 0;
    else
        s1_entry <= (current_state != SB_S1_DET_PATTERN) && (next_state == SB_S1_DET_PATTERN);
end

//Register to detect the rising edge of sb_det_pattern_rcvd signal.
logic sb_det_pattern_rcvd_d;
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        sb_det_pattern_rcvd_d <= 1'b0;
    else
        sb_det_pattern_rcvd_d <= sb_det_pattern_rcvd;
end
logic sb_det_pattern_rcvd_edge;
assign sb_det_pattern_rcvd_edge = sb_det_pattern_rcvd && !sb_det_pattern_rcvd_d;
//===========================
//S1 pattern received counter.
logic [1:0] pattern_rcvd_cnt;
logic two_patterns_done;

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n || current_state != SB_S1_DET_PATTERN)
        pattern_rcvd_cnt <= 2'd0;
    else if(sb_det_pattern_rcvd_edge)// to count only the rising edge of the pattern received signal.
        pattern_rcvd_cnt <= pattern_rcvd_cnt + 1;
end
assign two_patterns_done  = (pattern_rcvd_cnt == 2);

//==========================
//S2 pattern send counter
logic [2:0] pattern_req_cnt;
logic four_patterns_done;
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n || current_state != SB_S2_LINK_SYNCH)
        pattern_req_cnt <= 3'd0;
    else if(pattern_req_cnt < 4) // to count only the rising edge of the pattern request signal.
        pattern_req_cnt <= pattern_req_cnt + 1;
end
assign four_patterns_done = (pattern_req_cnt >= 4);

//=====================================================

//State register logic.
always_ff @( posedge clk , negedge rst_n ) begin
    if(!rst_n)
        current_state <= SB_S0_IDLE ;
    
    else
        current_state <= next_state ;
end
//=====================================================

//State transition logic.
    always_comb begin
        next_state = current_state ;

        if(timeout_error)
            next_state = SB_S0_IDLE;
        else 
        case(current_state)           
            SB_S0_IDLE: begin
                if(sbinit_enable && !sbinit_error && !timeout_error)
                    next_state = SB_S1_DET_PATTERN ;
            end

            SB_S1_DET_PATTERN: begin
                if(!sbinit_enable || sbinit_error)
                    next_state = SB_S0_IDLE ;
                else if(two_patterns_done)
                    next_state = SB_S2_LINK_SYNCH ;
            end
            
            SB_S2_LINK_SYNCH: begin
                if(!sbinit_enable|| sbinit_error)
                    next_state = SB_S0_IDLE ;
                else if(four_patterns_done)
                    next_state = SB_S3_OUT_OF_RESET ;
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
                if(!sbinit_enable || sbinit_done || sbinit_error || done_rsp_rcvd )
                    next_state = SB_S0_IDLE ;
            end

            default: next_state = SB_S0_IDLE ;
        endcase
    end
//=====================================================
//===================  OUTPUT  ========================
//=====================================================

    //Message Output logic.
    always_comb begin

        //if(!rst_n) begin
            sb_tx_msg_id = msg_no_e'(8'h00) ;
            sb_tx_valid = 1'b0 ;
            //sbinit_pattern_mode = 1'b0;
        //end
        if(sbinit_enable) begin
                case(current_state)
                /*
                SB_S1_DET_PATTERN: sbinit_pattern_mode = 1'b1;
                */
                    SB_S3_OUT_OF_RESET:begin
                        sb_tx_valid = 1'b1 ;
                        sb_tx_msg_id = SBINIT_Out_of_Reset ;
                        //sbinit_pattern_mode = 1'b0;
                    end
                
                    SB_S4_COMPLETION_REQ:begin
                        sb_tx_valid = 1'b1 ;
                        sb_tx_msg_id = SBINIT_done_req;
                    end
                    
                    SB_S4_COMPLETION_RSP:begin
                            sb_tx_valid = 1'b1 ;
                            sb_tx_msg_id = SBINIT_done_resp;
                    end                    
                endcase
            end
        end        

    //Pattern Request signal output logic.
    always_comb begin
        sb_det_pattern_req = 1'b0;
         if(s1_entry && !sbinit_done)
            sb_det_pattern_req = 1 ;
         else if(current_state == SB_S2_LINK_SYNCH && pattern_req_cnt < 4)
            sb_det_pattern_req = 1;
    end

    //sbinit_done signal output logic.
    always_ff @( posedge clk , negedge rst_n ) begin
        if(!rst_n /*|| !sbinit_enable*/)
            sbinit_done <= 1'b0 ;
        else if(current_state == SB_S4_COMPLETION_RSP && sb_rx_valid && sb_rx_msg_id == SBINIT_done_resp)
            sbinit_done <= 1'b1 ;

    end

    //sbinit_error signal output logic.
    always_ff @( posedge clk , negedge rst_n ) begin
        if(!rst_n || !sbinit_enable)
            sbinit_error <= 1'b0 ;
        else if (timeout_error)
            sbinit_error <= 1'b1 ;
        else begin
            // S1 and S2: Any valid message received is an error.
            if( (current_state == SB_S1_DET_PATTERN || current_state == SB_S2_LINK_SYNCH ) &&  sb_rx_valid )
                sbinit_error <= 1'b1 ;
            // S3: Any valid message other than Out_Of_Reset is an error.
            else if(current_state == SB_S3_OUT_OF_RESET && sb_rx_valid && sb_rx_msg_id !== SBINIT_Out_of_Reset)
                sbinit_error <= 1'b1 ;
            // S4: Any valid message other than Done_rsp is an error.
            else if(current_state == SB_S4_COMPLETION_RSP && sb_rx_valid && sb_rx_msg_id !== SBINIT_done_resp && sb_rx_msg_id != SBINIT_done_req)
                sbinit_error <= 1'b1 ;
        end
    end
endmodule 