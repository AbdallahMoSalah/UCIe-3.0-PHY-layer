module RDI_DePacketizer_tb;

    import sb_pkg::*;
    import rdi_codec_pkg::*;
    import RDI_DePacketizer_tb_pkg::*;

    logic clk;
    logic rst_n;

    logic [127:0] trn_msg_rcvd;
    logic trn_vld_rcvd;

    sb_rdi_msg_no_e RDI_msg_no_rcvd;
    logic stall_rcvd;
    logic RDI_vld_rcvd;

    int pass_count = 0;
    int fail_count = 0;

    RDI_DePacketizer_class obj = new();

    // --------------------------
    // DUT
    // --------------------------

    RDI_DePacketizer DUT (
        .clk(clk),
        .rst_n(rst_n),
        .trn_msg_rcvd(trn_msg_rcvd),
        .trn_vld_rcvd(trn_vld_rcvd),
        .RDI_msg_no_rcvd(RDI_msg_no_rcvd),
        .stall_rcvd(stall_rcvd),
        .RDI_vld_rcvd(RDI_vld_rcvd)
    );

    // --------------------------
    // Clock
    // --------------------------

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end


    // --------------------------
    // Test
    // --------------------------

    initial begin

        apply_reset();

        repeat (1000) begin
            obj.testtype = WITHOUT_RESET;
            assert(obj.randomize() with {
                error_type == NO_ERROR;
            });

            obj.build_expected();
            drive();
            check_result();
        end

        repeat (1000) begin
            obj.testtype = NORMAL;
            assert(obj.randomize());
            
            obj.error_type = NO_ERROR;
            obj.build_expected();
            drive();
            check_result();
        end
        repeat (100) begin
            obj.testtype = NORMAL;
            assert(obj.randomize() with {
                error_type == PARITY_ERROR;
            });
            
            
            obj.build_expected();
            drive();
            check_result();
        end
        repeat (100) begin
            obj.testtype = NORMAL;
            assert(obj.randomize() with {
                error_type == OPCODE_ERROR;
            });
            
            obj.build_expected();
            drive();
            check_result();
        end
        repeat (100) begin
            obj.testtype = NORMAL;
            assert(obj.randomize() with {
                error_type == MSGCODE_ERROR;
            });
            
            obj.build_expected();
            drive();
            check_result();
        end
        
        repeat (100) begin
            obj.testtype = NORMAL;
            assert(obj.randomize() with {
                error_type == MSGSUBCODE_ERROR;
            });
            
            obj.build_expected();
            drive();
            check_result();
        end

        repeat (1000) begin
            obj.testtype = NORMAL;
            assert(obj.randomize());
            
            obj.build_expected();
            drive();
            check_result();
        end

        #20;
        $display("PASS = %0d", pass_count);
        $display("FAIL = %0d", fail_count);
        $stop;
    end

    task drive();
        rst_n           = obj.rst_n;
        trn_msg_rcvd   = obj.LINK_msg;
        trn_vld_rcvd   = obj.trn_vld_rcvd;
    endtask

    task apply_reset();
        obj.testtype = WITH_RESET;
        assert(obj.randomize());
        
        obj.error_type = NO_ERROR;
        obj.build_expected();
        drive();
        check_result();
        rst_n = 1;
    endtask

    // --------------------------
    // Checker
    // --------------------------

    task check_result();
        @(negedge clk);

        if (RDI_msg_no_rcvd == obj.exp_msg_no &&
            stall_rcvd     == obj.exp_stall &&
            RDI_vld_rcvd   == obj.exp_vld) begin

            pass_count++;
        end
        else begin
            fail_count++;
            $display("Mismatch @ %0t", $time);

            $display("inputs: =%0p ",
                     obj.hdr);

            $display("Expected: msg=%0s stall=%0b vld=%0b",
                     obj.exp_msg_no, obj.exp_stall, obj.exp_vld);
            $display("Got     : msg=%0s stall=%0b vld=%0b",
                     RDI_msg_no_rcvd, stall_rcvd, RDI_vld_rcvd);
        end
    endtask


endmodule