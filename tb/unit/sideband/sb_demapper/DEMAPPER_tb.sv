class Demapper_Tx;
    rand logic [127:0] msg_data;
    logic [4:0] opcode;
    logic       is_128bit;

    // --- 1. Constraint Block ---
    constraint opcode_c {
        msg_data[4:0] inside {
            // Valid 64-bit opcodes
            5'b00000, 5'b00010, 5'b00100, 5'b01000, 5'b01010, 5'b01100, 5'b10000, 5'b10010, 5'b10111,
            // Valid 128-bit opcodes
            5'b00001, 5'b00011, 5'b00101, 5'b01001, 5'b01011, 5'b01101, 5'b10001, 5'b11001, 5'b11000, 5'b11011
        };
    }

    // --- 2. Covergroup ---
    covergroup demapper_cg;
        option.per_instance = 1;
        
        // التفتيش على الـ Opcode
        cp_opcode: coverpoint opcode {
            bins op_64bit  = {5'b00000, 5'b00010, 5'b00100, 5'b01000, 5'b01010, 5'b01100, 5'b10000, 5'b10010, 5'b10111};
            bins op_128bit = {5'b00001, 5'b00011, 5'b00101, 5'b01001, 5'b01011, 5'b01101, 5'b10001, 5'b11001, 5'b11000, 5'b11011};
        }
        
        // التفتيش على طول الرسالة
        cp_is_128bit: coverpoint is_128bit {
            bins short_msg = {1'b0};
            bins long_msg  = {1'b1};
        }
        
        // التقاطع (Cross Coverage) للتأكيد إن الاتنين متوافقين
        cross cp_opcode, cp_is_128bit;
    endgroup

    // --- 3. Constructor ---
    function new();
        demapper_cg = new(); // بنخلق الـ Covergroup في الميموري
    endfunction

    // --- 4. Post-Randomize Function ---
    function void post_randomize();
        opcode = msg_data[4:0];
        
        if (opcode == 5'b00001 || opcode == 5'b00011 || opcode == 5'b00101 || 
            opcode == 5'b01001 || opcode == 5'b01011 || opcode == 5'b01101 || 
            opcode == 5'b10001 || opcode == 5'b11001 || opcode == 5'b11000 || opcode == 5'b11011) begin
            is_128bit = 1'b1;
        end else begin
            is_128bit = 1'b0;
        end
        
        
        demapper_cg.sample(); 
    endfunction
endclass
module DEMAPPER_tb;
   logic         clk;
   logic         rst_n;
    

    logic [63:0]  msg_rcvd;    
    logic         msg_vld_rcvd;

  
    logic [127:0] msg_word_rcvd;
    logic         word_vld_rcvd;

    unit_demapper dut (
    .clk(clk),
    .rst_n(rst_n),
    .msg_rcvd(msg_rcvd),      
    .msg_vld_rcvd( msg_vld_rcvd),    
    .msg_word_rcvd (msg_word_rcvd), 
    .word_vld_rcvd(word_vld_rcvd)
    );
        int pass_cnt = 0;
        int fail_cnt = 0;

        Demapper_Tx tx = new();

   initial begin
        clk = 0; 
        forever #5 clk = ~clk;
    end
    initial begin
        
        
        
        
        rst_n = 0;
        msg_vld_rcvd = 0;
        msg_rcvd = 64'b0;
        
        repeat(2) @(negedge clk);
        rst_n = 1;
        
        for (int i = 1; i <= 20; i++) begin
            assert (tx.randomize());
            
           
            @(posedge clk);
            msg_rcvd = tx.msg_data[63:0];
            msg_vld_rcvd = 1'b1;
            
            if (tx.is_128bit) begin
                @(posedge clk);
                msg_vld_rcvd = 1'b0;
                @(posedge clk);
                @(posedge clk);
                @(posedge clk);
                msg_vld_rcvd = 1'b1;
                msg_rcvd = tx.msg_data[127:64];
            end
           #1;
            
            
            if (word_vld_rcvd !== 1'b1) begin
                $error("[FAIL] Packet %0d: word_vld_rcvd is NOT high!", i);
                fail_cnt++;
            end else begin
               
                if (tx.is_128bit) begin
                    
                    if (msg_word_rcvd === tx.msg_data) begin
                        $display("[PASS] Packet %0d: 128-bit Reconstructed correctly.", i);
                        pass_cnt++;
                    end else begin
                        $error("[FAIL] Packet %0d: 128-bit Data Mismatch!", i);
                        fail_cnt++;
                    end
                end else begin
                    
                    if (msg_word_rcvd === {64'b0, tx.msg_data[63:0]}) begin
                        $display("[PASS] Packet %0d: 64-bit Padded with zeros correctly.", i);
                        pass_cnt++;
                    end else begin
                        $error("[FAIL] Packet %0d: 64-bit Data Mismatch!", i);
                        fail_cnt++;
                    end
                end
            end

            
            @(posedge clk);
            msg_vld_rcvd = 1'b0;
            
            
            repeat(1) @(posedge clk); 
        end
        
        
        $display("\n==================================================");
        $display(" Total Packets Injected : 20");
        $display(" Packets Passed         : %0d", pass_cnt);
        $display(" Packets Failed         : %0d", fail_cnt);
        $display("==================================================\n");
        $display(" Functional Coverage = %0.2f %%", tx.demapper_cg.get_inst_coverage());
        $finish; 
    end
endmodule