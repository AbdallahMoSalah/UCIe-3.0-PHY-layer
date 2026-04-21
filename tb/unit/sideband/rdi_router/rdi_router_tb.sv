`timescale 1ns / 1ps

import sb_pkg::*;

// ==========================================================
// Transaction Class with Constraints
// ==========================================================
class demux_seq_item;
    rand sb_dstid_e     dst_id;
    rand logic          is_req;
    rand logic [127:0]  payload;
    rand sb_opcode_e    opcode;

    // Constraints to ensure valid opcodes corresponding to the is_req flag
    constraint opcode_c {
        if (is_req) {
            // MSB = 0 implies it's a request
            opcode inside {SB_32_MEM_READ, SB_32_CFG_WRITE, SB_64_MEM_READ, SB_64_CFG_WRITE, SB_32_DMS_REG_WRITE};
        } else {
            // MSB = 1 implies it's a message or completion
            opcode inside {SB_COMPLETION_WITHOUT_DATA, SB_MSG_WITHOUT_DATA, SB_COMPLETION_WITH_64_DATA, SB_MNGT_PORT_MSG_WITHOUT_DATA};
        }
    }

    constraint dst_id_c {
        dst_id inside {LOCAL_PHY, REMOTE_PHY, REMOTE_ADAPTER, MNGT_PORT_DST, REMOTE_REG_ACCESS};
    }

    // Function to assemble the final 128-bit message word
    function logic [127:0] get_msg();
        logic [127:0] msg = payload;
        msg[58:56] = dst_id;
        msg[4:0]   = opcode;
        return msg;
    endfunction
endclass

// ==========================================================
// Testbench Module (Combinational Checker)
// ==========================================================
module rdi_router_tb;

    // Interfaces
    logic         rst_n;
    logic         reset;
    
    logic [127:0] rdi_msg;
    logic         rdi_vld;
    logic         rdi_ready;
    
    logic [127:0] reg_msg;
    logic         reg_vld;
    logic         reg_ready;
    
    logic [127:0] Adapter_msg_send;
    logic         Adapter_vld_send;
    logic         Adapter_ready;

    // DUT Instantiation
    rdi_router dut (
        .rst_n(rst_n),
        .reset(reset),
        
        .rdi_msg(rdi_msg),
        .rdi_vld(rdi_vld),
        .rdi_ready(rdi_ready),
        
        .reg_msg(reg_msg),
        .reg_vld(reg_vld),
        .reg_ready(reg_ready),
        
        .Adapter_msg_send(Adapter_msg_send),
        .Adapter_vld_send(Adapter_vld_send),
        .Adapter_ready(Adapter_ready)
    );

    int errors = 0;
    int tests_run = 0;

    // ----------------------------------------------------------------
    // Simple Scoreboard / Predictor for Combinational Demux
    // ----------------------------------------------------------------
    task check_outputs(logic is_req, logic [127:0] exp_msg, sb_dstid_e dst_id, logic active_reset);
        
        // Expected Outputs
        logic exp_reg_vld;
        logic exp_adp_vld;
        logic exp_rdi_rdy;
        
        exp_reg_vld = 0;
        exp_adp_vld = 0;
        exp_rdi_rdy = 0;
        
        if (active_reset) begin
            // In reset mode
            if (is_req) begin
                exp_reg_vld = rdi_vld;
                exp_rdi_rdy = reg_ready;
            end else begin
                // Drop normal messages / comps
                exp_adp_vld = 0;
                exp_reg_vld = 0;
                exp_rdi_rdy = 1'b1; // consume to pop
            end
        end else begin
            // Normal mode
            if (dst_id == LOCAL_PHY) begin
                exp_reg_vld = rdi_vld;
                exp_rdi_rdy = reg_ready;
            end else begin
                exp_adp_vld = rdi_vld;
                exp_rdi_rdy = Adapter_ready;
            end
        end

        // Check assertions (Scoreboard functionality)
        if (reg_vld !== exp_reg_vld) begin
            $error("[%0t] reg_vld mismatch! Act: %b, Exp: %b", $time, reg_vld, exp_reg_vld);
            errors++;
        end
        if (Adapter_vld_send !== exp_adp_vld) begin
            $error("[%0t] Adapter_vld_send mismatch! Act: %b, Exp: %b", $time, Adapter_vld_send, exp_adp_vld);
            errors++;
        end
        if (rdi_ready !== exp_rdi_rdy) begin
            $error("[%0t] rdi_ready mismatch! Act: %b, Exp: %b", $time, rdi_ready, exp_rdi_rdy);
            errors++;
        end
        
        // Data path is passed through straight in comb mode
        if (reg_msg !== exp_msg) begin
            $error("[%0t] reg_msg mismatch! Act: %h, Exp: %h", $time, reg_msg, exp_msg);
            errors++;
        end
        if (Adapter_msg_send !== exp_msg) begin
            $error("[%0t] Adapter_msg_send mismatch! Act: %h, Exp: %h", $time, Adapter_msg_send, exp_msg);
            errors++;
        end
    endtask

    // ----------------------------------------------------------------
    // Master Test Generation Thread
    // ----------------------------------------------------------------
    initial begin
        demux_seq_item item;
        
        $display("==================================================");
        $display("[%0t] Starting Class-Based Combinational Checker TB...", $time);
        
        // Init
        rst_n = 0;
        reset = 0;
        rdi_msg = 0;
        rdi_vld = 0;
        reg_ready = 1;
        Adapter_ready = 1;
        
        #10;
        rst_n = 1;
        
        for (int i = 0; i < 5000; i++) begin
            item = new();
            if (!item.randomize()) $error("Randomization failed!");
            
            // Form completely random inputs on every cycle
            reset         = ($urandom() % 100) < 15; // 15% probability of reset state
            reg_ready     = ($urandom() % 100) < 50; // 50% stall chance
            Adapter_ready = ($urandom() % 100) < 50; // 50% stall chance
            
            rdi_msg = item.get_msg();
            rdi_vld = ($urandom() % 100) < 80;       // 80% Valid traffic
            
            // Advance simulation delta to let combinational logic settle
            #5; 
            
            // Check outputs dynamically via the scoreboard
            check_outputs(item.is_req, item.get_msg(), item.dst_id, reset);
            
            if (rdi_vld) begin
                 tests_run++;
            end
        end
        
        $display("==================================================");
        $display("Total Transactions Checked: %0d", tests_run);
        
        if (errors == 0)
            $display("[%0t] ALL TESTS PASSED SUCCESSFULLY! :-)", $time);
        else
            $display("[%0t] TESTS FAILED WITH %0d ERRORS! :-(", $time, errors);
            
        $display("==================================================");
        
        $finish;
    end

endmodule
