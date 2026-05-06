module RESET_tb;

    // Clock and Reset
    logic clk;
    logic rst_n;

    // DUT Signals
    logic phy_start_ucie_link_training_ctrl_out;
    logic Adapter_training_req;
    logic sb_det_pattern_rcvd;
    logic RESET_state_done;
    logic RESET_enable;

    // Instantiate the DUT
    RESET #(
        .CLK_FRQ_HZ(800000000)  // Assuming default frequency
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .phy_start_ucie_link_training_ctrl_out(phy_start_ucie_link_training_ctrl_out),
        .Adapter_training_req(Adapter_training_req),
        .sb_det_pattern_rcvd(sb_det_pattern_rcvd),
        .RESET_state_done(RESET_state_done),
        .RESET_enable(RESET_enable)
    );

    // Clock Generation
    localparam real CLK_PERIOD = 1.25; // 800 MHz -> 1.25 ns period

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // Test Sequence
    initial begin
        // Initialize
        rst_n = 1'b0;          // Assert reset

        phy_start_ucie_link_training_ctrl_out = 1'b0;
        Adapter_training_req = 1'b0;
        sb_det_pattern_rcvd = 1'b0;
        RESET_enable = 1'b0;

        #20;                   // Hold reset for 20 ns
        rst_n = 1'b1;          // Release reset
        #10;

        // Scenario 1: phy_start_ucie_link_training_ctrl_out triggers training
        $display("Time %t: Scenario 1: phy_start_ucie_link_training_ctrl_out", $time);
        phy_start_ucie_link_training_ctrl_out = 1'b1;
        RESET_enable = 1'b1;   // Enable the module
        #(CLK_PERIOD * 10);    // Hold trigger for 10 cycles
        phy_start_ucie_link_training_ctrl_out = 1'b0;

        // Wait for RESET_state_done
        wait(RESET_state_done);
        $display("Time %t: RESET_state_done asserted - Training completed", $time);
        #50; // Let it settle

        // Scenario 2: Adapter_training_req triggers training
        $display("Time %t: Scenario 2: Adapter_training_req", $time);
        Adapter_training_req = 1'b1;
        #(CLK_PERIOD * 10);
        Adapter_training_req = 1'b0;

        wait(RESET_state_done);
        $display("Time %t: RESET_state_done asserted - Training completed", $time);
        #50;

        // Scenario 3: sb_det_pattern_rcvd triggers training
        $display("Time %t: Scenario 3: sb_det_pattern_rcvd", $time);
        sb_det_pattern_rcvd = 1'b1;
        #(CLK_PERIOD * 10);
        sb_det_pattern_rcvd = 1'b0;

        wait(RESET_state_done);
        $display("Time %t: RESET_state_done asserted - Training completed", $time);
        #50;

        // Scenario 4: Simultaneous triggers
        $display("Time %t: Scenario 4: Simultaneous triggers", $time);
        phy_start_ucie_link_training_ctrl_out = 1'b1;
        Adapter_training_req = 1'b1;
        sb_det_pattern_rcvd = 1'b1;
        #(CLK_PERIOD * 10);
        phy_start_ucie_link_training_ctrl_out = 1'b0;
        Adapter_training_req = 1'b0;
        sb_det_pattern_rcvd = 1'b0;

        wait(RESET_state_done);
        $display("Time %t: RESET_state_done asserted - Training completed", $time);
        #50;

        // Scenario 5: Trigger with RESET_enable low (should not start)
        $display("Time %t: Scenario 5: Trigger with RESET_enable low", $time);
        RESET_enable = 1'b0;
        phy_start_ucie_link_training_ctrl_out = 1'b1;
        #(CLK_PERIOD * 20);
        phy_start_ucie_link_training_ctrl_out = 1'b0;
        // RESET_state_done should remain low
        if (!RESET_state_done) begin
            $display("Time %t: RESET_state_done remained low as expected", $time);
        end else begin
            $error("Time %t: RESET_state_done asserted unexpectedly", $time);
        end
        #50;

        // Scenario 6: Verify DONE pulses for one cycle then FSM returns to IDLE
        $display("Time %t: Scenario 6: Verify DONE pulse and FSM return to IDLE", $time);
        phy_start_ucie_link_training_ctrl_out = 1'b1;
        RESET_enable = 1'b1;
        #(CLK_PERIOD * 10);
        phy_start_ucie_link_training_ctrl_out = 1'b0;

        // RESET_state_done is a 1-cycle combinational pulse (TRAINING && 4ms_done).
        // After it fires the FSM transitions back to IDLE, so done deasserts.
        wait(RESET_state_done);
        $display("Time %t: RESET_state_done pulsed (1-cycle done pulse) - PASS", $time);
        @(posedge clk); // advance one clock — FSM should be back in IDLE
        #1;
        if (!RESET_state_done) begin
            $display("Time %t: RESET_state_done deasserted (FSM back in IDLE) - PASS", $time);
        end else begin
            $error("Time %t: RESET_state_done still asserted after expected de-assertion", $time);
        end
        #50;

        $finish; // Terminate simulation — the forever clock would otherwise run indefinitely.
    end

    // final block: a teardown hook that runs AFTER $finish is called above.
    // $finish inside a final block is redundant and has no effect.
    final begin
        $display("Time %t: All scenarios completed. Simulation finished.", $time);
    end

endmodule