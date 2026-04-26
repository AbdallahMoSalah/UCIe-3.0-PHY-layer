module rdi_rx_arbiter_tb;

    // Inputs
    logic [127:0] comp_msg;
    logic         comp_vld;
    logic [127:0] req_msg;
    logic         req_vld;
    logic         no_crd;
    logic         out_rdy;

    // Outputs
    logic [127:0] out_msg;
    logic         out_vld;
    logic         comp_rdy;
    logic         req_rdy;

    // Expected Outputs for self-check
    logic [127:0] exp_out_msg;
    logic         exp_out_vld;
    logic         exp_comp_rdy;
    logic         exp_req_rdy;

    int pass_count = 0;
    int fail_count = 0;

    // DUT Instantiation
    rdi_rx_arbiter dut (
        .out_msg(out_msg),
        .out_vld(out_vld),
        .out_rdy(out_rdy),
        .comp_msg(comp_msg),
        .comp_vld(comp_vld),
        .comp_rdy(comp_rdy),
        .req_msg(req_msg),
        .req_vld(req_vld),
        .req_rdy(req_rdy),
        .no_crd(no_crd)
    );

    initial begin
        // Distinct values for messages to test correct multiplexing
        comp_msg = 128'hCCCCCCCC_CCCCCCCC_CCCCCCCC_CCCCCCCC;
        req_msg  = 128'hBBBBBBBB_BBBBBBBB_BBBBBBBB_BBBBBBBB;

        $display("\n==================================================");
        $display("   Starting rdi_rx_arbiter Combinational Test");
        $display("==================================================\n");

        for (int i = 0; i < 16; i++) begin
            comp_vld  = i[3];
            req_vld   = i[2];
            no_crd    = i[1];
            out_rdy = i[0];

            // Setup expected outputs
            exp_out_msg    = req_msg;
            exp_out_vld    = req_vld;
            exp_comp_rdy = 1'b0;
            exp_req_rdy  = 1'b0;

            if (comp_vld) begin
                exp_out_msg    = comp_msg;
                exp_out_vld    = 1'b1;
                exp_comp_rdy = out_rdy;
            end
            else if (req_vld && !no_crd) begin
                exp_out_vld    = 1'b1;
                exp_req_rdy  = out_rdy;
            end

            #1; // Delay to allow combinational logic to settle

            // Self-Check
            if (out_msg !== exp_out_msg || out_vld !== exp_out_vld ||
                comp_rdy !== exp_comp_rdy || req_rdy !== exp_req_rdy) begin
                $display("[FAIL] comp_vld=%b, req_vld=%b, no_crd=%b, out_rdy=%b", comp_vld, req_vld, no_crd, out_rdy);
                $display("       EXP: msg=%h, vld=%b, c_rdy=%b, r_rdy=%b", exp_out_msg, exp_out_vld, exp_comp_rdy, exp_req_rdy);
                $display("       GOT: msg=%h, vld=%b, c_rdy=%b, r_rdy=%b", out_msg, out_vld, comp_rdy, req_rdy);
                fail_count++;
            end else begin
                // Detailed debug display for passing conditions
                $display("[PASS] comp_vld=%b, req_vld=%b, no_crd=%b, out_rdy=%b -> out_vld=%b, c_rdy=%b, r_rdy=%b", 
                          comp_vld, req_vld, no_crd, out_rdy, out_vld, comp_rdy, req_rdy);
                pass_count++;
            end
            #9; // wait before next iteration
        end

        // Final Verification Summary
        $display("\n==================================================");
        $display("            VERIFICATION SUMMARY REPORT             ");
        $display("==================================================");
        $display(" Total Cases Checked    : %0d", (pass_count + fail_count));
        $display(" Cases Passed           : %0d", pass_count);
        $display(" Cases Failed           : %0d", fail_count);
        $display("==================================================\n");

        $stop;
    end

endmodule
