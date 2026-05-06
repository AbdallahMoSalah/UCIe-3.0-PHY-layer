
/*

            //====== mb_tx_status ======
            mb_tx_valid_status  = 1'b1 ;
            mb_tx_track_status  = 1'b1 ;
            mb_tx_clk_status    = 1'b1 ;
            mb_tx_data_status   = 1'b1 ;
            //=========
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
*/

module RESET #(
    parameter int CLK_FRQ_HZ = 800000000
) (
    input  logic clk,
    input  logic rst_n, 
    
    //======================= RESET STATE SIGNALS =======================
    // Conditions that trigger LTSM to start training sequence.
    // Triggers for starting UCIe training sequence. 
    input  logic phy_start_ucie_link_training_ctrl_out,
    input  logic Adapter_training_req,
    input  logic sb_det_pattern_rcvd,  
    
    output logic RESET_state_done,
    
    input  logic RESET_enable  // UCIe_start
);

    logic RESET_4ms_done;

    //=====================================================
    typedef enum logic { 
        IDLE,
        TRAINING
    } rest_state_e;
    
    rest_state_e current_state, next_state;
    
    //================== Conditions =======================
    // Any trigger while RESET_enable is high causes an IDLE→TRAINING transition.
    // The triggers are pulse-style; they do NOT need to stay high for the full
    // 4 ms — the FSM latches the request by entering TRAINING state.
    logic training_trigger;
    assign training_trigger = RESET_enable &&
                              (phy_start_ucie_link_training_ctrl_out ||
                               Adapter_training_req ||
                               sb_det_pattern_rcvd);

    //===================================================== 
    //===============  TIMER  =============================
    //=====================================================
    // 4 ms counter for RESET.
    // The timer runs while we are in TRAINING state.  It resets in IDLE
    // (enable_timeout is low → counter clears to 0 inside timeout_counter).
    logic timer_enable;
    assign timer_enable = (current_state == TRAINING);
    
    timeout_counter #(
        .CLK_FRQ_HZ(CLK_FRQ_HZ),
        .TIME_OUT(4)  // 4ms RESET time.
    ) reset_4ms_counter (
        .clk(clk),
        .timeout_rst_n(rst_n),
        .enable_timeout(timer_enable),
        .timeout_expired(RESET_4ms_done)
    );

    //=====================================================
    //===================== STATE REGISTER ================
    //=====================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
        end else begin
            current_state <= next_state;
        end
    end
    
    //===================================================== 
    //===============  NEXT STATE LOGIC ===================
    //=====================================================
    always_comb begin
        next_state = current_state;
        
        case (current_state)
            IDLE: begin
                if (training_trigger) begin
                    next_state = TRAINING;
                end
            end
            
            TRAINING: begin
                if (RESET_4ms_done) begin
                    next_state = IDLE;
                end
            end
        endcase
    end
    
    //=====================================================
    //===================== DONE SIGNAL ===================
    //=====================================================
    // Single-cycle pulse: high for exactly the clock edge where the timer
    // expires while still in TRAINING.  On the next edge the FSM moves
    // back to IDLE, so the pulse self-clears.
    assign RESET_state_done = (current_state == TRAINING) && RESET_4ms_done;

endmodule
