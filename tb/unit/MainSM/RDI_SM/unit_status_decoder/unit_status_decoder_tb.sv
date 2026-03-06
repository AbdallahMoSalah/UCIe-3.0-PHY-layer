`timescale 1ns/1ps

module unit_status_decoder_tb();

    // ===============
    // Signals
    // ===============
    logic [3:0] UCIe_Link_DVSEC_UCIe_Link_Capability_7_downto_4;
    logic [3:0] UCIe_Link_DVSEC_UCIe_Link_Status_10_downto_7;
    logic [3:0] UCIe_Link_DVSEC_UCIe_Link_Status_17_downto_11;
            
    logic [2:0] pl_lnk_cfg; 
    logic [2:0] pl_speedmode; 
    logic       pl_max_speedmode;

    // Golden model signals
    logic [2:0] exp_pl_lnk_cfg; 
    logic [2:0] exp_pl_speedmode; 
    logic       exp_pl_max_speedmode;

    // ===============
    // DUT Instantiation
    // ===============
    unit_status_decoder dut (
        .UCIe_Link_DVSEC_UCIe_Link_Capability_7_downto_4(UCIe_Link_DVSEC_UCIe_Link_Capability_7_downto_4),
        .UCIe_Link_DVSEC_UCIe_Link_Status_10_downto_7(UCIe_Link_DVSEC_UCIe_Link_Status_10_downto_7),
        .UCIe_Link_DVSEC_UCIe_Link_Status_17_downto_11(UCIe_Link_DVSEC_UCIe_Link_Status_17_downto_11),
        .pl_lnk_cfg(pl_lnk_cfg),
        .pl_speedmode(pl_speedmode),
        .pl_max_speedmode(pl_max_speedmode)
    );

    // ===============
    // Golden Model
    // ===============
    // Purely combinational evaluation matching DUT logic
    assign exp_pl_max_speedmode = (UCIe_Link_DVSEC_UCIe_Link_Capability_7_downto_4[2:0] > 3'h5);
    assign exp_pl_lnk_cfg = UCIe_Link_DVSEC_UCIe_Link_Status_10_downto_7[2:0];
    assign exp_pl_speedmode = UCIe_Link_DVSEC_UCIe_Link_Status_17_downto_11[2:0];

    // ===============
    // Tasks
    // ===============
    
    // Task: Drive inputs
    task drive_inputs(
        input logic [3:0] cap,
        input logic [3:0] stat1,
        input logic [3:0] stat2
    );
        begin
            #5; // Wait a bit before applying new stimulus
            UCIe_Link_DVSEC_UCIe_Link_Capability_7_downto_4 = cap;
            UCIe_Link_DVSEC_UCIe_Link_Status_10_downto_7 = stat1;
            UCIe_Link_DVSEC_UCIe_Link_Status_17_downto_11 = stat2;
            $display("[%0t] DRIVER : Driven cap=%h, stat1=%h, stat2=%h", 
                $time, cap, stat1, stat2);
            #5; // Let combinational logic propagate
        end
    endtask

    int err_count = 0;
    
    // Task: Check outputs against golden model
    task check_outputs();
        begin
            if (pl_max_speedmode !== exp_pl_max_speedmode || 
                pl_lnk_cfg !== exp_pl_lnk_cfg || 
                pl_speedmode !== exp_pl_speedmode) begin
                
                $error("[%0t] CHECKER: MISMATCH! Expected (max_speed=%b, lnk_cfg=%h, speed=%h) | Actual (max_speed=%b, lnk_cfg=%h, speed=%h)", 
                    $time, exp_pl_max_speedmode, exp_pl_lnk_cfg, exp_pl_speedmode, 
                    pl_max_speedmode, pl_lnk_cfg, pl_speedmode);
                err_count++;
            end else begin
                $display("[%0t] CHECKER: MATCH! max_speed=%b, lnk_cfg=%h, speed=%h", 
                    $time, pl_max_speedmode, pl_lnk_cfg, pl_speedmode);
            end
        end
    endtask

    // ===============
    // Test Sequence
    // ===============
    initial begin
        $display("========================================");
        $display("Starting unit_status_decoder Testbench");
        $display("========================================");

        // Initialize inputs
        UCIe_Link_DVSEC_UCIe_Link_Capability_7_downto_4 = 0;
        UCIe_Link_DVSEC_UCIe_Link_Status_10_downto_7 = 0;
        UCIe_Link_DVSEC_UCIe_Link_Status_17_downto_11 = 0;
        
        #10;
        
        // ----------------------------------------
        // Transaction 1: All zeros
        // ----------------------------------------
        $display("\n--- Test 1: All Zeros ---");
        drive_inputs(4'h0, 4'h0, 4'h0);
        check_outputs(); 

        // ----------------------------------------
        // Transaction 2: Max speedmode threshold exactly at 5
        // ----------------------------------------
        $display("\n--- Test 2: Threshold case (cap=5) ---");
        drive_inputs(4'h5, 4'h1, 4'h2);
        check_outputs(); 

        // ----------------------------------------
        // Transaction 3: Max speedmode threshold above 5
        // ----------------------------------------
        $display("\n--- Test 3: Above threshold (cap=6) ---");
        drive_inputs(4'h6, 4'h3, 4'h4);
        check_outputs(); 

        // ----------------------------------------
        // Transaction 4: Max speedmode threshold max (cap=7)
        // ----------------------------------------
        $display("\n--- Test 4: Max value (cap=7) ---");
        drive_inputs(4'h7, 4'h7, 4'h7);
        check_outputs(); 
        
        // ----------------------------------------
        // Transaction 5: Discard upper bit (bit 3) as per logic limitation
        // ----------------------------------------
        $display("\n--- Test 5: Ignored upper bit (cap=8, stat1=F, stat2=8) ---");
        drive_inputs(4'h8, 4'hF, 4'h8);
        check_outputs(); 

        // Summary
        $display("\n========================================");
        if (err_count == 0)
            $display("TEST PASSED! 0 Mismatches.");
        else
            $display("TEST FAILED! %0d Mismatches.", err_count);
        $display("========================================");

        $stop;
    end

endmodule
