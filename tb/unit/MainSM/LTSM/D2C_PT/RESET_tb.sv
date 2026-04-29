`timescale 1ns/1ps
module RESET_tb;

logic clk, rst_n;
logic S_W_trigger , Adapter_trigger , sb_det_pattern_rcvd;

logic mb_tx_valid_status , sb_tx_valid_status , sb_rx_valid_status;  // track , valid , data , clk .
logic mb_tx_track_status , sb_tx_track_status , sb_rx_track_status;  // track , valid , data , clk .
logic mb_tx_clk_status , sb_tx_clk_status , sb_rx_clk_status;        // track , valid , data , clk .
logic mb_tx_data_status , sb_tx_data_status , sb_rx_data_status;     // track , valid , data , clk .

logic RESET_state_done;

logic RESET_enable;

// Instantiate the RESET module.
RESET #(1000000)
 reset_inst(
    .clk(clk),
    .rst_n(rst_n),
    .S_W_trigger(S_W_trigger),
    .Adapter_trigger(Adapter_trigger),
    .sb_det_pattern_rcvd(sb_det_pattern_rcvd),
    .mb_tx_valid_status(mb_tx_valid_status),
    .sb_tx_valid_status(sb_tx_valid_status),
    .sb_rx_valid_status(sb_rx_valid_status),
    .mb_tx_track_status(mb_tx_track_status),
    .sb_tx_track_status(sb_tx_track_status),
    .sb_rx_track_status(sb_rx_track_status),
    .mb_tx_clk_status(mb_tx_clk_status),
    .sb_tx_clk_status(sb_tx_clk_status),
    .sb_rx_clk_status(sb_rx_clk_status),
    .mb_tx_data_status(mb_tx_data_status),
    .sb_tx_data_status(sb_tx_data_status),
    .sb_rx_data_status(sb_rx_data_status),
    .RESET_state_done(RESET_state_done),
    .RESET_enable(RESET_enable)
);

    initial clk = 0;
    always #500 clk = ~clk; // 1 MHz clock period is 1 microsecond (1000ns), so toggle every 500ns.


initial begin
    rst_n = 0;
    S_W_trigger = 0;
    Adapter_trigger = 0;
    sb_det_pattern_rcvd = 0;
    RESET_enable = 0;

    #2000; // Wait for 2 microseconds before releasing reset.
    rst_n = 1;
    RESET_enable = 1;

    #2000; // Wait for 2 microsecond before asserting conditions.
    S_W_trigger = 1;
    Adapter_trigger = 1;
    sb_det_pattern_rcvd = 1;

    #5000000; //Wait 5ms (should complete at 4ms)
    
   // $stop; // Stop the simulation.
end
endmodule

