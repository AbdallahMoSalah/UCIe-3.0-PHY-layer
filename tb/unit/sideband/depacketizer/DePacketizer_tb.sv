module DePacketizer_tb;

    import sb_pkg::*;
    import UCIe_pkg::*;
    import DePacketizer_tb_pkg::*;

    logic clk;
    logic rst_n;
    logic [127:0] msg_in;
    logic vld_in;

    msg_no_e     msg_no_out;
    logic [15:0] msginfo_r;
    logic [63:0] payload_r;
    logic vld_r;
    logic stall_rcvd;

    int pass_count = 0;
    int fail_count = 0;

    DePacketizer_class obj = new();

    DePacketizer DUT (
        .clk(clk),
        .rst_n(rst_n),
        .msg_in(msg_in),
        .vld_in(vld_in),
        .msg_no_out(msg_no_out),
        .msginfo_r(msginfo_r),
        .payload_r(payload_r),
        .vld_r(vld_r),
        .stall_rcvd(stall_rcvd)
    );

    // Clock
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin

        apply_reset();

        repeat (3000) begin
            obj.testtype = WITHOUT_RESET;
            assert(obj.randomize() with{
                error_type == NO_ERROR;
            });
            obj.build_expected();

            drive();
            check_result();
        end

        repeat (1000) begin
            obj.testtype = WITHOUT_RESET;
            assert(obj.randomize() with{
                error_type == CP_ERROR;
            });
            obj.build_expected();

            drive();
            check_result();
        end
        repeat (1000) begin
            obj.testtype = WITHOUT_RESET;
            assert(obj.randomize() with{
                error_type == DP_ERROR;
            });
            obj.build_expected();

            drive();
            check_result();
        end
        repeat (1000) begin
            obj.testtype = WITHOUT_RESET;
            assert(obj.randomize() with{
                error_type == OPCODE_ERROR;
            });
            obj.build_expected();

            drive();
            check_result();
        end
        repeat (1000) begin
            obj.testtype = WITHOUT_RESET;
            assert(obj.randomize() with{
                error_type == MSGCODE_ERROR;
            });
            obj.build_expected();

            drive();
            check_result();
        end

        repeat (1000) begin
            obj.testtype = WITHOUT_RESET;
            assert(obj.randomize() with{
                error_type == MSGSUBCODE_ERROR;
            });
            obj.build_expected();

            drive();
            check_result();
        end
        repeat (2000) begin
            obj.testtype = WITHOUT_RESET;
            assert(obj.randomize());
            obj.build_expected();

            drive();
            check_result();
        end

        #20;
        $display("PASS=%0d FAIL=%0d", pass_count, fail_count);
        $stop;
    end

    task apply_reset();
        obj.testtype = WITH_RESET;
        assert(obj.randomize() with {
            error_type == NO_ERROR;
        });

        obj.build_expected();
        drive();
        check_result();
        rst_n = 1;
    endtask

    task drive();
        rst_n  = obj.rst_n;
        msg_in = obj.msg_in;
        vld_in = obj.vld_in;
    endtask

    task check_result();
        @(negedge clk);

        if (msg_no_out == obj.exp_msg_no &&
            msginfo_r  == obj.exp_msginfo &&
            payload_r  == obj.exp_payload &&
            vld_r      == obj.exp_vld &&
            stall_rcvd == obj.exp_stall) begin

            pass_count++;
        end
        else begin
            fail_count++;
            $display("Mismatch @ %0t", $time);
            $display("inputs: =%0p ",
                     obj.hdr);

            $display("Expected: msg=%0s stall=%0b vld=%0b payload=%0d msginfo=%0d",
                     obj.exp_msg_no, obj.exp_stall, obj.exp_vld, obj.exp_payload, obj.exp_msginfo);
            $display("Got     : msg=%0s stall=%0b vld=%0b payload=%0d msginfo=%0d",
                     msg_no_out, stall_rcvd, vld_r, payload_r, msginfo_r);
        end
    endtask

endmodule