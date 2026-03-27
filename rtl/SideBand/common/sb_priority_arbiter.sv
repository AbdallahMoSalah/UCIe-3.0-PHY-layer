module sb_priority_arbiter #(
    parameter int DATA_WIDTH = 128
) (
    // High Priority Input Interface
    input  logic [DATA_WIDTH-1:0] hp_msg,
    input  logic                  hp_vld,
    output logic                  hp_ready,

    // Low Priority Input Interface
    input  logic [DATA_WIDTH-1:0] lp_msg,
    input  logic                  lp_vld,
    output logic                  lp_ready,

    // Arbitrated Output Interface
    output logic [DATA_WIDTH-1:0] out_msg,
    output logic                  out_vld,
    input  logic                  out_ready
);

    always_comb begin
        // Priority 1: High Priority Input
        if (hp_vld) begin
            out_msg = hp_msg;
            out_vld = 1'b1;
        end
        // Priority 2: Low Priority Input
        else begin
            out_msg = lp_msg;
            out_vld = lp_vld;
        end

        hp_ready = out_ready && hp_vld;
        lp_ready = out_ready && lp_vld && !hp_vld;
    end

endmodule
