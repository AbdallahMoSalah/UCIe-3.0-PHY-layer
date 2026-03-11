`timescale 1ns/1ps

import LinK_Arbiter_pkg::*;

module Link_Arbiter_tb;

logic clk;

// LINK
logic [127:0] LINK_msg;
logic LINK_vld;
logic LINK_ready;

// adapter
logic [127:0] adapter_msg;
logic adapter_not_empty;
logic adapter_rd_en;

// downstream
logic mapper_ready;

// outputs
logic [127:0] msg_word_send;
logic valid_s;

int pass_count = 0;
int fail_count = 0;

Link_Arbiter_tb_class obj = new();

//////////////////////////////////////////////////
// DUT
//////////////////////////////////////////////////

Link_Arbiter dut (
    .LINK_msg(LINK_msg),
    .LINK_vld(LINK_vld),
    .LINK_ready(LINK_ready),

    .adapter_msg(adapter_msg),
    .adapter_not_empty(adapter_not_empty),
    .adapter_rd_en(adapter_rd_en),

    .mapper_ready(mapper_ready),

    .msg_word_send(msg_word_send),
    .valid_s(valid_s)
);

//////////////////////////////////////////////////
// clock
//////////////////////////////////////////////////

initial begin
    clk = 0;
    forever #5 clk = ~clk;
end

//////////////////////////////////////////////////
// main test
//////////////////////////////////////////////////

initial begin
// send 128-bit message on LINK
@(posedge clk);
mapper_ready = 1; 
LINK_msg = 0;
LINK_vld = 0;
adapter_msg = 128'h11111111_11111111_11111111_11111111;
adapter_not_empty = 0;
@(posedge clk);
mapper_ready = 1; 
LINK_msg = 128'hDEADBEEF_DEADBEEF_DEADBEEF_DEADBEEF;
LINK_vld = 1;
adapter_msg = 128'h11111111_11111111_11111111_11111111;
adapter_not_empty = 0;
// back to back msg 
@(posedge clk);
mapper_ready = 0; 
LINK_msg = 128'hD0000000_D0000000_DE000000_DEADBEEF;
LINK_vld = 1;
adapter_msg = 128'h11111111_11111111_11111111_11111111;
adapter_not_empty = 0;
@(posedge clk);
mapper_ready = 1; 
LINK_msg = 128'hD0000000_D0000000_DE000000_DEADBEEF;
LINK_vld = 1;
adapter_msg = 128'h11111111_11111111_11111111_11111111;
adapter_not_empty = 0;
//////
@(posedge clk);
mapper_ready = 1; 
LINK_msg = 128'hD0000000_D0000000_DEADBEEF_DEADBEEF;
LINK_vld = 0;
adapter_msg = 128'h11111111_11111111_11111111_11111111;
adapter_not_empty = 0;
// send adapter msg
@(posedge clk);
mapper_ready = 1; 
LINK_msg = 0;
LINK_vld = 0;
adapter_msg = 128'hCAFEBABE_CAFEBABE_CAFEBABE_CAFEBABE;
adapter_not_empty = 1;
@(posedge clk);
mapper_ready = 1; 
LINK_msg = 0;
LINK_vld = 0;
adapter_msg = 128'hCAFEBABE_CAFEBABE_CAFEBABE_CAFEBABE;
adapter_not_empty = 1;

/*    repeat (1000) begin

        assert(obj.randomize());

        obj.build_expected();

        drive();

        check();

    end
*/
    #20;
    $display("PASS = %0d", pass_count);
    $display("FAIL = %0d", fail_count);

    $stop;

end

//////////////////////////////////////////////////
// drive (synchronous)
//////////////////////////////////////////////////

task automatic drive();

@(posedge clk);

    LINK_msg          <= obj.LINK_msg;
    LINK_vld          <= obj.LINK_vld;

    adapter_msg       <= obj.adapter_msg;
    adapter_not_empty <= obj.adapter_not_empty;

    mapper_ready      <= obj.mapper_ready;

endtask

//////////////////////////////////////////////////
// check
//////////////////////////////////////////////////

task check();

@(negedge clk);

if (
    (msg_word_send !== obj.exp_msg) ||
    (valid_s       !== obj.exp_valid) ||
    (LINK_ready    !== obj.exp_LINK_ready) ||
    (adapter_rd_en !== obj.exp_adapter_rd_en)
)
begin

    $display("FAIL @%0t", $time);

    $display("LINK_vld=%0b adapter_vld=%0b mapper_ready=%0b",
        LINK_vld, adapter_not_empty, mapper_ready);

    $display("msg_exp=%h msg_dut=%h",
        obj.exp_msg, msg_word_send);

    $display("valid_exp=%0b valid_dut=%0b",
        obj.exp_valid, valid_s);

    $display("LINK_ready_exp=%0b LINK_ready_dut=%0b",
        obj.exp_LINK_ready, LINK_ready);

    $display("adapter_rd_en_exp=%0b adapter_rd_en_dut=%0b",
        obj.exp_adapter_rd_en, adapter_rd_en);

    fail_count++;

end
else begin
    pass_count++;
end

endtask

endmodule