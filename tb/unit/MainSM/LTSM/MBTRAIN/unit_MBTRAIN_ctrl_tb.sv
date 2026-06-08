`timescale 1ns/1ps

module unit_MBTRAIN_ctrl_tb;
    // Clock and Reset
    logic        lclk;
    logic        rst_n;
    logic        is_ltsm_out_of_reset;

    // LTSM Interface
    logic        mbtrain_en;
    logic        mbtrain_done;
    logic [3:0]  current_mbtrain_substate;

    // Global Interrupts / External Requests
    logic        trainerror_detected;
    logic        ltsm_trainerror_req;
    logic        ltsm_linkinit_req;
    logic        ltsm_phyretrain_req;
    logic        ltsm_repair_req;
    logic        ltsm_speedidle_req;

    // Entry Requests
    logic        mbtrain_txselfcal_req;
    logic        mbtrain_speedidle_req;
    logic        mbtrain_repair_req;

    // Sub-state Handshakes
    logic        local_valvref_en,          local_valvref_done;
    logic        partner_valvref_en,        partner_valvref_done;
    logic        local_datavref_en,         local_datavref_done;
    logic        partner_datavref_en,       partner_datavref_done;
    logic        local_speedidle_en,        local_speedidle_done;
    logic        partner_speedidle_en,      partner_speedidle_done;
    logic        local_txselfcal_en,        local_txselfcal_done;
    logic        partner_txselfcal_en,      partner_txselfcal_done;
    logic        local_rxclkcal_en,         local_rxclkcal_done;
    logic        partner_rxclkcal_en,       partner_rxclkcal_done;
    logic        local_valtraincenter_en,   local_valtraincenter_done;
    logic        partner_valtraincenter_en, partner_valtraincenter_done;
    logic        local_valtrainvref_en,     local_valtrainvref_done;
    logic        partner_valtrainvref_en,   partner_valtrainvref_done;
    logic        local_dtc1_en,             local_dtc1_done;
    logic        partner_dtc1_en,           partner_dtc1_done;
    logic        local_datatrainvref_en,    local_datatrainvref_done;
    logic        partner_datatrainvref_en,  partner_datatrainvref_done;
    logic        local_rxdeskew_en,         local_rxdeskew_done;
    logic        partner_rxdeskew_en,       partner_rxdeskew_done;
    logic        local_dtc1_loopback_req;
    logic        local_dtc2_en,             local_dtc2_done;
    logic        partner_dtc2_en,           partner_dtc2_done;
    logic        local_linkspeed_en,        local_linkspeed_done;
    logic        partner_linkspeed_en,      partner_linkspeed_done;
    logic        local_linkinit_route_req;
    logic        local_speedidle_route_req;
    logic        local_repair_route_req;
    logic        local_phyretrain_route_req;
    logic        local_repair_en,           local_repair_done;
    logic        partner_repair_en,         partner_repair_done;
    logic        local_repair_txselfcal_req;

    // DUT Instantiation
    unit_MBTRAIN_ctrl dut (.*);

    // Clock Generation
    initial lclk = 0;
    always #0.5 lclk = ~lclk; // 1GHz

    // Watchdog Timer
    initial begin
        #100us;
        $display("ERROR: Global Timeout reached at %0t! Simulation hung.", $time);
        $stop;
    end

    // Helper Tasks
    task reset_dut();
        rst_n = 0;
        is_ltsm_out_of_reset = 0;
        mbtrain_en = 0;
        trainerror_detected = 0;
        mbtrain_txselfcal_req = 0;
        mbtrain_speedidle_req = 0;
        mbtrain_repair_req = 0;
        
        local_valvref_done = 0; partner_valvref_done = 0;
        local_datavref_done = 0; partner_datavref_done = 0;
        local_speedidle_done = 0; partner_speedidle_done = 0;
        local_txselfcal_done = 0; partner_txselfcal_done = 0;
        local_rxclkcal_done = 0; partner_rxclkcal_done = 0;
        local_valtraincenter_done = 0; partner_valtraincenter_done = 0;
        local_valtrainvref_done = 0; partner_valtrainvref_done = 0;
        local_dtc1_done = 0; partner_dtc1_done = 0;
        local_datatrainvref_done = 0; partner_datatrainvref_done = 0;
        local_rxdeskew_done = 0; partner_rxdeskew_done = 0;
        local_dtc1_loopback_req = 0;
        local_dtc2_done = 0; partner_dtc2_done = 0;
        local_linkspeed_done = 0; partner_linkspeed_done = 0;
        local_linkinit_route_req = 0;
        local_speedidle_route_req = 0;
        local_repair_route_req = 0;
        local_phyretrain_route_req = 0;
        local_repair_done = 0; partner_repair_done = 0;
        local_repair_txselfcal_req = 0;

        repeat(10) @(posedge lclk);
        rst_n = 1;
        repeat(10) @(posedge lclk);
        is_ltsm_out_of_reset = 1;
        repeat(5) @(posedge lclk);
    endtask

    task automatic wait_state(input logic [3:0] expected_state);
        int timeout = 0;
        while (current_mbtrain_substate !== expected_state) begin
            @(posedge lclk);
            timeout++;
            if (timeout > 5000) begin
                $display("ERROR @%0t: Timeout waiting for state %0d (current=%0d)", $time, expected_state, current_mbtrain_substate);
                $stop;
            end
        end
        $display("[%0t] Entered state %0d", $time, expected_state);
    endtask

    task automatic finish_substate(ref logic l_done, ref logic p_done);
        repeat(5) @(posedge lclk);
        l_done = 1;
        repeat(2) @(posedge lclk);
        p_done = 1;
        @(posedge lclk);
        l_done = 0;
        p_done = 0;
        $display("[%0t] Substate finished", $time);
    endtask

    initial begin
        $display("Starting unit_MBTRAIN_ctrl_tb...");
        reset_dut();

        // Test 1: Normal full sequence
        $display("Test 1: Normal sequence to LINKINIT");
        mbtrain_en = 1;
        
        // 1. VALVREF
        wait_state(4'd1);
        finish_substate(local_valvref_done, partner_valvref_done);
        
        // 2. DATAVREF
        wait_state(4'd2);
        finish_substate(local_datavref_done, partner_datavref_done);

        // 3. SPEEDIDLE
        wait_state(4'd3);
        finish_substate(local_speedidle_done, partner_speedidle_done);

        // 4. TXSELFCAL
        wait_state(4'd4);
        finish_substate(local_txselfcal_done, partner_txselfcal_done);

        // 5. RXSELFCAL
        wait_state(4'd5);
        finish_substate(local_rxclkcal_done, partner_rxclkcal_done);

        // 6. VALTRAINCENTER
        wait_state(4'd6);
        finish_substate(local_valtraincenter_done, partner_valtraincenter_done);

        // 7. VALTRAINVREF
        wait_state(4'd7);
        finish_substate(local_valtrainvref_done, partner_valtrainvref_done);

        // 8. DATATRAINCENTER1
        wait_state(4'd8);
        finish_substate(local_dtc1_done, partner_dtc1_done);

        // 9. DATATRAINVREF
        wait_state(4'd9);
        finish_substate(local_datatrainvref_done, partner_datatrainvref_done);

        // 10. RXDESKEW
        wait_state(4'd10);
        finish_substate(local_rxdeskew_done, partner_rxdeskew_done);

        // 11. DATATRAINCENTER2
        wait_state(4'd11);
        finish_substate(local_dtc2_done, partner_dtc2_done);

        // 12. LINKSPEED -> LINKINIT
        wait_state(4'd12);
        local_linkinit_route_req = 1;
        finish_substate(local_linkspeed_done, partner_linkspeed_done);

        // 13. DONE
        wait_state(4'd14);
        if (mbtrain_done && ltsm_linkinit_req) begin
            $display("Test 1 PASSED: Reached MBTRAIN_DONE with linkinit_req");
        end else begin
            $display("Test 1 FAILED: Expected mbtrain_done and ltsm_linkinit_req");
        end

        mbtrain_en = 0;
        wait_state(4'd0);

        // Test 2: RXDESKEW loopback
        $display("Test 2: RXDESKEW loop back to DTC1");
        mbtrain_en = 1;
        @(posedge lclk); // Enter VALVREF
        // Fast forward to RXDESKEW
        local_valvref_done = 1; partner_valvref_done = 1; @(posedge lclk); local_valvref_done = 0; partner_valvref_done = 0;
        local_datavref_done = 1; partner_datavref_done = 1; @(posedge lclk); local_datavref_done = 0; partner_datavref_done = 0;
        local_speedidle_done = 1; partner_speedidle_done = 1; @(posedge lclk); local_speedidle_done = 0; partner_speedidle_done = 0;
        local_txselfcal_done = 1; partner_txselfcal_done = 1; @(posedge lclk); local_txselfcal_done = 0; partner_txselfcal_done = 0;
        local_rxclkcal_done = 1; partner_rxclkcal_done = 1; @(posedge lclk); local_rxclkcal_done = 0; partner_rxclkcal_done = 0;
        local_valtraincenter_done = 1; partner_valtraincenter_done = 1; @(posedge lclk); local_valtraincenter_done = 0; partner_valtraincenter_done = 0;
        local_valtrainvref_done = 1; partner_valtrainvref_done = 1; @(posedge lclk); local_valtrainvref_done = 0; partner_valtrainvref_done = 0;
        local_dtc1_done = 1; partner_dtc1_done = 1; @(posedge lclk); local_dtc1_done = 0; partner_dtc1_done = 0;
        local_datatrainvref_done = 1; partner_datatrainvref_done = 1; @(posedge lclk); local_datatrainvref_done = 0; partner_datatrainvref_done = 0;
        
        wait_state(4'd10); // RXDESKEW
        repeat(2) @(posedge lclk);
        local_dtc1_loopback_req = 1;
        @(posedge lclk);
        local_dtc1_loopback_req = 0;
        wait_state(4'd8); // Back to DTC1
        $display("Test 2 PASSED: Looped back to DTC1");

        // Test 3: LINKSPEED -> REPAIR -> TXSELFCAL
        $display("Test 3: LINKSPEED -> REPAIR -> TXSELFCAL");
        // Fast forward to LINKSPEED from DTC1
        local_dtc1_done = 1; partner_dtc1_done = 1; @(posedge lclk); local_dtc1_done = 0; partner_dtc1_done = 0;
        local_datatrainvref_done = 1; partner_datatrainvref_done = 1; @(posedge lclk); local_datatrainvref_done = 0; partner_datatrainvref_done = 0;
        local_rxdeskew_done = 1; partner_rxdeskew_done = 1; @(posedge lclk); local_rxdeskew_done = 0; partner_rxdeskew_done = 0;
        local_dtc2_done = 1; partner_dtc2_done = 1; @(posedge lclk); local_dtc2_done = 0; partner_dtc2_done = 0;

        wait_state(4'd12); // LINKSPEED
        local_linkinit_route_req = 0;
        local_repair_route_req = 1;
        finish_substate(local_linkspeed_done, partner_linkspeed_done);
        
        wait_state(4'd13); // REPAIR
        local_repair_txselfcal_req = 1;
        finish_substate(local_repair_done, partner_repair_done);
        
        wait_state(4'd4); // Back to TXSELFCAL
        $display("Test 3 PASSED: REPAIR looped to TXSELFCAL");

        // Test 4: Emergency TRAINERROR
        $display("Test 4: Emergency TRAINERROR exit");
        repeat(5) @(posedge lclk);
        trainerror_detected = 1;
        wait_state(4'd14); // MBTRAIN_DONE
        if (ltsm_trainerror_req) begin
            $display("Test 4 PASSED: Emergency exit to TRAINERROR");
        end else begin
            $display("Test 4 FAILED: Expected ltsm_trainerror_req");
        end

        $display("All tests completed.");
        $finish;
    end
endmodule
