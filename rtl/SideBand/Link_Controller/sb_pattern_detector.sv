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
    input  logic [DATA_WIDTH-1:0]    packet_data,
    input  logic                     packet_done,

    // to LTSM
    output logic                     pattern_detected,

    // to demapper
    output logic [DATA_WIDTH-1:0]    data_out,
    output logic                     data_valid
);

////////////////////////////////////////////////////////////
// Pattern check
////////////////////////////////////////////////////////////

logic is_pattern;

assign is_pattern = &(packet_data ^ (packet_data >> 1));

////////////////////////////////////////////////////////////
// Pattern counter
////////////////////////////////////////////////////////////

logic [1:0] pattern_cnt;

always_ff @(posedge clk or negedge rst_n) begin

    if(!rst_n) begin
        pattern_cnt <= 0;
        pattern_detected <= 0;
    end

    else if(pattern_mode) begin

        if(packet_done) begin

            if(is_pattern) begin

                if(pattern_cnt == 1) begin
                    pattern_detected <= 1;
                    pattern_cnt <= 0;
                end
                else begin
                    pattern_cnt <= pattern_cnt + 1;
                end

            end
            else begin
                pattern_cnt <= 0;
                pattern_detected <= 0;
            end

        end

    end

    else begin
        pattern_cnt <= 0;
        pattern_detected <= 0;
    end

end

////////////////////////////////////////////////////////////
// Data filtering
////////////////////////////////////////////////////////////

always_comb begin

    data_out   = '0;
    data_valid = 0;

    if(!pattern_mode && packet_done) begin

        if(!is_pattern) begin
            data_out   = packet_data;
            data_valid = 1;
        end

    end

end

endmodule