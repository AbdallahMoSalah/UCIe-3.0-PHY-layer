module rdi_rx_arbiter
(
    // Interface with De_Aggregator
    output logic [127:0] out_msg,
    output logic         out_vld,
    input  logic         out_ready,

    // Interface with Completion FIFO (High Priority)
    input  logic [127:0] comp_msg,
    input  logic         comp_vld,
    output logic         comp_ready,

    // Interface with Request FIFO (Low Priority)
    input  logic [127:0] req_msg,
    input  logic         req_vld,
    output logic         req_ready,

    // Interface with Credit Counter
    input  logic         no_crd
);

    always_comb begin
        // Default values
        out_msg    = '0;
        out_vld    = 1'b0;
        comp_ready = 1'b0;
        req_ready  = 1'b0;

        // Priority 1: Completion FIFO
        if (comp_vld) begin
            out_msg    = comp_msg;
            out_vld    = 1'b1;
            comp_ready = out_ready;
        end
        // Priority 2: Request FIFO (Only if credits are available)
        else if (req_vld && !no_crd) begin
            out_msg    = req_msg;
            out_vld    = 1'b1;
            req_ready  = out_ready;
        end
    end

endmodule
