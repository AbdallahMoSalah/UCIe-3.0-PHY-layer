module RDI_Packetizer_tb;

    import sb_pkg::*; 

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
    // Reset
    // ----------------------------------   
    task apply_reset();
        rst_n = 0;
        repeat (3) @(posedge clk);
        rst_n = 1;
    endtask

    // -----------------------------------
    // Expected Model using struct
    // ----------------------------------   
    function sb_header_t build_expected(
        input sb_rdi_msg_no_e msg,
        input logic stall
    ); 
        sb_header_t hdr;   
        hdr = '0;    
        hdr.opcode = SB_MSG_WITHOUT_DATA;
        hdr.srcid  = PHY;
        hdr.dstid  = REMOTE_PHY;
        hdr.dp     = 1'b0;  
        // msgcode
        if (msg <= DISABLE_REQ)
          hdr.msgcode = 8'h01; // Request
        else
          hdr.msgcode = 8'h02; // Respons   
        // subcode
        case (msg)
          ACTIVE_REQ, ACTIVE_RSP:         hdr.MsgSubcode = 8'h01;
          PMNAK_RSP:                      hdr.MsgSubcode = 8'h02;
          L1_REQ, L1_RSP:                 hdr.MsgSubcode = 8'h04;
          L2_REQ, L2_RSP:                 hdr.MsgSubcode = 8'h08;
          LINK_RESET_REQ, LINK_RESET_RSP: hdr.MsgSubcode = 8'h09;
          LINK_ERROR_REQ, LINK_ERROR_RSP: hdr.MsgSubcode = 8'h0A;
          RETRAIN_REQ, RETRAIN_RSP:       hdr.MsgSubcode = 8'h0B;
          DISABLE_REQ, DISABLE_RSP:       hdr.MsgSubcode = 8'h0C;
          default:                        hdr.MsgSubcode = 8'h00;
        endcase  
        // MsgInfo
        if (msg >= ACTIVE_RSP)
          hdr.MsgInfo = stall ? 16'hFFFF : 16'h0000;
        else
          hdr.MsgInfo = 16'h0000;    
        // Parity (even)
/*         sb_header_t tmp;
        tmp = hdr;
        tmp.cp = 0;
        tmp.dp = 0; */
        hdr.cp = ^hdr[61:0]; 
        return hdr;
    endfunction

    // -----------------------------------
    // Random Send Task
    // ----------------------------------   
    task send_random();
        @(posedge clk);  
        RDI_msg_no_send = sb_rdi_msg_no_e'($urandom_range(0,14));
        stall_send      = $urandom_range(0,1);
        RDI_vld_send    = 1;  
        wait (RDI_ready_send);  
        @(posedge clk);
        RDI_vld_send = 0;
    endtask   

    // -----------------------------------
    // Monitor + Checker
    // ----------------------------------   
    always @(posedge clk) begin
        if (RDI_vld_out) begin
            sb_header_t dut_hdr;
            sb_header_t exp_hdr;  
            dut_hdr = sb_header_t'(RDI_msg[63:0]);
            exp_hdr = build_expected(RDI_msg_no_send, stall_send); 
            if (dut_hdr === exp_hdr) begin
              pass_count++;
            end
            else begin
              fail_count++;
              $display("Mismatch at time %0t", $time);
              $display("Expected = %h", exp_hdr);
              $display("Got      = %h", dut_hdr);
            end
        end
    end

    // -----------------------------------
    // Test Sequence
    // ----------------------------------   
    initial begin
        push_ready = 1;
        RDI_vld_send = 0;
        stall_send = 0;   
        apply_reset();  
        // Directed
        repeat (5)
          send_random();  
        // Random with backpressure
        repeat (200) begin
          send_random();
          
          push_ready = 1;
        end  
        #20   
        $display("PASS = %0d", pass_count);
        $display("FAIL = %0d", fail_count);   
        $stop;
    end

endmodule