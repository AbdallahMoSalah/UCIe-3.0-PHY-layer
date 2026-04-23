module sb_priority_arbiter #(
    parameter int DATA_WIDTH = 128
) (
    // High Priority Input Interface
    input  logic [DATA_WIDTH-1:0] hip_msg,
    input  logic                  hip_vld,
    output logic                  hip_rdy,

    // Low Priority Input Interface
    input  logic [DATA_WIDTH-1:0] lop_msg,
    input  logic                  lop_vld,
    output logic                  lop_rdy,

    // Arbitrated Output Interface
    output logic [DATA_WIDTH-1:0] out_msg,
    output logic                  out_vld,
    input  logic                  out_rdy
);
    
    always_comb begin
        // Priority 1: High Priority Input
        if (hip_vld) begin
            out_msg = hip_msg;
            out_vld = 1'b1;
        end
        // Priority 2: Low Priority Input
        else begin
            out_msg = lop_msg;
            out_vld = lop_vld;
        end

        hip_rdy = out_rdy && hip_vld;
        lop_rdy = out_rdy && lop_vld && !hip_vld;
    end

endmodule
