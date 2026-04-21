`timescale 1ns/1ps

import sb_pkg::*;
import UCIe_pkg::*;
import Packetizer_tb_pkg::*;
import msg_codec_pkg::*;

module Packetizer_tb;

  
  logic         clk;
  logic         rst_n;

  logic [63:0]  msg_data_send;
  logic [15:0]  msg_info_send;
  msg_no_e      msg_no_send;
  logic         valid_send;
  logic         LINK_ready;
  logic         stall_send;

  logic [127:0] LINK_msg;
  logic         LINK_vld;
  logic         ready;

  int pass_count = 0;
  int fail_count = 0;

Packetizer_class obj = new();
//////////////////////////////////////////////////////////////////
//////////////////////////// DUT ///////////////////////////////
//////////////////////////////////////////////////////////////////
  Packetizer dut (
    .clk            (clk),
    .rst_n          (rst_n),
    .msg_data_send  (msg_data_send),
    .msg_info_send  (msg_info_send),
    .msg_no_send    (msg_no_send),
    .valid_send     (valid_send),
    .LINK_ready     (LINK_ready),
    .stall_send     (stall_send),
    .LINK_msg       (LINK_msg),
    .LINK_vld       (LINK_vld),
    .ready          (ready)
  );

//////////////////////////////////////////////////////////////////
//////////////////////////// inital //////////////////////////////
//////////////////////////////////////////////////////////////////
  
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

initial begin
    apply_reset();
    
    repeat (10000) begin
      assert(obj.randomize());
      drive();
      obj.build_expected();
      check();
    end
        #20 $display("PASS = %0d", pass_count);
        $display("FAIL = %0d", fail_count);
        $stop;
  end
  
//////////////////////////////////////////////////////////////////
//////////////////////////// TASKS ///////////////////////////////
//////////////////////////////////////////////////////////////////
task automatic apply_reset();

    assert (obj.randomize());
    drive();
    rst_n = 1'b0;
    obj.build_expected();
    check();
    assert (obj.randomize());
    drive();
    obj.build_expected();
    rst_n = 1'b1;
    check();
endtask //automatic

task automatic drive();
    rst_n = obj.rst_n;
    msg_data_send = obj.msg_data_send;
    msg_info_send = obj.msg_info_send;
    msg_no_send   = obj.msg_no_send;
    valid_send    = obj.valid_send;
    LINK_ready    = obj.LINK_ready;
    stall_send    = obj.stall_send;
endtask //automatic

task check();
@(negedge clk);
  if (
    (LINK_vld !== obj.exp_vld) ||
    (LINK_msg !== obj.exp_msg) || 
    (ready !== obj.exp_ready)
  ) begin
   $display("FAIL @%0t | vld_exp=%0b vld_dut=%0b | msg_exp=%h msg_dut=%h | valid_send=%0b ready=%0b",
          $time,
          obj.exp_vld, LINK_vld,
          obj.exp_msg, LINK_msg,
          valid_send, LINK_ready);
    $display("msgno= %s",msg_no_send);
    $display("exmsgcode=%s,msgcode=%s",obj.hdr.msg.msgcode, dut.header_reg.msg.msgcode);
    $display("exmsgsubcode=%h,msgsubcode=%h",obj.hdr.msg.MsgSubcode, dut.header_reg.msg.MsgSubcode);
    
    fail_count++;
  end else begin
    //$display("Test Passed: Exp LINK_vld=%b, LINK_msg=%h, ready=%b and got Link_vld=%b, LINK_msg=%h, ready=%b @time=%0t",
       //   obj.exp_vld, obj.exp_msg, obj.exp_ready, LINK_vld, LINK_msg, ready ,$time);
    pass_count++;
  end
endtask


 /* // Timeout Protection
  initial begin
    #1000000;
    $fatal("Simulation Timeout!");
  end
*/
endmodule