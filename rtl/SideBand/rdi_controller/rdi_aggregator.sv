import sb_pkg::*;

module rdi_aggregator
(
    input  logic        clk,
    input  logic        rst_n,

    input  logic [31:0] lp_cfg,
    input  logic        lp_cfg_vld,

    output sb_packet_t   lp_msg,
    output logic         lp_msg_vld
);


    typedef enum logic [1:0] {
        IDLE,
        COLLECT,
        OUTPUT
    } state_t;

    state_t state, next_state;

    logic [95:0] packet_reg;
    logic [2:0]   chunk_cnt;
    logic [2:0]   expected_chunks;
    logic [2:0]   cycle_count;
    logic [127:0] lp_msg_reg;
    sb_opcode_e opcode;
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
        if(!rst_n) begin
            state <= IDLE;
        end
        else begin
            state <= next_state;
        end
    end


    ////////////////////////////////////////
    // next state logic
    ////////////////////////////////////////

    always_comb begin

        next_state = state;

        case(state)

            IDLE: begin

                if(lp_cfg_vld) begin
                    if(cycle_count == 2) begin
                        next_state = OUTPUT;
                    end
                    else begin
                        next_state = COLLECT;
                    end
                end

            end 

            COLLECT: begin
                if(lp_cfg_vld && (chunk_cnt == expected_chunks-2)) begin
                    next_state = OUTPUT;

                end

            end

            OUTPUT: begin
                if(lp_cfg_vld) begin
                    next_state = IDLE;
                end
            end

            default: next_state = IDLE;

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
            lp_msg_reg      <= 0;
        end

        else begin

            case(state)

            ///////////////////////////////////////
            IDLE:
            ///////////////////////////////////////

            begin
                chunk_cnt <= 0;
                lp_msg_vld <= 0;

                if(lp_cfg_vld) begin

                    packet_reg[31:0] <= lp_cfg;

                    expected_chunks <= cycle_count;

                    chunk_cnt <= 1;

                end
            end

            ///////////////////////////////////////
            COLLECT:
            ///////////////////////////////////////

            begin

                lp_msg_vld <= 0;
                if(lp_cfg_vld) begin

                    packet_reg[32*chunk_cnt +: 32] <= lp_cfg;

                    chunk_cnt <= chunk_cnt + 1;

                end


            end


            ///////////////////////////////////////
            OUTPUT:
            ///////////////////////////////////////

            begin
                lp_msg_vld <= 1;
                if(lp_cfg_vld && (chunk_cnt == expected_chunks-1)) begin

                    case(expected_chunks)

                        2: 
                        begin

                            lp_msg_reg  <= {64'b0,lp_cfg,packet_reg[31 : 0]};
                        end

                        3: 
                        begin
                            lp_msg_reg  <= {32'b0,lp_cfg,packet_reg[63 : 0]};
                        end

                        4:
                        begin
                            lp_msg_reg  <= {lp_cfg,packet_reg[95 : 0]};
                        end

                        default: ;

                    endcase

                end

            end

            default: ;

            endcase
        end
    end

    assign lp_msg = sb_packet_t'(lp_msg_reg);

endmodule