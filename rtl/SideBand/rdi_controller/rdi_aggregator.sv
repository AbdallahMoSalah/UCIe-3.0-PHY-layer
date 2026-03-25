import sb_pkg::*;

module rdi_aggregator
(
    input  logic        clk,
    input  logic        rst_n,

    input  logic [31:0] lp_cfg,
    input  logic        lp_cfg_vld,

    output sb_packet_t lp_msg,
    output logic         lp_msg_vld
);


typedef enum logic [1:0] {
    IDLE,
    COLLECT,
    OUTPUT
} state_t;

state_t state, next_state;

logic [127:0] packet_reg;
logic [2:0]   chunk_cnt;
logic [2:0]   expected_chunks;

sb_opcode_e opcode;

logic [2:0]   cycle_count;
////////////////////////////////////////
// opcode decode
////////////////////////////////////////
assign opcode = sb_opcode_e'(lp_cfg[4:0]);

always_comb begin

    case(opcode)

        // header only
        SB_32_MEM_READ, //32 mem read
        SB_32_DMS_REG_READ,
        SB_32_CFG_READ,
        SB_64_MEM_READ,
        SB_64_DMS_REG_READ,
        SB_64_CFG_READ,
        SB_COMPLETION_WITHOUT_DATA,
        SB_MSG_WITHOUT_DATA,
        SB_MNGT_PORT_MSG_WITHOUT_DATA:
            cycle_count = 2;

        // header + 32 data
        SB_32_MEM_WRITE,
        SB_32_DMS_REG_WRITE,
        SB_32_CFG_WRITE,
        SB_COMPLETION_WITH_32_DATA:
            cycle_count = 3;

        // header + 64 data
        SB_64_MEM_WRITE,
        SB_64_DMS_REG_WRITE,
        SB_64_CFG_WRITE,
        SB_COMPLETION_WITH_64_DATA,
        SB_MSG_WITH_64_DATA:
            cycle_count = 4;

        default:
            cycle_count = 2;

    endcase

end


////////////////////////////////////////
// state register
////////////////////////////////////////

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        state <= IDLE;
    else
        state <= next_state;
end


////////////////////////////////////////
// next state logic
////////////////////////////////////////

always_comb begin

    next_state = state;

    case(state)

        IDLE:
        if(lp_cfg_vld)
            next_state = COLLECT;

        COLLECT:
        if(lp_cfg_vld && (chunk_cnt == expected_chunks-1))
            next_state = OUTPUT;

        OUTPUT:
            if(lp_cfg_vld)
                next_state = COLLECT;
            else 
                next_state = IDLE;

    endcase

end


////////////////////////////////////////
// datapath
////////////////////////////////////////

always_ff @(posedge clk or negedge rst_n) begin

    if(!rst_n) begin
        packet_reg      <= '0;
        chunk_cnt       <= 0;
        expected_chunks <= 0;

    end

    else begin

        case(state)

        ///////////////////////////////////////
        IDLE:
        ///////////////////////////////////////

        begin
            chunk_cnt <= 0;

            if(lp_cfg_vld) begin

                packet_reg[31:0] <= lp_cfg;
                packet_reg[127:32] <= '0;

                expected_chunks <= cycle_count;

                chunk_cnt <= 1;

            end
        end


        ///////////////////////////////////////
        COLLECT:
        ///////////////////////////////////////

        begin

            if(lp_cfg_vld) begin

                packet_reg[32*chunk_cnt +: 32] <= lp_cfg;

                chunk_cnt <= chunk_cnt + 1;

            end

        end


        ///////////////////////////////////////
        OUTPUT:
        ///////////////////////////////////////

        begin

            chunk_cnt <= 0;

            if(lp_cfg_vld) begin

                packet_reg[31:0] <= lp_cfg;
                packet_reg[127:32] <= '0;

                expected_chunks <= cycle_count;

                chunk_cnt <= 1;

            end

        end

        endcase
    end
end

always_comb begin

    if(!rst_n) begin
        lp_msg_vld = 0;
        lp_msg     = 0;
    end
    else begin
        case(state)

            OUTPUT:
            begin
                lp_msg_vld = 1;
                lp_msg     = sb_packet_t'(packet_reg);
            end
            default : lp_msg_vld = 0;

        endcase
    end
    
end


endmodule