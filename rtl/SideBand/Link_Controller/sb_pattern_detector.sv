module sb_pattern_detector
#(
    parameter DATA_WIDTH = 64
)
(
    input  logic                     clk,
    input  logic                     rst_n,

    // control
    input  logic                     pattern_mode,

    // from deserializer
    input  logic [DATA_WIDTH-1:0]    des_data_rcvd,
    input  logic                     des_vld_rcvd,

    // to LTSM
    output logic                     det_pat_rcvd,

    // to unit_demapper
    output logic [DATA_WIDTH-1:0]    msg_rcvd,
    output logic                     msg_vld_rcvd
);

////////////////////////////////////////////////////////////
// Pattern check
////////////////////////////////////////////////////////////
localparam logic [63:0] CLOCK_PATTERN = 64'h5555_5555_5555_5555;
logic is_pattern;

assign is_pattern = (des_data_rcvd == CLOCK_PATTERN);

////////////////////////////////////////////////////////////
// Pattern counter
////////////////////////////////////////////////////////////

logic [1:0] pattern_cnt;

always_ff @(posedge clk or negedge rst_n) begin

    if(!rst_n) begin
        pattern_cnt <= 0;
        det_pat_rcvd <= 0;
    end

    else if(pattern_mode) begin

        if(des_vld_rcvd) begin

            if(is_pattern) begin

                if(pattern_cnt == 1) begin
                    det_pat_rcvd <= 1'b1;
                    pattern_cnt  <= 2'b0;
                end
                else begin
                    pattern_cnt  <= pattern_cnt + 1'b1;
                    det_pat_rcvd <= 1'b0;
                end

            end
            else begin
                pattern_cnt <= 0;
                det_pat_rcvd <= 0;
            end

        end
        else begin
            det_pat_rcvd <= 0;
        end

    end

    else begin
        pattern_cnt <= 0;
        det_pat_rcvd <= 0;
    end

end

////////////////////////////////////////////////////////////
// Data filtering
////////////////////////////////////////////////////////////

always_comb begin

    msg_rcvd   = '0;
    msg_vld_rcvd = 0;

    if(!pattern_mode && des_vld_rcvd) begin

        if(!is_pattern) begin
            msg_rcvd   = des_data_rcvd;
            msg_vld_rcvd = 1;
        end

    end

end

endmodule