import sb_pkg::*;

module sb_fifo_demux(
    input logic [127:0] data_in,
    input logic         vld_in,
    // Req msg path
    output logic [127:0] req_msg_data,
    output logic         req_msg_vld,
    
    // Completion path
    output logic [127:0] comp_data,
    output logic         comp_vld
);

    logic is_completion;
    sb_opcode_e opcode;

    assign opcode = sb_opcode_e'(data_in[4:0]);

    always_comb begin

        case(opcode)
           
            SB_COMPLETION_WITHOUT_DATA,
            SB_COMPLETION_WITH_64_DATA:
                is_completion = 1;
            default:
                is_completion = 0;

        endcase
    end

    always_comb begin
        req_msg_vld = 0;
        comp_vld    = 0;

        req_msg_data = data_in;
        comp_data    = data_in;

        if (vld_in) begin
            if (is_completion) begin
                comp_vld = 1;
            end 
            else begin
                req_msg_vld = 1;
            end
        end
    end
endmodule