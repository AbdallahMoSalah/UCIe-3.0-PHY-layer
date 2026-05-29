import sb_pkg::*;

module rdi_de_aggregator
(
    input  logic        clk,
    input  logic        rst_n,

    // Interface with Arbiter
    input  sb_packet_t  pl_msg,
    input  logic        pl_msg_vld,
    output logic        pl_msg_rdy,

    // Interface with Link/PHY layer
    output logic        traffic_req,
    input  logic        traffic_rdy,
    output logic [31:0] pl_cfg,
    output logic        pl_cfg_vld
);


    typedef enum logic [1:0] {
        IDLE,
        WAIT_READY,
        OUTPUT_STATE
    } state_t;

    state_t state, next_state;

    sb_packet_t   msg_reg;
    logic [127:0] msg_flat;
    logic [2:0]   chunk_cnt;
    logic [2:0]   expected_chunks;
    
    sb_opcode_e   in_opcode;
    logic [2:0]   next_expected_chunks;

    assign msg_flat = msg_reg;

    ////////////////////////////////////////
    // opcode decode
    ////////////////////////////////////////

    assign in_opcode = pl_msg.header.req.opcode;

    always_comb begin

        case(in_opcode)

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
                next_expected_chunks = 2;

            // header + 32 data
            SB_32_MEM_WRITE,
            SB_32_DMS_REG_WRITE,
            SB_32_CFG_WRITE,
            SB_COMPLETION_WITH_32_DATA:
                next_expected_chunks = 3;

            // header + 64 data
            SB_64_MEM_WRITE,
            SB_64_DMS_REG_WRITE,
            SB_64_CFG_WRITE,
            SB_COMPLETION_WITH_64_DATA,
            SB_MSG_WITH_64_DATA:
                next_expected_chunks = 4;

            default:
                next_expected_chunks = 2;

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
                if(pl_msg_vld) begin
                    next_state = WAIT_READY;
                end
            end 

            WAIT_READY: begin
                if(traffic_rdy) begin
                    next_state = OUTPUT_STATE;
                end
            end

            OUTPUT_STATE: begin
                if(chunk_cnt == expected_chunks) begin
                    if(pl_msg_vld) begin
                        next_state = WAIT_READY;
                    end
                    else begin
                        next_state = IDLE;
                    end
                end
            end

            default: next_state = IDLE;

        endcase

    end

    assign pl_msg_rdy = (state == IDLE) || (state == OUTPUT_STATE && chunk_cnt == expected_chunks);
    assign traffic_req  = (state == WAIT_READY);


    ////////////////////////////////////////
    // datapath
    ////////////////////////////////////////

    always_ff @(posedge clk or negedge rst_n) begin

        if(!rst_n) begin
            msg_reg         <= '0;
            chunk_cnt       <= 0;
            expected_chunks <= 0;
            pl_cfg_vld      <= 0;
            pl_cfg          <= 0;
        end

        else begin

            case(state)

            ///////////////////////////////////////
            IDLE:
            ///////////////////////////////////////
            begin
                if(pl_msg_vld) begin
                    msg_reg         <= pl_msg;
                    expected_chunks <= next_expected_chunks;
                end
                pl_cfg_vld <= 0;
                chunk_cnt  <= 0;
            end

            ///////////////////////////////////////
            WAIT_READY:
            ///////////////////////////////////////
            begin
                if (traffic_rdy) begin
                    chunk_cnt  <= 1;
                    pl_cfg_vld <= 1'b1;
                    // Send out the first chunk
                    pl_cfg     <= msg_reg[31:0]; 
                end
                else begin
                    pl_cfg_vld <= 0;
                end
            end

            ///////////////////////////////////////
            OUTPUT_STATE:
            ///////////////////////////////////////
            begin
                if(chunk_cnt == expected_chunks) begin
                    // Last chunk was alrdy sent out in the previous cycle
                    if(pl_msg_vld) begin
                        // Back to back consecutive packets: buffer and wait for rdy
                        msg_reg         <= pl_msg;
                        expected_chunks <= next_expected_chunks;
                    end
                    pl_cfg_vld <= 0;
                    chunk_cnt  <= 0;
                end
                else begin
                    pl_cfg_vld <= 1'b1;
                    chunk_cnt  <= chunk_cnt + 1;
                    case(chunk_cnt)
                        1: pl_cfg <= msg_flat[63:32];
                        2: pl_cfg <= msg_flat[95:64];
                        3: pl_cfg <= msg_flat[127:96];
                        default: pl_cfg <= msg_flat[31:0];
                    endcase
                end
            end

            default: ;

            endcase
        end
    end

endmodule
