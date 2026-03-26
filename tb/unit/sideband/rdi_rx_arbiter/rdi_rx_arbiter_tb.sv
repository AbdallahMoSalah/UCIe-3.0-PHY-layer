module rdi_rx_arbiter_tb;

    // Inputs
    logic [127:0] comp_msg;
    logic         comp_vld;
    logic [127:0] req_msg;
    logic         req_vld;
    logic         no_crd;
    logic         out_ready;

    // Outputs
    logic [127:0] out_msg;
    logic         out_vld;
    logic         comp_ready;
    logic         req_ready;

    // Expected Outputs for self-check
    logic [127:0] exp_out_msg;
    logic         exp_out_vld;
    logic         exp_comp_ready;
    logic         exp_req_ready;

    int pass_count = 0;
    int fail_count = 0;

    // DUT Instantiation
    rdi_rx_arbiter dut (
        .out_msg(out_msg),
        .out_vld(out_vld),
        .out_ready(out_ready),
        .comp_msg(comp_msg),
        .comp_vld(comp_vld),
        .comp_ready(comp_ready),
        .req_msg(req_msg),
        .req_vld(req_vld),
        .req_ready(req_ready),
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
            out_ready = i[0];

            // Setup expected outputs
            exp_out_msg    = 128'h0;
            exp_out_vld    = 1'b0;
            exp_comp_ready = 1'b0;
            exp_req_ready  = 1'b0;

            if (comp_vld) begin
                exp_out_msg    = comp_msg;
                exp_out_vld    = 1'b1;
                exp_comp_ready = out_ready;
            end
            else if (req_vld && !no_crd) begin
                exp_out_msg    = req_msg;
                exp_out_vld    = 1'b1;
                exp_req_ready  = out_ready;
            end

            #1; // Delay to allow combinational logic to settle

            // Self-Check
            if (out_msg !== exp_out_msg || out_vld !== exp_out_vld ||
                comp_ready !== exp_comp_ready || req_ready !== exp_req_ready) begin
                $display("[FAIL] comp_vld=%b, req_vld=%b, no_crd=%b, out_ready=%b", comp_vld, req_vld, no_crd, out_ready);
                $display("       EXP: msg=%h, vld=%b, c_rdy=%b, r_rdy=%b", exp_out_msg, exp_out_vld, exp_comp_ready, exp_req_ready);
                $display("       GOT: msg=%h, vld=%b, c_rdy=%b, r_rdy=%b", out_msg, out_vld, comp_ready, req_ready);
                fail_count++;
            end else begin
                // Detailed debug display for passing conditions
                $display("[PASS] comp_vld=%b, req_vld=%b, no_crd=%b, out_ready=%b -> out_vld=%b, c_rdy=%b, r_rdy=%b", 
                          comp_vld, req_vld, no_crd, out_ready, out_vld, comp_ready, req_ready);
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
