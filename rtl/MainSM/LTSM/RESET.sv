// idle state.
// enable signal.
// (S.W || Adapter || SBINIT pattern ) && timeout(4ms) = status.
// track , valid , data , clk =  tx & rx .s

module RESET
#( parameter int CLK_FRQ_HZ = 800000000)
(
    input logic clk, rst_n, 

    //======================= RESET STATE SIGNALS =======================
    //conditions that trigger LTSM to start training sequence.
    //Triggers for starting UCIe training sequence. 
    input logic S_W_trigger , Adapter_trigger , sb_det_pattern_rcvd ,      

    // Control signals
    output logic mb_tx_valid_status , sb_tx_valid_status , sb_rx_valid_status,  // track , valid , data , clk .
    output logic mb_tx_track_status , sb_tx_track_status , sb_rx_track_status,  // track , valid , data , clk .
    output logic mb_tx_clk_status , sb_tx_clk_status , sb_rx_clk_status,        // track , valid , data , clk .
    output logic mb_tx_data_status , sb_tx_data_status , sb_rx_data_status,     // track , valid , data , clk .
    
    //NEW SIGNALS.
    output logic RESET_state_done, 
    
	input logic RESET_enable  //UCIe_start
);
logic RESET_4ms_done;
//=====================================================

typedef enum logic { 
    IDLE ,
    TRAINING
} rest_state_e;
rest_state_e current_state , next_state ;
//================== Conditions =======================

logic trainging_req;
assign trainging_req = (S_W_trigger || Adapter_trigger || sb_det_pattern_rcvd)&& RESET_4ms_done;


// to Reset timeout counter USING enable signal.
logic timer_enable;
assign timer_enable = RESET_enable && !RESET_state_done;
//===================================================== 

//===============  TIMER  =============================
//=====================================================
    //4ms counter for RESET.

timeout_counter #(
    .CLK_FRQ_HZ(CLK_FRQ_HZ),
    .TIME_OUT(4)        // 4ms RESET time.
) reset_4ms_counter (
    .clk(clk),
    .timeout_rst_n(rst_n),
    .enable_timeout(timer_enable),
    .timeout_expired(RESET_4ms_done)
);
//=========================

//state register.
always_ff @( posedge clk , negedge rst_n ) begin
    if(!rst_n)
        current_state <= IDLE ;
    else
        current_state <= next_state ;
    
end

//================================================
//next state logic.
always_comb begin
    next_state = current_state ;
    case(current_state)
        IDLE : begin
            if(trainging_req)
            //if(timer_enable)
                next_state = TRAINING ;
        end
        TRAINING : begin
            if(RESET_state_done)
                next_state = IDLE ;
        end
    endcase
end

// output logic.
    always_ff @(posedge clk , negedge rst_n) begin
        if(!rst_n) begin
        //====== mb_tx_status ======
        mb_tx_valid_status  = 1'b1 ;
        mb_tx_track_status  = 1'b1 ;
        mb_tx_clk_status    = 1'b1 ;
        mb_tx_data_status   = 1'b1 ;
        //====== sb_tx_status ======
        sb_tx_valid_status  = 1'b1 ;
        sb_tx_track_status  = 1'b1 ;
        sb_tx_clk_status    = 1'b1 ;
        sb_tx_data_status   = 1'b1 ;
        //====== sb_rx_status ======
        sb_rx_valid_status  = 1'b0 ;
        sb_rx_track_status  = 1'b0 ;
        sb_rx_clk_status    = 1'b0 ;
        sb_rx_data_status   = 1'b0 ;
        end
        else if(RESET_state_done) begin
                //====== mb_tx_status ======
                mb_tx_valid_status  = 1'b0 ;
                mb_tx_track_status  = 1'b0 ;
                mb_tx_clk_status    = 1'b0 ;
                mb_tx_data_status   = 1'b0 ;
                //====== sb_tx_status ======
                sb_tx_valid_status  = 1'b0 ;
                sb_tx_track_status  = 1'b0 ;
                sb_tx_clk_status    = 1'b0 ;
                sb_tx_data_status   = 1'b0 ;
                //====== sb_rx_status ======
                sb_rx_valid_status  = 1'b1 ;
                sb_rx_track_status  = 1'b1 ;
                sb_rx_clk_status    = 1'b1 ;
                sb_rx_data_status   = 1'b1 ;
                end
    end

    always_ff @(posedge clk , negedge rst_n) begin
        if(!rst_n)
            RESET_state_done <= 1'b0 ;
        else if(!RESET_enable)
            RESET_state_done <= 1'b0 ;
        else if(RESET_4ms_done)
            RESET_state_done <= 1'b1 ;
    end
endmodule 

