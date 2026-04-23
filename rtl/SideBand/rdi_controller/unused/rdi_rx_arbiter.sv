module rdi_rx_arbiter
(
    // Interface with De_Aggregator
    output logic [127:0] out_msg,
    output logic         out_vld,
    input  logic         out_rdy,

    // Interface with Completion FIFO (High Priority)
    input  logic [127:0] comp_msg,
    input  logic         comp_vld,
    output logic         comp_rdy,

    // Interface with Request FIFO (Low Priority)
    input  logic [127:0] req_msg,
    input  logic         req_vld,
    output logic         req_rdy,

    // Interface with Credit Counter
    input  logic         no_crd
);

    always_comb begin
    
        // Priority 1: Completion FIFO
        if (comp_vld) begin
            out_msg    = comp_msg;
            out_vld    = 1'b1;
        end
        // Priority 2: Request FIFO (Only if credits are available)
        else begin
            out_vld    = req_vld;
            out_msg    = req_msg;
        end
        comp_rdy = out_rdy && comp_vld;
        req_rdy  = out_rdy && req_vld && !comp_vld && !no_crd;

    end

endmodule
