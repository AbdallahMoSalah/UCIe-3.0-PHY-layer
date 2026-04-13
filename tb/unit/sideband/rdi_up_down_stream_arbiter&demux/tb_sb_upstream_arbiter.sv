`timescale 1ns/1ps

module tb_sb_upstream_arbiter();

    // ==========================================
    // 1. Testbench Signals Declaration
    // ==========================================
    // Inputs to DUT (عربيات جاية للتقاطع)
    logic [127:0] Adapter_msg_rcvd;
    logic         Adapter_vld_rcvd;
    logic [127:0] completion_msg;
    logic         completion_vld;

    // Outputs from DUT (قرارات عسكري المرور)
    logic         completion_ready;
    logic [127:0] Adapter_msg;
    logic         Adapter_vld;

    // ==========================================
    // 2. DUT Instantiation (توصيل الديزاين)
    // ==========================================
    sb_upstream_arbiter dut (
        .Adapter_msg_rcvd(Adapter_msg_rcvd),
        .Adapter_vld_rcvd(Adapter_vld_rcvd),
        .completion_msg(completion_msg),
        .completion_vld(completion_vld),
        .completion_ready(completion_ready),
        .Adapter_msg(Adapter_msg),
        .Adapter_vld(Adapter_vld)
    );

    // ==========================================
    // 3. Helper Task for Checking (أداة فحص النتيجة)
    // ==========================================
    task check_result(input logic exp_vld, input logic [127:0] exp_msg, input logic exp_comp_rdy, string test_name);
        if (Adapter_vld === exp_vld && Adapter_msg === exp_msg && completion_ready === exp_comp_rdy)
            $display("[PASS] %s", test_name);
        else
            $error("[FAIL] %s - Check Waveforms!", test_name);
    endtask

    // ==========================================
    // 4. Test Scenarios (بداية الاختبارات)
    // ==========================================
    initial begin
        $display("==================================================");
        $display("   STARTING ARBITER VERIFICATION...");
        $display("==================================================");

        // تهيئة الإشارات (الشارع فاضي)
        Adapter_msg_rcvd = 128'h0;
        Adapter_vld_rcvd = 0;
        completion_msg   = 128'h0;
        completion_vld   = 0;
        #10;
        check_result(1'b0, 128'h0, 1'b0, "TC0: Idle State (No Requests)");

        // --------------------------------------------------------
        // Test Case 1: Remote Only (High Priority)
        // Expected: Remote passes, completion_ready = 0
        // --------------------------------------------------------
        Adapter_msg_rcvd = 128'hAAAA_AAAA_AAAA_AAAA_AAAA_AAAA_AAAA_AAAA; // رسالة مميزة بحرف A
        Adapter_vld_rcvd = 1;
        completion_msg   = 128'hBBBB_BBBB_BBBB_BBBB_BBBB_BBBB_BBBB_BBBB;
        completion_vld   = 0; // Local مش باعت حاجة
        #10;
        check_result(1'b1, 128'hAAAA_AAAA_AAAA_AAAA_AAAA_AAAA_AAAA_AAAA, 1'b0, "TC1: Remote Request Only");

        // --------------------------------------------------------
        // Test Case 2: Local Only (Low Priority)
        // Expected: Local passes, completion_ready = 1 (أهم حاجة الـ Ready بواحد)
        // --------------------------------------------------------
        Adapter_vld_rcvd = 0; // Remote مش باعت حاجة
        completion_vld   = 1;
        #10;
        check_result(1'b1, 128'hBBBB_BBBB_BBBB_BBBB_BBBB_BBBB_BBBB_BBBB, 1'b1, "TC2: Local Completion Only");

        // --------------------------------------------------------
        // Test Case 3: THE COLLISION (Both at the same time)
        // Expected: Remote MUST win (Msg = AAAA...), Local MUST stall (completion_ready = 0)
        // --------------------------------------------------------
        Adapter_vld_rcvd = 1; // Remote باعت
        completion_vld   = 1; // Local باعت في نفس اللحظة
        #10;
        check_result(1'b1, 128'hAAAA_AAAA_AAAA_AAAA_AAAA_AAAA_AAAA_AAAA, 1'b0, "TC3: Collision! Remote Wins & Local Stalls");

        // تنظيف الإشارات في النهاية
        Adapter_vld_rcvd = 0;
        completion_vld   = 0;
        #10;

        $display("==================================================");
        $display("   VERIFICATION COMPLETE.");
        $display("==================================================");
        $finish;
    end

endmodule