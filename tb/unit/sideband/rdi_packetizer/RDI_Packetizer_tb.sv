module RDI_Packetizer_tb;

    import sb_pkg::*;
    import RDI_Packetizer_tb_pkg::*;

    
    logic clk;
    logic rst_n;
    sb_rdi_msg_no_e RDI_msg_no_send;
    logic stall_send;
    logic RDI_vld_send;
    logic RDI_ready_send;
    logic push_ready;
    logic [127:0] RDI_msg;
    logic RDI_vld_out;
    
    int pass_count = 0;
    int fail_count = 0;

    sb_header_t dut_hdr;

    RDI_Packetizer_class RDI_Packetizer_object = new();
    // -----------------------------------
    // DUT
    // ----------------------------------   
    RDI_Packetizer DUT (
        .clk(clk),
        .rst_n(rst_n),
        .RDI_msg_no_send(RDI_msg_no_send),
        .stall_send(stall_send),
        .RDI_vld_send(RDI_vld_send),
        .RDI_ready(RDI_ready_send),
        .push_ready(push_ready),
        .RDI_msg(RDI_msg),
        .RDI_vld_out(RDI_vld_out)
    );

    // -----------------------------------
    // Clock
    // ----------------------------------   
    initial begin
        clk = 0;
        forever begin
            #5 clk = ~clk;
        end
    end


    // -----------------------------------
    // Test Sequence
    // ----------------------------------   
    initial begin
        push_ready   = 1;
        RDI_vld_send = 0;
        stall_send   = 0;
        apply_reset();
        
        repeat (1000) begin 
          RDI_Packetizer_object.testtype = WITHOUT_RESET;
          send_random();
          RDI_Packetizer_object.build_expected();
          
          checker_result();
          
        end
        repeat (1000) begin 
          RDI_Packetizer_object.testtype = NORMAL;
          send_random();
          RDI_Packetizer_object.build_expected();
          
          checker_result();
          
        end
 
        #20 $display("PASS = %0d", pass_count);
        $display("FAIL = %0d", fail_count);
        $stop;
    end

    // -----------------------------------
    // Reset
    // ----------------------------------   
    task apply_reset();
        RDI_Packetizer_object.testtype = WITH_RESET;
        assert(RDI_Packetizer_object.randomize());
        rst_n = RDI_Packetizer_object.rst_n;
        RDI_Packetizer_object.build_expected();
        checker_result();
        rst_n = 1;
    endtask

    // -----------------------------------
    // Random Send Task
    // ----------------------------------   
    task send_random(); 
        
        assert(RDI_Packetizer_object.randomize());
        
        rst_n = RDI_Packetizer_object.rst_n;
        RDI_msg_no_send = RDI_Packetizer_object.RDI_msg_no_send;
        stall_send = RDI_Packetizer_object.stall_send;
        RDI_vld_send = RDI_Packetizer_object.RDI_vld_send;
        push_ready = RDI_Packetizer_object.push_ready;

    endtask

    // -----------------------------------
    // Monitor + Checker
    // ----------------------------------   
    task checker_result();
        @(negedge clk);
        dut_hdr = sb_header_t'(RDI_msg[63:0]);
        
        if (dut_hdr === RDI_Packetizer_object.exp_hdr && RDI_vld_out === RDI_Packetizer_object.RDI_vld_out_exp) begin
            pass_count++;
        end else begin
            fail_count++;
            $display("Mismatch at time %0t", $time);
            $display("Expected = %h", RDI_Packetizer_object.exp_hdr);
            $display("Got      = %h", dut_hdr);
        end
        
    endtask

endmodule
