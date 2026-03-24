module rdi_aggregator
(
    input  logic        clk,
    input  logic        rst_n,

    input  logic [31:0] lp_cfg,
    input  logic        lp_cfg_vld,

    output logic [127:0] lp_msg,
    output logic         lp_msg_vld
);

typedef enum logic [1:0] {
    IDLE,
    COLLECT,
    OUTPUT
} state_t;

state_t state, next_state;

logic [127:0] packet_reg;
logic [1:0]   chunk_cnt;
logic [1:0]   expected_chunks;

////////////////////////////////////////
// opcode decode
////////////////////////////////////////

function automatic logic [1:0] get_chunks(input logic [4:0] opcode);

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
            get_chunks = 2;

        // header + 32 data
        SB_32_MEM_WRITE,
        SB_32_DMS_REG_WRITE,
        SB_32_CFG_WRITE,
        SB_COMPLETION_WITH_32_DATA:
            get_chunks = 3;

        // header + 64 data
        SB_64_MEM_WRITE,
        SB_64_DMS_REG_WRITE,
        SB_64_CFG_WRITE,
        SB_COMPLETION_WITH_64_DATA,
        SB_MSG_WITH_64_DATA:
            get_chunks = 4;

        default:
            get_chunks = 2;

    endcase

endfunction


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
        lp_msg_vld      <= 0;
        lp_msg          <= 0;
    end

    else begin

        lp_msg_vld <= 0;

        case(state)

        ///////////////////////////////////////
        IDLE:
        ///////////////////////////////////////

        begin
            chunk_cnt <= 0;

            if(lp_cfg_vld) begin

                packet_reg[31:0] <= lp_cfg;
                packet_reg[127:32] <= '0;

                expected_chunks <= get_chunks(lp_cfg[4:0]);

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

            lp_msg     <= packet_reg;
            lp_msg_vld <= 1;

        end

        endcase
    end
end

endmodule